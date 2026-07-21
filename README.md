# ClaudeReels

Opens a reels-sized Chrome window while Claude Code is working, and pauses the video the moment it
stops.

## What it does

Every time you send a prompt, this script:

- Opens a phone-shaped Chrome window, or resumes the one that's already open
- Loads Instagram Reels, TikTok, YouTube Shorts, or whichever site you picked
- Pauses the video when Claude finishes its turn
- Resumes it on your next prompt

## Prerequisites

- Windows
- Chrome or Edge
- Claude Code

## Installation

1. Put this folder anywhere you like.
2. Double-click `install.cmd`. It backs up your `settings.json` first and leaves your other hooks
   alone. Running it twice is fine.
3. Restart Claude Code so it re-reads the hooks.
4. Double-click `pick-site.cmd` and choose a site.

`uninstall.cmd` reverses all of it.

The window runs on its own Chrome profile, so the first time you'll see a logged-out page. Log in
once and it sticks. Your normal browser session isn't touched.

## Usage

Just use Claude Code normally. `toggle-reels.cmd` switches it off and on, `pick-site.cmd` changes
sites.

From a terminal:

```powershell
& .\reels.ps1 -Action status     # switch state, window state, current site, live CDP port
& .\reels.ps1 -Action toggle
& .\reels.ps1 -Action pause      # or resume
```

## Customization

Built-in sites are `instagram`, `youtube`, `tiktok`, `douyin`, `xhs`, `bilibili`, `yt`. Any URL
works too:

```powershell
& .\reels.ps1 -Action site -Site https://www.twitch.tv/directory
```

Edit the `$Sites` table at the top of `reels.ps1` to get your own into the picker:

```powershell
$Sites = [ordered]@{
    instagram = @{ Name = 'Instagram Reels'; Url = 'https://www.instagram.com/reels/'; W = 412; H = 760 }
    tiktok    = @{ Name = 'TikTok';          Url = 'https://www.tiktok.com/foryou';    W = 412; H = 760 }
}
```

## Notes

`video.pause()` on its own doesn't hold. Instagram and TikTok restart playback within about a
second, so there's a capture-phase guard that re-pauses them. [doc/pausing.md](doc/pausing.md) has
the measurements.

YouTube Shorts sometimes closes its own window after a `?themeRefresh=1` redirect. The next prompt
reopens it. No other site does this.

Video inside a cross-origin iframe won't pause. None of the built-in sites put theirs in one.
