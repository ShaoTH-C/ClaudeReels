# ClaudeReels

A reels-sized browser window that plays while Claude Code is working and **pauses the moment Claude
finishes**. It resumes by itself the next time you send a prompt. Pick which site it opens.

```
you send a prompt   ->  window opens (or video resumes)
Claude finishes     ->  video pauses
you send a prompt   ->  video resumes
```

## Install

1. Put this folder anywhere you like.
2. Double-click **`install.cmd`**.
3. Restart Claude Code so it picks up the hooks.
4. Double-click **`pick-site.cmd`** and choose a site.

That's it. The installer wires the Claude Code hooks for you, backs up your existing
`settings.json` first, and leaves every other hook and setting untouched. Running it
twice is safe.

To remove it: double-click **`uninstall.cmd`**.

### First run

The window uses its own browser profile (`%LOCALAPPDATA%\ClaudeReels\profile`), so the first time
you'll see a logged-out site. Log in once — it persists, and it never touches your normal browser
tabs or cookies.

## Everyday use

| Double-click | What it does |
|---|---|
| `toggle-reels.cmd` | ON / OFF switch |
| `pick-site.cmd` | Choose which site to open |
| `install.cmd` | Wire up the hooks |
| `uninstall.cmd` | Remove the hooks |

From a terminal:

```powershell
$r = "E:\Extra Projects\ClaudeReels\reels.ps1"

& $r -Action status              # switch state, window state, current site
& $r -Action toggle              # flip ON/OFF
& $r -Action on                  # enable + open
& $r -Action off                 # disable + close
& $r -Action sites               # list sites (* = current)
& $r -Action site -Site youtube  # switch site (navigates a live window)
& $r -Action site                # interactive picker
& $r -Action pause               # pause now
& $r -Action resume              # resume now
```

## Sites

`instagram` `youtube` `tiktok` `douyin` `xhs` `bilibili` `yt`

Anything else works too — pass a URL:

```powershell
& $r -Action site -Site https://www.twitch.tv/directory
```

Site + window size live in the `$Sites` table at the top of `reels.ps1`; add your own there if you
want it in the picker.

## How the pausing works

The window is launched with a private Chrome DevTools port. `pause` and `resume` connect to it and
run a little JavaScript in the page.

A plain `video.pause()` does **not** hold — feed sites re-start playback within about a second.
Measured on TikTok: after a naive pause the clock ran on from 0.08s to 1.45s. So `pause` also
installs a capture-phase `play` listener that re-pauses anything the site tries to start, and
`resume` removes it. Measured with the guard: clock frozen at 1.43s across 8 seconds, then resumed
cleanly to 8.73s.

`resume` always targets whichever video is centred in the viewport and re-asserts play a few times
over ~1.2s, because feeds recycle their `<video>` elements and briefly fight a scripted play.

## Which hooks it installs

| Hook | Action | Why |
|---|---|---|
| `UserPromptSubmit` | `ensure` | You sent a prompt: open the window, or resume if it's already open |
| `Stop` | `pause` | Claude finished its turn |
| `SessionEnd` | `pause` | Session closed |

All three are `async` so they never add latency to your prompts. `ensure` only opens a window when
one isn't already open, so it fires every prompt but launches at most once.

## Known issues

- **YouTube Shorts can close its own window.** YouTube redirects to `?themeRefresh=1` shortly after
  load, which sometimes kills a Chrome `--app` window. The next prompt reopens it. The other sites
  don't do this.
- **Pause only reaches the main document.** Video inside a cross-origin iframe won't be paused.
  None of the built-in sites put their feed video in one.
- **If the debugging port can't bind**, pause/resume quietly do nothing rather than breaking your
  prompt. Check `reels.log` and `-Action status` (it prints the live port and page state).
- **Upgrading from an older build**: close the existing window once. Windows opened by the old
  script have no debugging port, so pause can't reach them. `install.cmd` does this for you.

## Files

| File | |
|---|---|
| `reels.ps1` | everything: window, state, CDP, pause/resume, site picker |
| `install.ps1` | hook installer / uninstaller (`-Uninstall`, `-SettingsPath`) |
| `*.cmd` | double-click wrappers |
| `state.json` | switch state, current site, last port |
| `reels.log` | why pause/resume didn't work, when it doesn't |

`reels.ps1` is UTF-8 **with BOM** on purpose — Windows PowerShell 5.1 reads a BOM-less script as
ANSI and mangles the non-ASCII site names.
