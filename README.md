# aeris-tiler

![aeris-tiler: Hyprland-style tiling for macOS](assets/banner.png)

Hyprland-style tiling for macOS, built on open-source tools: yabai tiles, skhd and Hammerspoon handle the keys, sketchybar is an optional top bar. Ported from AerisOS, a Hyprland desktop on Linux.

It works with System Integrity Protection (SIP) on. Window animations need SIP off, so they are not included. Switching spaces uses macOS's own keys: ⌃← / ⌃→ and ⌃1–9.

## Layouts

Each space has one of three layouts. ⌘⌥← cycles them; the bar shows the current one.

| Layout | Command | What it does |
|---|---|---|
| TILE | `tile` | yabai bsp, like Hyprland dwindle: new windows split the focused one, resizing a window resizes its neighbours. |
| GRID | `grid` | Swiss grid of 12 columns: 1 window full, 2 halves, 3 or more in 3 \| 6 \| 3 columns. Re-tiles when windows open or close. Sizes are fixed: resize shakes the window. |
| FLOAT | `floating` | Plain macOS: windows stay where you put them. Opens Magnet if it is installed. |

## Keys

| Keys | Action |
|---|---|
| ⌃⌥ ← → ↑ ↓ | Focus the window in that direction |
| ⌃⌥⌘ ← → ↑ ↓ | Swap with the window in that direction |
| ⌘⌃ ← → ↑ ↓ | Resize: hold to keep resizing, tap for 60 px. The border moves in the arrow's direction; neighbours follow in TILE. |
| ⌃⌥J | Flip the split between rows and columns |
| ⌘⌥↑ | Maximize (keeps the window in the layout, unlike the green button) |
| ⌘⌥↓ | Float / unfloat the window |
| ⌘⌥→ | Move the window to the other display |
| ⌘⌥← | Cycle layout: tile → grid → float |
| ⌘⇧Space | Hide / show the bar (sketchybar) |
| ⌃← / ⌃→ | Switch space (native macOS) |
| ⌃⌥⌘ 1–9 | Move the window to space 1–9 |
| ⌘K | Keysheet: a searchable list of these keys |

Mouse: ⌃ + drag moves a window, ⌃ + right-drag resizes it. Focus follows the mouse. New windows open on the display under the mouse.

Hammerspoon also adds a Linux-style clipboard: selecting text copies it, right-click in a text field pastes (⌥ + right-click for the normal menu).

## Install

**With an AI agent** (Claude, ChatGPT, Gemini, Codex or any other): paste this prompt. The agent checks your Mac, asks before each change, installs the tools, walks you through the permissions and tests the result.

> Set up aeris-tiler on my Mac. Follow https://raw.githubusercontent.com/hjbarraza/aeris-tiler/main/SETUP.md step by step and ask me before each change.

**By hand:**

1. Install the tools. Homebrew asks you to trust the two third-party taps first:

   ```bash
   brew trust asmvik/formulae
   brew trust felixkratz/formulae
   brew install asmvik/formulae/yabai asmvik/formulae/skhd jq
   brew install --cask hammerspoon
   brew install felixkratz/formulae/sketchybar   # optional: the top bar
   ```

2. Install the configs, which backs up any file it replaces:

   ```bash
   git clone https://github.com/hjbarraza/aeris-tiler && cd aeris-tiler && ./install.sh
   ```

3. Grant Accessibility to yabai, skhd and Hammerspoon in System Settings → Privacy & Security.

## What is in here

`home/` mirrors `$HOME`; `install.sh` copies it there.

| File | Job |
|---|---|
| `home/.config/yabai/yabairc` | Tiling: bsp, 8 px padding and gaps, focus follows mouse, utility apps float, new windows open on the display under the mouse. |
| `home/.config/skhd/skhdrc` | Hotkeys. Each `# comment` names the group shown in Keysheet. |
| `home/.hammerspoon/init.lua` | Hold-to-resize (it sees the key release, which skhd cannot) and the mouse clipboard. |
| `home/.local/bin/grid`, `tile`, `floating`, `layout` | The three layouts, and `layout` to print or cycle the current one. |
| `home/.config/sketchybar/sketchybarrc` | Optional top bar: spaces, layout, Tailscale, network, volume, battery, clock. |
| `home/.warp/settings.toml` | Warp terminal settings. |
| `keysheet/` | ⌘K cheat sheet, built by `install.sh` into `~/Applications/Keysheet.app`. |
| `assets/` | Banner: `banner.svg` (source, uses the Söhne typeface), `banner.png`, and `banner-social.png` at 1280 × 640 for the GitHub social preview. |
| `SETUP.md` | Step-by-step setup written for AI agents (and people): checks, questions, install, permissions, tests, custom shortcuts, undo. |
| `resize-matrix.py` | Test: resizes every window on the current space in every direction and layout, and checks the result. About 3 min; keep hands off the mouse and keyboard. |

## Tools

| Tool | Role | License |
|---|---|---|
| [yabai](https://github.com/asmvik/yabai) | Tiling window manager | MIT |
| [skhd](https://github.com/asmvik/skhd) | Hotkey daemon | MIT |
| [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) | Resize hotkeys, mouse clipboard | MIT |
| [jq](https://github.com/jqlang/jq) | JSON for the scripts | MIT |
| [SketchyBar](https://github.com/FelixKratz/SketchyBar) | Top bar (optional) | GPL-3.0 |
| [Magnet](https://magnet.crowdcafe.com) | Window snapping in FLOAT (optional, paid, closed source) | — |

## Notes

- Without sketchybar everything still runs, but GRID and the resize code assume a 26 px bar at the top. A layout tuned for the normal macOS menu bar is planned.
- The bar, Warp and Keysheet use the Söhne typeface, which is licensed and not included. Without it they fall back to the system fonts.
- macOS apps have a minimum size. In TILE a resize stops when a neighbour reaches its minimum, instead of letting it spill over another window.
- Window resize goes through macOS Accessibility, one app at a time, so it is not as smooth as Hyprland.
