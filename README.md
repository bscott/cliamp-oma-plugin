# CLIAMP for Omarchy

An [Omarchy](https://omarchy.org) bar widget for [CLIAMP](https://cliamp.stream), the retro
terminal music player. See what's playing at a glance and control playback without leaving
your workflow — works with the CLIAMP TUI and with `cliamp --daemon` alike. When Spotify or
YouTube playback is detected, the widget follows and controls those too.

![The CLIAMP widget's popup, showing the now-playing track, transport controls, and the source picker](preview.png)

## Features

- **Now playing in the bar** — play/pause state glyph plus a scrolling title · artist label.
- **One-click transport** — left click toggles play/pause, middle click skips ahead, and the
  scroll wheel moves through the playlist.
- **Detail popup** — right click opens track details with album art, previous / play-pause /
  next / stop buttons, a progress bar for regular tracks, a LIVE badge for radio streams, and
  the current playlist position.
- **Spotify and YouTube, when detected** — the Spotify desktop app and YouTube / YouTube Music
  (in a browser or as a PWA) are picked up over MPRIS. The widget auto-follows whichever
  source is playing, preferring cliamp, and the popup grows a picker to pin a source when more
  than one is around.
- **Scriptable** — the plugin's service exposes IPC methods, so keybindings get the same
  on-screen-display feedback as Omarchy's built-in media controls.

## Requirements

- Omarchy with the plugin-capable shell (`omarchy plugin` available).
- [`cliamp`](https://github.com/bjarneo/cliamp) on your `PATH`. The widget talks to the running
  instance through cliamp's own remote-control CLI, so no MPRIS proxy is needed.
- Spotify and YouTube support needs nothing extra — those sources are detected through the
  MPRIS players the apps already register.

## Install

```bash
omarchy plugin add https://github.com/bscott/cliamp-oma-plugin.git --enable
```

Then place the **CLIAMP** widget in your bar from the Omarchy bar settings (category *Media*).

## Usage

| Input | Action |
|-------|--------|
| Left click | Play / pause |
| Middle click | Next track |
| Scroll wheel | Previous / next track |
| Right click | Open the detail popup |

The widget dims to a note glyph while no media source is reachable. Start `cliamp` (or
`cliamp --daemon` for headless playback), Spotify, or a YouTube tab and it lights back up
on the next poll. All controls target the active source, shown in the popup's picker.

### Settings

Configurable from the widget's bar settings:

| Setting | Default | Description |
|---------|---------|-------------|
| Refresh interval | 2 s | How often to poll `cliamp status --json`. |
| Max label width | 180 px | Label width before the title scrolls. |
| Hide when unavailable | off | Remove the widget entirely while cliamp isn't running. |

### IPC / keybindings

The service registers the `cliamp` IPC target, so playback can be driven from scripts or
Hyprland keybindings with on-screen-display feedback:

```bash
omarchy-shell cliamp playPause
omarchy-shell cliamp next
omarchy-shell cliamp previous
omarchy-shell cliamp stop
omarchy-shell cliamp status   # JSON playback state, including active/detected sources
omarchy-shell cliamp source spotify   # pin a source: cliamp, spotify, or youtube
```

Example Hyprland binding (`~/.config/hypr/bindings.conf`):

```ini
bindd = SUPER SHIFT, P, Toggle CLIAMP playback, exec, omarchy-shell cliamp playPause
```

Plain `cliamp toggle` works too — the IPC route just adds the OSD popup.

## Development

```bash
git clone https://github.com/bscott/cliamp-oma-plugin.git
ln -s "$PWD/cliamp-oma-plugin" ~/.config/omarchy/plugins/io.github.bscott.cliamp
omarchy plugin validate ~/.config/omarchy/plugins/io.github.bscott.cliamp
omarchy plugin enable io.github.bscott.cliamp
```

## License

[MIT](LICENSE)
