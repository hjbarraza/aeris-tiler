# aeris-tiler

![aeris-tiler: Hyprland-style tiling for macOS](assets/banner.png)

Hyprland-style tiling for macOS in one native app. It tiles windows, handles the hotkeys and the mouse, draws the focus border and shows a searchable cheat sheet. It replaces the earlier setup of yabai, skhd, Hammerspoon, jq and JankyBorders (still in this repo, see [Legacy setup](#legacy-setup)).

It works with System Integrity Protection (SIP) on and needs one permission: Accessibility. Switching spaces uses macOS's own keys: ⌃← / ⌃→.

## Layouts

Each space has its own layout. ⌘⌥← cycles them; the menu bar shows the current one.

| Layout | What it does |
|---|---|
| TILE | Like Hyprland dwindle: a new window splits the focused one along its longer side. Moving a border resizes the neighbours. |
| GRID | A preset places the windows from their count. **Hard**: sizes are locked, a resize shakes the window. **Soft**: borders move, until the windows on the space change. |
| FLOAT | Plain macOS: windows stay where you put them. |

Grid presets (⌃⌥G cycles them, ⌃⌥H toggles hard / soft):

| Preset | Arrangement | Good for |
|---|---|---|
| Swiss | 12 columns: 1 window full, 2 halves, 3 or more in 3 \| 6 \| 3 | Main work in the middle, references at the sides |
| Columns | Equal columns | Comparing documents |
| Main | One window on two thirds, the rest stacked beside it | Focus work |
| Board | Even rows and columns | Overview of many windows |

## Keys

Every key can be changed in Preferences → Shortcuts. ⌘K lists the current ones.

| Keys | Action |
|---|---|
| ⌃⌥ ← → ↑ ↓ | Focus the window in that direction |
| ⌃⌥⌘ ← → ↑ ↓ | Swap with the window in that direction |
| ⌃⌘ ← → ↑ ↓ | Move a border: hold to keep moving, tap for 60 px |
| ⌘⌥← | Cycle layout: tile → grid → float |
| ⌃⌥G / ⌃⌥H | Next grid preset / grid hard or soft |
| ⌃⌥J / ⌃⌥B | Flip a split between columns and rows / balance all splits |
| ⌘⌥↑ / ⌘⌥↓ | Maximize or restore / float or unfloat |
| ⌘⌥→ | Move the window to the other display |
| ⌃⌥⌘ 1–9 | Move the window to space 1–9 and follow it |
| ⌃⌥⇧ ← → ↑ ↓ | Snap to the left, right, top or bottom half |
| ⌃⌥⇧ U I J K | Snap to a quarter |
| ⌃⌥⇧ D F G / E T | Snap to a third / two thirds |
| ⌃⌥⇧ C / ⌃⌥⇧ ↩ | Centre / fill the screen |
| ⌃⌥P | Pause or resume tiling |
| ⌘K | Keysheet: a searchable list of these keys |

A snapped window leaves the layout and floats; ⌘⌥↓ puts it back.

Mouse: ⌃ + drag moves a window (drop it on another tiled window to swap them), ⌃ + right-drag resizes it. Focus follows the mouse without raising the window. New windows open on the display under the mouse. Selecting text copies it; right-click in the text field you type in pastes (⌥ + right-click for the normal menu). Each of these has a switch in Preferences → Mouse.

## Install

Needs macOS 14 or later and the Xcode Command Line Tools. Built and tested on macOS 27.

```bash
git clone https://github.com/hjbarraza/aeris-tiler && cd aeris-tiler
./build.sh cert   # once: a local signing certificate, so the permission survives rebuilds
./build.sh run    # build, install to ~/Applications/Aeris Tiler.app, start
```

Then turn on **Aeris Tiler** in System Settings → Privacy & Security → Accessibility. If yabai, skhd, Hammerspoon or borders still run, stop them first: two window managers fight over the windows.

## Preferences, menu bar, command line

- **Menu bar**: the item shows the layout (TILE, SWISS, SWISS SOFT, FLOAT, PAUSED). Its menu has every action, the presets, and Preferences.
- **Preferences**: gaps, padding, default layout and preset, mouse behaviour, border width (0 = none) and colour, shortcuts, floating apps, launch at login.
- **Config file**: `~/.config/aeris-tiler/config.json`. Preferences writes it; after an edit by hand run `aeris-tiler reload`. Keys left out keep their default.
- **Command line**: `aeris-tiler` talks to the running app, so scripts and agents can do all that the GUI can.

```bash
aeris-tiler actions              # every action id with its key
aeris-tiler snap-left-half       # run any action on the focused window
aeris-tiler space-2 --window 42  # or on a window by id (ids come from `query`)
aeris-tiler set preset main      # layout tile|grid|float · preset swiss|columns|main|board · hard true|false · login true|false
aeris-tiler query                # JSON: screens, layouts, windows, frames
```

## What is in here

| Path | Job |
|---|---|
| `Sources/TilerCore/` | Layout maths (tile tree, grid presets, snap positions) and the config. No window APIs; unit-tested. |
| `Sources/AerisTiler/WindowManager.swift` | Reads the windows, keeps one layout per space, places windows through Accessibility. |
| `Sources/AerisTiler/Hotkeys.swift`, `MouseTap.swift`, `Border.swift` | Global hotkeys, mouse behaviour, focus border. |
| `Sources/AerisTiler/Preferences.swift`, `StatusMenu.swift`, `Keysheet.swift` | Preferences window, menu bar menu, ⌘K cheat sheet. |
| `Sources/AerisTiler/main.swift` | App start, command line, app icon. |
| `Sources/CPrivate/` | The private window-server calls: window ids, reading spaces, focus without raise, border stacking. |
| `build.sh` | Build, bundle, sign, install. `swift test` runs the unit tests. |

## Limits

- **Move window to space 1–9 (⌃⌥⌘ 1–9)** needs the macOS shortcuts "Switch to Desktop 1…9" turned on (System Settings → Keyboard → Keyboard Shortcuts → Mission Control). The window server refuses a direct move with SIP on, so the app does what a hand does: it holds the window by its title bar and switches space. It takes about 2 s, the pointer jumps to the window and back, and you follow the window. Keep the mouse still meanwhile. Without the shortcut, or for a space on another display that is not showing, the app beeps.
- No window animations and no instant space switch: both need SIP off.
- Apps have a minimum size. A resize stops when a neighbour reaches its minimum.
- Resizing goes through Accessibility, one app at a time, so it is not as smooth as Hyprland.
- The app uses private macOS calls (see `Sources/CPrivate`), so a macOS update can break parts of it and it cannot go on the Mac App Store.

## Credits

Focus without raise follows the method of [yabai](https://github.com/asmvik/yabai) (MIT). The app has no dependencies besides macOS.

## Legacy setup

The first version of aeris-tiler was a set of configs for open-source tools. It still works on its own and stays here for reference: `home/`, `install.sh`, `SETUP.md`, `keysheet/`, `resize-matrix.py`. Do not run it together with the app.

Hyprland-style tiling for macOS, built on open-source tools: yabai tiles, skhd and Hammerspoon handle the keys, sketchybar is an optional top bar. Ported from AerisOS, a Hyprland desktop on Linux.

It works with System Integrity Protection (SIP) on. Window animations need SIP off, so they are not included. Switching spaces uses macOS's own keys: ⌃← / ⌃→ and ⌃1–9.

### Layouts

Each space has one of three layouts. ⌘⌥← cycles them; the bar shows the current one.

| Layout | Command | What it does |
|---|---|---|
| TILE | `tile` | yabai bsp, like Hyprland dwindle: new windows split the focused one, resizing a window resizes its neighbours. |
| GRID | `grid` | Swiss grid of 12 columns: 1 window full, 2 halves, 3 or more in 3 \| 6 \| 3 columns. Re-tiles when windows open or close. Sizes are fixed: resize shakes the window. |
| FLOAT | `floating` | Plain macOS: windows stay where you put them. Opens Magnet if it is installed. |

### Keys

| Keys | Action |
|---|---|
| ⌃⌥ ← → ↑ ↓ | Focus the window in that direction |
| ⌃⌥⌘ ← → ↑ ↓ | Swap with the window in that direction |
| ⌘⌃ ← → ↑ ↓ | Resize: hold to keep resizing, tap for 60 px. The border moves in the arrow's direction; neighbours follow in TILE. |
| ⌃⌥J | Flip the split between rows and columns |
| ⌘⌥↑ | Maximize (keeps the window in the layout, unlike the green button) |
| ⌘⌥↓ | Float / unfloat the window |
| ⌘⌥→ | Move the window to the other display |
| ⌃⌥⌘ 1–9 | Move the window to space 1–9 and follow it |
| ⌘⌥← | Cycle layout: tile → grid → float |
| ⌘⇧Space | Hide / show the bar (sketchybar) |
| ⌃← / ⌃→ | Switch space (native macOS) |
| ⌃⌥⌘ 1–9 | Move the window to space 1–9 |
| ⌘K | Keysheet: a searchable list of these keys |

Mouse: ⌃ + drag moves a window, ⌃ + right-drag resizes it. Focus follows the mouse. New windows open on the display under the mouse.

Hammerspoon also adds a Linux-style clipboard: selecting text copies it, right-click in a text field pastes (⌥ + right-click for the normal menu).

### Install

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

### What is in here

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

### Tools

| Tool | Role | License |
|---|---|---|
| [yabai](https://github.com/asmvik/yabai) | Tiling window manager | MIT |
| [skhd](https://github.com/asmvik/skhd) | Hotkey daemon | MIT |
| [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) | Resize hotkeys, mouse clipboard | MIT |
| [jq](https://github.com/jqlang/jq) | JSON for the scripts | MIT |
| [SketchyBar](https://github.com/FelixKratz/SketchyBar) | Top bar (optional) | GPL-3.0 |
| [Magnet](https://magnet.crowdcafe.com) | Window snapping in FLOAT (optional, paid, closed source) | — |

### Notes

- Without sketchybar everything still runs, but GRID and the resize code assume a 26 px bar at the top. A layout tuned for the normal macOS menu bar is planned.
- The bar, Warp and Keysheet use the Söhne typeface, which is licensed and not included. Without it they fall back to the system fonts.
- macOS apps have a minimum size. In TILE a resize stops when a neighbour reaches its minimum, instead of letting it spill over another window.
- Window resize goes through macOS Accessibility, one app at a time, so it is not as smooth as Hyprland.
