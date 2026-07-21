param(
    [switch]$Uninstall,
    [string]$SettingsPath
)

$ErrorActionPreference = 'Stop'

$Reels    = Join-Path $PSScriptRoot 'reels.ps1'
$Settings = if ($SettingsPath) { $SettingsPath } else { Join-Path $env:USERPROFILE '.claude\settings.json' }
$Tag      = 'ClaudeReels'

if (-not (Test-Path $Reels)) { throw "reels.ps1 not found next to install.ps1" }

function Read-Settings {
    if (-not (Test-Path $Settings)) { return [ordered]@{} }
    $txt = [IO.File]::ReadAllText($Settings)
    if (-not $txt.Trim()) { return [ordered]@{} }
    $txt | ConvertFrom-Json
}

# ConvertFrom-Json gives PSCustomObjects; walk them into ordered hashtables so we
# can add keys and round-trip without clobbering settings we don't own
function ToHash($o) {
    if ($o -is [Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ToHash $p.Value }
        return $h
    }
    # leading comma stops PowerShell unwrapping a 1-element array into a scalar,
    # which would turn "hooks":[{...}] into "hooks":{...} and break the config
    if ($o -is [Object[]]) { return ,@($o | ForEach-Object { ToHash $_ }) }
    return $o
}

function Save-Settings($h) {
    if (Test-Path $Settings) {
        $bak = "$Settings.bak-reels"
        Copy-Item $Settings $bak -Force
        "  backup   -> $bak"
    }
    $dir = Split-Path $Settings -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = $h | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($Settings, $json, (New-Object Text.UTF8Encoding $false))
}

function New-HookEntry([string]$action, [int]$timeout, [bool]$async) {
    $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1}' -f $Reels, $action
    $inner = [ordered]@{ type = 'command'; command = $cmd; timeout = $timeout }
    if ($async) { $inner['async'] = $true }
    [ordered]@{ hooks = @($inner) }
}

function Test-Ours($entry) {
    foreach ($h in @($entry.hooks)) {
        if ($h -and $h.command -and $h.command -like "*$Tag*") { return $true }
    }
    return $false
}

# drop every hook entry pointing at this project, on every event
function Remove-Ours($root) {
    if (-not $root.Contains('hooks')) { return $root }
    $hooks = $root['hooks']
    foreach ($evt in @($hooks.Keys)) {
        $kept = @(@($hooks[$evt]) | Where-Object { -not (Test-Ours $_) })
        if ($kept.Count) { $hooks[$evt] = $kept } else { $hooks.Remove($evt) }
    }
    if ($hooks.Keys.Count -eq 0) { $root.Remove('hooks') }
    return $root
}

$root = ToHash (Read-Settings)
if ($root -isnot [Collections.Specialized.OrderedDictionary]) { $root = [ordered]@{} }

"settings : $Settings"
$root = Remove-Ours $root

if ($Uninstall) {
    Save-Settings $root
    & $Reels -Action close
    "  hooks    -> removed"
    ""
    "ClaudeReels uninstalled. reels.ps1 and your browser profile were left in place."
    "Delete the profile too with:  Remove-Item -Recurse -Force `"$env:LOCALAPPDATA\ClaudeReels`""
    exit 0
}

if (-not $root.Contains('hooks')) { $root['hooks'] = [ordered]@{} }
$hooks = $root['hooks']

# UserPromptSubmit = Claude starts working  -> open if needed, else resume
# Stop            = Claude finished          -> pause
$wanted = [ordered]@{
    UserPromptSubmit = New-HookEntry 'ensure' 15 $true
    Stop             = New-HookEntry 'pause'  10 $true
    SessionEnd       = New-HookEntry 'pause'  10 $true
}

foreach ($evt in $wanted.Keys) {
    $existing = @()
    if ($hooks.Contains($evt)) { $existing = @($hooks[$evt]) }
    $hooks[$evt] = @($existing + $wanted[$evt])
    "  hook     -> $evt"
}

Save-Settings $root

# a window left over from an older build has no debugging port, so pause/resume
# would silently no-op until it is reopened
& $Reels -Action close

""
"ClaudeReels installed."
"  reels.ps1 : $Reels"
& $Reels -Action status
""
"Next:"
"  1. Restart Claude Code (or run /hooks) so it picks up the new hooks."
"  2. Double-click pick-site.cmd to choose a site."
"  3. Double-click toggle-reels.cmd to turn it on."
"     First run shows a logged-out site - log in once, it persists."
