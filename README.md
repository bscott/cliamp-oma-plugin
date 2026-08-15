# CLIAMP for Omarchy

An [Omarchy](https://omarchy.org) bar widget for [CLIAMP](https://cliamp.stream), the retro
terminal music player. See what's playing at a glance and control playback without leaving
your workflow — works with the CLIAMP TUI and with `cliamp --daemon` alike.

## Features

- **Now playing in the bar** — play/pause state glyph plus a scrolling title · artist label.
- **One-click transport** — left click toggles play/pause, middle click skips ahead, and the
  scroll wheel moves through the playlist.
- **Detail popup** — right click opens track details with previous / play-pause / next / stop
  buttons, a progress bar for regular tracks, a LIVE badge for radio streams, and the current
  playlist position.
- **Scriptable** — the plugin's service exposes IPC methods, so keybindings get the same
  on-screen-display feedback as Omarchy's built-in media controls.

## Requirements

- Omarchy with the plugin-capable shell (`omarchy plugin` available).
- [`cliamp`](https://github.com/bjarneo/cliamp) on your `PATH`. The widget talks to the running
  instance through cliamp's own remote-control CLI, so no MPRIS proxy is needed.

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

The widget dims to a note glyph while no cliamp instance is reachable. Start `cliamp` (or
`cliamp --daemon` for headless playback) and it lights back up on the next poll.

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
omarchy-shell cliamp status   # JSON playback state
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
