# Pausing a feed site

`video.pause()` is not enough. I assumed it was, shipped it, and the video kept playing.

Instagram and TikTok re-assert playback about a second after you pause them. On TikTok the clock ran
on from 0.08s to 1.45s after a "successful" pause. The site does not accept that decision from
anyone but itself.

## The guard

What works is a capture-phase `play` listener on `document` that re-pauses anything the site starts
while the guard is on:

```js
document.addEventListener('play', function (e) {
  if (g.on && e.target && e.target.tagName === 'VIDEO') e.target.pause();
}, true);
```

Capture phase specifically. `play` doesn't bubble, so a listener registered the normal way never
sees it.

Measured with the guard installed: clock frozen at 1.43s across 8 seconds, then resumed cleanly to
8.73s.

## Resume

Don't restore the `<video>` element you paused. Feeds recycle their nodes, so by the time you come
back that element is out of the DOM or scrolled off, and the site stops it again immediately.

Take whatever is centred in the viewport at resume time, and re-assert `play()` about four times
over 1.2s to outlast the site's own state machine.

## Why CDP

The window launches with a private `--remote-debugging-port`, and pause/resume connect to it over
the DevTools Protocol.

The alternatives don't work. Media keys hit Spotify. `SendKeys` needs focus, so it would eat
keystrokes while you're typing a prompt. CDP touches exactly one window and never steals focus.

The port is read back off the process command line rather than trusted from `state.json`, so the
script self-heals if state is stale. `DevToolsActivePort` is only written when the port is `0`, so
it can't be used here. Chrome picks a fresh free port on every launch, because when a port is taken
Chrome does not fall back to another one, it just starts the browser with no devtools server.

## Editing reels.ps1

`reels.ps1` is UTF-8 **with BOM** and has to stay that way. Windows PowerShell 5.1 reads a BOM-less
`.ps1` as ANSI, which mangles the `抖音` and `小红书` entries in the site table badly enough to break
quote pairing, and then reports a syntax error about forty lines away from the actual damage.
`.editorconfig` pins it. To check:

```powershell
[IO.File]::ReadAllBytes("reels.ps1")[0..2]   # must be 239,187,191
```

The three hooks are all `async`, and `reels.ps1` ends in a hard `exit 0` with every exception going
to `reels.log`. A broken hook must never be able to block a prompt.
