# Set up aeris-tiler with an AI agent

This file is written for an AI agent (Claude, ChatGPT, Gemini, Codex or any other) that helps a person install aeris-tiler on their Mac. A person can follow it too.

To start, the user pastes this into their agent:

> Set up aeris-tiler on my Mac. Follow https://raw.githubusercontent.com/hjbarraza/aeris-tiler/main/SETUP.md step by step and ask me before each change.

If you cannot open that link, ask the user to paste this file into the chat.

## Rules for the agent

- **Ask before every change** to the user's Mac: installing software, replacing a file, starting a service. Say what the command does in one sentence, then run it or hand it over.
- **If you can run shell commands** (Claude Code, Codex, Gemini CLI, a terminal tool), run them yourself and show the result. **If you cannot** (a chat window), give the user one command at a time to paste into Terminal (Applications → Utilities → Terminal), ask them to paste the output back, and read it before the next step.
- **Never turn off System Integrity Protection (SIP).** aeris-tiler works with SIP on. Do not suggest `csrutil`, `--load-sa` or boot arguments.
- **Never use `sudo`.** The Homebrew installer asks for the password itself, so the user runs that one command in Terminal.
- **Permissions are the user's job.** macOS only lets the user grant Accessibility. Open the right settings page, then wait until they confirm.
- **Stop and explain** when a command fails. Do not try workarounds that change system settings.

## 1. Check the Mac

```bash
sw_vers -productVersion          # macOS version
uname -m                         # arm64 = Apple silicon, x86_64 = Intel
xcode-select -p || echo "no Command Line Tools"
git --version
command -v brew || ls /opt/homebrew/bin/brew /usr/local/bin/brew 2>/dev/null || echo "no Homebrew"
csrutil status                   # informational only; SIP stays as it is
```

- aeris-tiler was built and tested on macOS 27. On older versions, tell the user it is untested there.
- **Command Line Tools are required** (they provide `git` and the compiler for the ⌘K cheat sheet). If missing, ask, then run `xcode-select --install`. A macOS dialog opens; wait until the user says it finished, then check `git --version` again.
- **Homebrew is required.** If missing, give the user the official install command from https://brew.sh to run **in Terminal themselves**, because it asks for their password. Afterwards, ask them to also run the "Next steps" lines Homebrew prints. Check with `brew --version`.

**Every later shell needs Homebrew on its PATH.** A fresh install is not on the PATH of an agent's shell yet, so start each later command block with:

```bash
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
```

## 2. Tell the user what changes, and ask four questions

**What aeris-tiler changes on the Mac** (say this before installing):

- Windows tile automatically: every new window takes a place in the layout.
- **Focus follows the mouse:** moving the pointer over a window focuses it.
- **Mouse:** ⌃ + drag moves a window, ⌃ + right-drag resizes it.
- **Clipboard (Hammerspoon):** selecting text copies it; right-click in a text field pastes (⌥ + right-click gives the normal menu).
- **⌘K opens the aeris-tiler cheat sheet in every app**, so apps that use ⌘K (Slack, browsers, Terminal "clear") lose it. This can be removed or changed.
- Three background services start at login: yabai, skhd and, optionally, sketchybar. Hammerspoon opens at login.

**Ask all four:**

1. **Top bar:** do they want sketchybar, the optional black top bar that shows spaces and the current layout? Without it, everything still works.
2. **Replaced files:** the installer replaces these, keeping each old one as `<file>.bak-<date-time>` next to it: `~/.config/yabai/yabairc`, `~/.config/skhd/skhdrc`, `~/.hammerspoon/init.lua`, `~/.config/sketchybar/sketchybarrc`, `~/.warp/settings.toml`, and `~/.local/bin/grid`, `tile`, `floating`, `layout`. It also creates `~/Applications/Keysheet.app` and `~/.local/state/aeris/`. If they already use Hammerspoon or Warp with their own settings, say so explicitly. Is that OK?
3. **Warp:** do they use the Warp terminal? If not, skip its settings file (step 4).
4. **Shortcuts:** show the defaults; they can be changed now or later (step 7).

| Default shortcut | Action |
|---|---|
| ⌃⌥ + arrows | Focus a window |
| ⌃⌥⌘ + arrows | Swap windows |
| ⌘⌃ + arrows (hold) | Resize: the window's border moves in the arrow's direction |
| ⌘⌥← | Cycle layout: tile → grid → float |
| ⌃⌥J | Flip the split between rows and columns |
| ⌘⌥↑ | Maximize |
| ⌘⌥↓ | Float / unfloat |
| ⌘⌥→ | Move window to the other display |
| ⌘⇧Space | Hide / show the top bar (needs sketchybar) |
| ⌃← / ⌃→ | Switch space (native macOS) |
| ⌃⌥⌘ 1–9 | Move window to space 1–9 |
| ⌘K | Cheat sheet |

## 3. Install the tools

Recent Homebrew versions ask you to trust third-party taps once. Run the `brew trust` line; if it fails with "Unknown command", skip it.

```bash
brew trust asmvik/formulae
brew install asmvik/formulae/yabai asmvik/formulae/skhd jq
brew install --cask hammerspoon
```

Only if the user wants the top bar:

```bash
brew trust felixkratz/formulae
brew install felixkratz/formulae/sketchybar
```

Check before going on; all three must print a path:

```bash
command -v yabai skhd jq
```

## 4. Install aeris-tiler

```bash
git clone https://github.com/hjbarraza/aeris-tiler ~/aeris-tiler || git -C ~/aeris-tiler pull
cd ~/aeris-tiler
```

If `~/aeris-tiler` already exists and has local changes, ask the user before pulling.

If the user does not want the Warp settings: `rm home/.warp/settings.toml` (this only removes it from the downloaded copy).

Then, after asking ("this copies the configs, backs up the old ones, builds the cheat sheet, starts yabai, skhd and sketchybar as login services, and opens Hammerspoon"):

```bash
./install.sh
```

Each `backed up <file> -> <file>.bak-<date-time>` line names a backup; tell the user where they are.

## 5. Grant permissions (the user does this)

yabai, skhd and Hammerspoon need Accessibility to move windows and read the keyboard. Open the page:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

Without a shell, tell the user: System Settings → Privacy & Security → Accessibility.

Then tell the user:

1. Turn on **yabai**, **skhd** and **Hammerspoon**. If one is missing, click **+**, press ⌘⇧G and type the path from `command -v yabai` or `command -v skhd` (usually `/opt/homebrew/bin/...` on Apple silicon, `/usr/local/bin/...` on Intel), or pick Hammerspoon in Applications.
2. macOS may also show its own prompts; they should click **Open System Settings** and allow.
3. Say "done" when all three are on.

Then restart so they pick up the permission:

```bash
yabai --restart-service
skhd --restart-service
open -a Hammerspoon
```

## 6. Check that it works

```bash
yabai -m query --spaces --space | jq .type     # "bsp" means tiling is on
pgrep -x skhd >/dev/null && echo "skhd running"
~/.local/bin/layout                               # prints TILE, GRID, FLOAT or FULL
```

Then ask the user to try, with two or three windows open:

1. ⌘⌥←: the layout changes (tile → grid → float); with sketchybar, the label in the bar changes too.
2. In TILE, hold ⌘⌃→: the border between two windows moves right and both windows change size. (On the rightmost window, → shrinks it from the left; that is the border moving right.)
3. ⌘K: the cheat sheet opens.

If a key does nothing, the usual cause is a missing Accessibility permission: go back to step 5.

## 7. Customize the shortcuts

Every shortcut can be changed.

- **Most shortcuts** live in `~/.config/skhd/skhdrc`, one per line: `cmd + alt - left : $HOME/.local/bin/layout next`. Edit the left side, save, then run `skhd --reload`. The cheat sheet reads this file, so it updates too.
- **To free ⌘K**, delete or change the `cmd - k` line in `skhdrc`, then `skhd --reload`.
- **Resize** lives in `~/.hammerspoon/init.lua`, in the line `hs.hotkey.bind({ "cmd", "ctrl" }, dir, ...)`. Change `{ "cmd", "ctrl" }`, then reload Hammerspoon from its menu. Also update the four `-> : true` lines in `skhdrc` so the cheat sheet shows the new keys.
- Avoid combinations macOS already uses (⌘Space, ⌃↑, ⌃←/→ for Spaces, unless the user turned those off in System Settings → Keyboard → Keyboard Shortcuts).
- **Running `./install.sh` again resets shortcuts to the defaults** (the customized files are kept as `.bak-<date-time>`). To keep custom shortcuts across updates, make the same edits in `~/aeris-tiler/home/...` too.

When the user asks for a new shortcut, edit the file, reload, and ask them to try it.

## Undo

```bash
yabai --stop-service; yabai --uninstall-service
skhd --stop-service; skhd --uninstall-service
brew services stop sketchybar 2>/dev/null
```

Then, for each file listed in step 2: if a `.bak-<date-time>` copy exists, move it back over the file; if not, delete the file. Also delete `~/Applications/Keysheet.app` and `~/.local/state/aeris/`. Quit Hammerspoon (or restore its `init.lua` and reload it), otherwise the clipboard features stay. Optionally `brew uninstall yabai skhd sketchybar` and `brew uninstall --cask hammerspoon`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Refusing to load formula ... from untrusted tap` | Run the `brew trust` line for that tap (step 3). |
| `yabai: command not found` from `install.sh` | Homebrew is not on this shell's PATH: run the `eval "$(.../brew shellenv)"` line (step 1), then `./install.sh` again. |
| Keys do nothing | Accessibility not granted, or granted to an old binary after an update. Remove the entry, add it again (step 5), restart the services. |
| `install.sh` says the cheat sheet was skipped | Command Line Tools missing: `xcode-select --install`, then run `./install.sh` again. |
| A resize stops early | An app reached its minimum size; the resize stops there on purpose. |
| Space switching from the keyboard does not work | Expected: it needs SIP off, which this setup does not do. |
