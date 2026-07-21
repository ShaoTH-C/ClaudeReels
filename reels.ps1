param(
    [ValidateSet('ensure','pause','resume','toggle','on','off','open','close','site','sites','status')]
    [string]$Action = 'ensure',
    [string]$Site
)

$ErrorActionPreference = 'Stop'

$StateFile  = Join-Path $PSScriptRoot 'state.json'
$LegacyFile = Join-Path $PSScriptRoot 'state.txt'
$LogFile    = Join-Path $PSScriptRoot 'reels.log'
$ProfileDir = Join-Path $env:LOCALAPPDATA 'ClaudeReels\profile'

$Sites = [ordered]@{
    instagram = @{ Name = 'Instagram Reels'; Url = 'https://www.instagram.com/reels/';  W = 412;  H = 760 }
    youtube   = @{ Name = 'YouTube Shorts';  Url = 'https://www.youtube.com/shorts/';   W = 412;  H = 760 }
    tiktok    = @{ Name = 'TikTok';          Url = 'https://www.tiktok.com/foryou';     W = 412;  H = 760 }
    douyin    = @{ Name = '抖音';             Url = 'https://www.douyin.com/discover';   W = 412;  H = 760 }
    xhs       = @{ Name = '小红书';           Url = 'https://www.xiaohongshu.com/explore'; W = 460; H = 800 }
    bilibili  = @{ Name = 'Bilibili';        Url = 'https://www.bilibili.com/';         W = 1000; H = 640 }
    yt        = @{ Name = 'YouTube';         Url = 'https://www.youtube.com/';          W = 1000; H = 640 }
}

function Write-Log([string]$m) {
    try { Add-Content -Path $LogFile -Value ("{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Action, $m) -Encoding UTF8 } catch {}
}

function Get-State {
    $raw = $null
    if (Test-Path $StateFile) {
        try { $raw = Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
    }
    $enabled = $true
    if ($raw -and $null -ne $raw.enabled) { $enabled = [bool]$raw.enabled }
    elseif (Test-Path $LegacyFile)        { $enabled = ((Get-Content $LegacyFile -Raw).Trim() -ne 'off') }

    # always rebuild with every field present -- adding a property to a
    # ConvertFrom-Json object throws on 5.1
    [pscustomobject]@{
        enabled = $enabled
        site    = if ($raw -and $raw.site) { [string]$raw.site } else { 'instagram' }
        url     = if ($raw -and $raw.url)  { [string]$raw.url }  else { '' }
    }
}

function Set-State($s) {
    $json = $s | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($StateFile, $json, (New-Object Text.UTF8Encoding $false))
    if (Test-Path $LegacyFile) { Remove-Item $LegacyFile -Force -ErrorAction SilentlyContinue }
}

function Resolve-Site([string]$key) {
    $s = Get-State
    if (-not $key) { $key = $s.site }
    if ($Sites.Contains($key)) {
        $d = $Sites[$key]
        return @{ Key = $key; Name = $d.Name; Url = $d.Url; W = $d.W; H = $d.H }
    }
    if ($key -match '^https?://') {
        return @{ Key = $key; Name = $key; Url = $key; W = 412; H = 760 }
    }
    return $null
}

function Get-CurrentSite {
    $s = Get-State
    if ($s.url) { return @{ Key = $s.site; Name = $s.site; Url = $s.url; W = 412; H = 760 } }
    $r = Resolve-Site $s.site
    if ($r) { return $r }
    return Resolve-Site 'instagram'
}

function Get-Browser {
    @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:LocalAppData}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-ReelsProcs {
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*ClaudeReels\profile*' }
}

function Test-Open { [bool](Get-ReelsProcs) }

# read off the live command line rather than stored: keeps state.json write-only
# for explicit user actions, so an async hook can't clobber a site change
function Get-ReelsPort {
    foreach ($p in Get-ReelsProcs) {
        if ($p.CommandLine -match '--remote-debugging-port=(\d+)') { return [int]$Matches[1] }
    }
    return 0
}

function Get-FreePort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $l.Start()
    $p = $l.LocalEndpoint.Port
    $l.Stop()
    return $p
}

function Invoke-Cdp([string]$Expression) {
    $port = Get-ReelsPort
    if (-not $port) { Write-Log 'no cdp port'; return $null }

    $ws = $null
    try {
        $all = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json" -TimeoutSec 4
        $t = $all | Where-Object { $_.type -eq 'page' -and $_.url -notmatch '^(chrome|devtools)' } | Select-Object -First 1
        if (-not $t) { Write-Log 'no page target'; return $null }

        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $ct = [System.Threading.CancellationToken]::None
        [void]$ws.ConnectAsync([Uri]$t.webSocketDebuggerUrl, $ct).GetAwaiter().GetResult()

        $msg = @{
            id     = 1
            method = 'Runtime.evaluate'
            params = @{ expression = $Expression; returnByValue = $true; awaitPromise = $true; userGesture = $true }
        } | ConvertTo-Json -Depth 6 -Compress

        $b = [Text.Encoding]::UTF8.GetBytes($msg)
        [void]$ws.SendAsync([ArraySegment[byte]]::new($b), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()

        $buf = [ArraySegment[byte]]::new([byte[]]::new(65536))
        $sb  = New-Object Text.StringBuilder
        do {
            $r = $ws.ReceiveAsync($buf, $ct).GetAwaiter().GetResult()
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf.Array, 0, $r.Count))
        } while (-not $r.EndOfMessage)

        $parsed = $sb.ToString() | ConvertFrom-Json
        if ($parsed.result.exceptionDetails) {
            Write-Log ('js: ' + $parsed.result.exceptionDetails.text)
            return $null
        }
        return $parsed.result.result.value
    } catch {
        Write-Log ('cdp: ' + $_.Exception.Message)
        return $null
    } finally {
        if ($ws) { try { $ws.Dispose() } catch {} }
    }
}

# a plain pause() loses: feed sites re-assert play() within ~1s.
# the capture-phase listener re-pauses anything that starts while the guard is on.
$JsPause = @'
(function(){
  var g = window.__reels;
  if (!g) {
    g = window.__reels = { on:false };
    document.addEventListener('play', function(e){
      if (g.on && e.target && e.target.tagName === 'VIDEO') e.target.pause();
    }, true);
  }
  g.on = true;
  var n = 0;
  document.querySelectorAll('video').forEach(function(v){ if (!v.paused) { v.pause(); n++; } });
  return n;
})()
'@

# resuming a remembered element is unreliable -- feeds recycle <video> nodes and
# re-pause anything that isn't the active reel. always target whatever is centred
# now, and re-assert a few times to ride out the site's own state machine.
$JsResume = @'
(function(){
  var g = window.__reels || (window.__reels = { on:false });
  g.on = false;
  function centred(){
    var vids = [].slice.call(document.querySelectorAll('video')).filter(function(v){
      var r = v.getBoundingClientRect(); return r.width > 0 && r.height > 0;
    });
    var cy = window.innerHeight / 2;
    vids.sort(function(a,b){
      var ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
      return Math.abs(ra.top + ra.height/2 - cy) - Math.abs(rb.top + rb.height/2 - cy);
    });
    return vids[0];
  }
  if (!centred()) return 0;
  var tries = 0;
  (function kick(){
    if (g.on) return;
    var v = centred();
    if (v && v.paused) { var p = v.play(); if (p && p.catch) p.catch(function(){}); }
    if (++tries < 4) setTimeout(kick, 400);
  })();
  return 1;
})()
'@

$JsStatus = @'
(function(){
  var v = document.querySelector('video');
  return JSON.stringify({
    url: location.host,
    videos: document.querySelectorAll('video').length,
    paused: v ? v.paused : null,
    guard: !!(window.__reels && window.__reels.on)
  });
})()
'@

function Open-Window {
    if (Test-Open) { return }
    $cur = Get-CurrentSite
    $exe = Get-Browser
    if (-not $exe) { Start-Process $cur.Url; return }

    $port = Get-FreePort

    Add-Type -AssemblyName System.Windows.Forms
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x  = $wa.Right - $cur.W - 40
    $y  = $wa.Top + 60

    $argLine = @(
        "--user-data-dir=`"$ProfileDir`""
        "--app=`"$($cur.Url)`""
        "--remote-debugging-port=$port"
        "--window-size=$($cur.W),$($cur.H)"
        "--window-position=$x,$y"
        '--no-first-run'
        '--no-default-browser-check'
    ) -join ' '

    Start-Process -FilePath $exe -ArgumentList $argLine
    Write-Log "opened $($cur.Name) on port $port"
}

function Close-Window {
    Get-ReelsProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Set-Site([string]$key) {
    $r = Resolve-Site $key
    if (-not $r) { "unknown site '$key' -- run: reels.ps1 -Action sites"; return }

    $st = Get-State
    if ($r.Key -match '^https?://') { $st.site = 'custom'; $st.url = $r.Url }
    else { $st.site = $r.Key; $st.url = '' }
    Set-State $st

    if (Test-Open) {
        $esc = $r.Url -replace "'", "\'"
        [void](Invoke-Cdp "location.href='$esc'; 'go'")
    }
    "site: $($r.Name)"
}

function Show-Menu {
    $keys = @($Sites.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $k = $keys[$i]
        "  [{0}] {1,-16} {2}" -f ($i + 1), $k, $Sites[$k].Name
    }
    '  [c] custom URL'
    $pick = Read-Host 'pick'
    if ($pick -eq 'c') {
        $u = Read-Host 'url'
        if ($u) { Set-Site $u }
        return
    }
    $n = 0
    if ([int]::TryParse($pick, [ref]$n) -and $n -ge 1 -and $n -le $keys.Count) { Set-Site $keys[$n - 1] }
    else { 'cancelled' }
}

try {
    switch ($Action) {
        'ensure' {
            $st = Get-State
            if ($st.enabled) {
                if (Test-Open) { [void](Invoke-Cdp $JsResume) } else { Open-Window }
            }
        }
        'pause'  { if (Test-Open) { [void](Invoke-Cdp $JsPause) } }
        'resume' { if (Test-Open) { [void](Invoke-Cdp $JsResume) } }
        'open'   { Open-Window }
        'close'  { Close-Window }
        'on'     { $st = Get-State; $st.enabled = $true;  Set-State $st; Open-Window; 'reels: ON' }
        'off'    { $st = Get-State; $st.enabled = $false; Set-State $st; Close-Window; 'reels: OFF' }
        'toggle' {
            $st = Get-State
            if ($st.enabled) { $st.enabled = $false; Set-State $st; Close-Window; 'reels: OFF (closed)' }
            else             { $st.enabled = $true;  Set-State $st; Open-Window;  'reels: ON (opened)' }
        }
        'site'  { if ($Site) { Set-Site $Site } else { Show-Menu } }
        'sites' {
            $cur = (Get-State).site
            foreach ($k in $Sites.Keys) {
                "{0} {1,-10} {2,-16} {3}" -f $(if ($k -eq $cur) { '*' } else { ' ' }), $k, $Sites[$k].Name, $Sites[$k].Url
            }
        }
        'status' {
            $st = Get-State
            $en = if ($st.enabled) { 'ON' } else { 'OFF' }
            $op = if (Test-Open) { 'open' } else { 'closed' }
            $cur = Get-CurrentSite
            "reels: $en  |  window $op  |  site $($cur.Name)"
            if (Test-Open) {
                $port = Get-ReelsPort
                "port:  $port"
                $j = Invoke-Cdp $JsStatus
                if ($j) { "page:  $j" } else { 'page:  <no cdp>' }
            }
        }
    }
} catch {
    Write-Log ('fatal: ' + $_.Exception.Message)
}

exit 0
