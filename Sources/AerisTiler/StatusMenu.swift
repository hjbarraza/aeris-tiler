// The menu bar item: its title is the layout of the current space, its menu runs every action.
import AppKit
import TilerCore

final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let wm: WindowManager
    private let run: (String) -> Void

    private final class Item: NSMenuItem {
        var work: (() -> Void)?
        @objc func fire() { work?() }
    }

    init(_ wm: WindowManager, run: @escaping (String) -> Void) {
        self.wm = wm
        self.run = run
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    /// TILE, FLOAT or the grid preset (SWISS, or SWISS SOFT); PAUSED; or a prompt while
    /// Accessibility is not granted.
    /// The state in words: TILE, FLOAT or the grid preset (SWISS, SWISS SOFT); PAUSED; or a
    /// prompt while Accessibility is not granted. Shown as the tooltip and in the preferences.
    var text: String {
        var text = "FULL"
        if let st = wm.current?.state { text = st.layout == .grid ? st.preset.label + (st.hard ? "" : " SOFT") : st.layout.label }
        if wm.paused { text = "PAUSED" }
        if !AXIsProcessTrusted() { text = "AERIS: NO ACCESS" }
        return text
    }

    /// The menu bar shows the arrangement itself: a small drawing of the current layout.
    /// Solid windows for tile and a hard grid, outlines for a soft grid and float. It is drawn
    /// here as vector shapes, so there is no image file. It is dimmed while tiling is paused,
    /// and marked "!" while Accessibility is not granted; the tooltip names the layout.
    func refresh() {
        let st = wm.current?.state
        var frames = tileFrames, solid = true
        switch st?.layout {
        case .grid: frames = presetFrames(st!.preset, st!.preset == .board ? 4 : 3); solid = st!.hard
        case .float: frames = floatFrames; solid = false
        default: break
        }
        let size = NSSize(width: 20, height: 14)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()
            for f in frames {
                let r = NSRect(x: f.minX * size.width, y: f.minY * size.height, width: f.width * size.width, height: f.height * size.height).insetBy(dx: 0.75, dy: 0.75)
                if solid {
                    NSBezierPath(roundedRect: r, xRadius: 1.2, yRadius: 1.2).fill()
                } else {
                    let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.2, yRadius: 1.2)
                    path.lineWidth = 1
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true   // macOS colours it for the light or dark menu bar
        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        item.button?.title = AXIsProcessTrusted() ? "" : "!"
        item.button?.appearsDisabled = wm.paused
        item.button?.toolTip = "Aeris Tiler: \(text)"
        item.button?.setAccessibilityLabel("Aeris Tiler, \(text)")
    }

    private func add(_ menu: NSMenu, _ title: String, action id: String? = nil, checked: Bool = false, _ work: (() -> Void)? = nil) {
        let i = Item(title: title, action: #selector(Item.fire), keyEquivalent: "")
        i.target = i
        i.work = work ?? { [run] in if let id { run(id) } }
        i.state = checked ? .on : .off
        // Show the hotkey next to the item.
        if let id, let k = wm.config.combo(id) {
            let special: [String: Int] = ["left": NSLeftArrowFunctionKey, "right": NSRightArrowFunctionKey, "up": NSUpArrowFunctionKey, "down": NSDownArrowFunctionKey]
            let plain = ["return": "\r", "space": " ", "tab": "\t", "escape": "\u{1b}", "delete": "\u{8}"]
            i.keyEquivalent = special[k.key].map { String(UnicodeScalar($0)!) } ?? plain[k.key] ?? k.key
            var mask: NSEvent.ModifierFlags = []
            for m in k.mods { mask.insert(["cmd": .command, "ctrl": .control, "alt": .option, "shift": .shift][m]!) }
            i.keyEquivalentModifierMask = mask
        }
        menu.addItem(i)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard AXIsProcessTrusted() else {
            add(menu, "Grant Accessibility…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            menu.addItem(.separator())
            add(menu, "Quit Aeris Tiler") { NSApp.terminate(nil) }
            return
        }
        let st = wm.current?.state
        for l in Layout.allCases {
            add(menu, l.rawValue.capitalized, checked: l == st?.layout) { [wm] in wm.update { $0.layout = l } }
        }
        add(menu, "Next Layout", action: "cycle-layout")
        menu.addItem(.separator())
        for p in Preset.allCases {
            add(menu, "Grid: \(p.rawValue.capitalized)", checked: st?.layout == .grid && p == st?.preset) { [wm] in wm.update { $0.layout = .grid; $0.preset = p } }
        }
        add(menu, "Next Grid Preset", action: "cycle-preset")
        add(menu, "Hard Grid: Lock Sizes", action: "toggle-hard", checked: st?.hard == true)
        menu.addItem(.separator())
        add(menu, "Maximize", action: "maximize")
        add(menu, "Float Window", action: "toggle-float")
        add(menu, "Flip Split", action: "toggle-split")
        add(menu, "Balance Splits", action: "balance")
        add(menu, "Move to Other Display", action: "next-display")
        let snap = NSMenuItem(title: "Snap", action: nil, keyEquivalent: "")
        snap.submenu = NSMenu()
        for s in Snap.allCases { add(snap.submenu!, s.title, action: "snap-\(s.rawValue)") }
        menu.addItem(snap)
        menu.addItem(.separator())
        add(menu, "Pause Tiling", action: "pause", checked: wm.paused)
        add(menu, "Keysheet", action: "keysheet")
        menu.addItem(.separator())
        add(menu, "Preferences…", action: "preferences")
        add(menu, "Quit Aeris Tiler") { NSApp.terminate(nil) }
    }
}

// MARK: - Small drawings of the layouts, in a unit square (menu bar icon, preferences)

/// The frames a preset gives `n` windows.
func presetFrames(_ p: Preset, _ n: Int) -> [CGRect] {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    return Tree(p, windows: (1...n).map { WindowID($0) }, in: area, gap: 0).frames(in: area, gap: 0).values
        .map { CGRect(x: $0.minX / 1000, y: $0.minY / 1000, width: $0.width / 1000, height: $0.height / 1000) }
}

let tileFrames = [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
let floatFrames = [CGRect(x: 0.04, y: 0.06, width: 0.56, height: 0.62), CGRect(x: 0.38, y: 0.32, width: 0.58, height: 0.62)]
