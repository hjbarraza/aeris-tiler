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
    var text: String {
        var text = "FULL"
        if let st = wm.current?.state { text = st.layout == .grid ? st.preset.label + (st.hard ? "" : " SOFT") : st.layout.label }
        if wm.paused { text = "PAUSED" }
        if !AXIsProcessTrusted() { text = "AERIS: NO ACCESS" }
        return text
    }

    func refresh() {
        item.button?.attributedTitle = NSAttributedString(string: text, attributes: [.font: Theme.font(11, bold: true), .kern: 1.0])
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
