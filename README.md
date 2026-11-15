# aeris-tiler

![aeris-tiler: Hyprland-style tiling for macOS](assets/banner.png)

Hyprland-style tiling for macOS in one native app: tiling, hotkeys, mouse control, a focus border and a searchable key list. It works with System Integrity Protection on and needs one permission: Accessibility.

## Install

1. Download the DMG from the [latest release](https://github.com/hjbarraza/aeris-tiler/releases/latest).
2. Drag Aeris Tiler to Applications and open it.
3. First start: System Settings → Privacy & Security → **Open Anyway**. The app is not notarized.
4. Turn on **Aeris Tiler** in Privacy & Security → Accessibility.

Needs an Apple Silicon Mac and macOS 14 or later.

## Use

| Layout | What it does |
|---|---|
| TILE | A new window splits the focused one along its longer side. |
| GRID | A preset places the windows: Swiss (3 \| 6 \| 3), Columns, Main or Board. |
| FLOAT | Plain macOS: windows stay where you put them. |

- ⌘⌥← cycles the layouts. ⌘K lists every key.
- The menu bar icon opens the menu and Preferences: keys, gaps, mouse, border, language, launch at login.
- The app uses private macOS calls, so a macOS update can break parts of it.

## Build

```sh
./build.sh cert   # once: a local signing certificate, so the permission stays across builds
./build.sh run    # build, install to ~/Applications, start
./build.sh dmg    # make "build/Aeris Tiler.dmg"
```

A source build links the command line tool to `~/.local/bin/aeris-tiler`. `aeris-tiler actions` lists what it can do.

## Credits

Aeris Tiler began as a setup of other tools, and is now one app. It is inspired by them:

- [Hyprland](https://github.com/hyprwm/Hyprland): the tiling model.
- [yabai](https://github.com/asmvik/yabai): window management. Focus without raise follows its method (MIT).
- [skhd](https://github.com/asmvik/skhd): hotkeys.
- [Hammerspoon](https://github.com/Hammerspoon/hammerspoon): mouse behaviour.
- [JankyBorders](https://github.com/FelixKratz/JankyBorders): the focus border.
- [SketchyBar](https://github.com/FelixKratz/SketchyBar): the status bar.

[hjbarraza.com](https://hjbarraza.com) · [astraed.co](https://astraed.co) · MIT, see [LICENSE](LICENSE)
