// Keysheet: a searchable cheat sheet of every shortcut, opened with ⌘K. It lists the live
// bindings, so it always matches the preferences.
import AppKit
import TilerCore

/// The look shared by the Keysheet, the preferences and the menu bar item.
/// Colour: black on white in light mode, white on black in dark mode; no tint, no grey surface.
/// Type: Helvetica Neue in three weights, with tracking set by size. Helvetica is drawn for text
/// sizes, so large type is tightened and small type is opened a little. Bold is for display
/// lines only; emphasis in text uses Medium.
enum Theme {
    enum Face: String { case regular = "HelveticaNeue", medium = "HelveticaNeue-Medium", bold = "HelveticaNeue-Bold" }

    static let background = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white }

    static func font(_ size: CGFloat, _ face: Face = .regular) -> NSFont {
        NSFont(name: face.rawValue, size: size) ?? .systemFont(ofSize: size, weight: face == .regular ? .regular : face == .medium ? .medium : .bold)
    }

    static func tracking(_ size: CGFloat) -> CGFloat {
        switch size {
        case 40...: return size * -0.03
        case 24...: return size * -0.022
        case 15...: return size * -0.012
        case 13...: return 0
        default: return size * 0.012
        }
    }

    /// Text set in the type system. `caps` is the small label style: upper case, opened wide.
    static func text(_ string: String, _ size: CGFloat, _ face: Face = .regular, color: NSColor = .labelColor, caps: Bool = false) -> NSAttributedString {
        NSAttributedString(string: caps ? string.uppercased() : string,
                           attributes: [.font: font(size, face), .kern: caps ? 1.5 : tracking(size), .foregroundColor: color])
    }
}

final class Keysheet: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private struct Entry { let keys: String, name: String, spelled: String, group: String }
    private enum Row { case key(Entry), rule }   // a shortcut, or a hairline between groups

    private final class Panel: NSPanel { override var canBecomeKey: Bool { true } }

    /// Swiss layout on an 8 pt grid: 40 pt margins, three fixed columns, flush left.
    private let margin: CGFloat = 40, colKeys: CGFloat = 152, colName: CGFloat = 288
    let panel: NSPanel = Panel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                               styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
    private let search = NSTextField(), table = NSTableView()
    private let count: NSTextField
    private let title = NSTextField(labelWithString: ""), hint = NSTextField(labelWithString: "")
    private var all: [Entry] = [], rows: [Row] = []
    private let config: () -> Config

    private static func label(_ text: NSAttributedString) -> NSTextField {
        let l = NSTextField(labelWithAttributedString: text)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private static func hairline() -> NSBox {
        let b = NSBox(); b.boxType = .separator; b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    init(config: @escaping () -> Config) {
        self.config = config
        count = Keysheet.label(Theme.text("", 11))
        super.init()
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true; panel.level = .floating
        panel.backgroundColor = Theme.background
        panel.delegate = self
        let bg = NSView(); panel.contentView = bg

        title.translatesAutoresizingMaskIntoConstraints = false

        search.delegate = self
        search.font = Theme.font(24); search.isBordered = false; search.drawsBackground = false
        search.focusRingType = .none; search.translatesAutoresizingMaskIntoConstraints = false
        let rule = Keysheet.hairline()

        for (id, w) in [("keys", colKeys), ("name", colName), ("spelled", 240)] {
            let col = NSTableColumn(identifier: .init(id)); col.width = w; table.addTableColumn(col)
        }
        table.headerView = nil; table.backgroundColor = .clear; table.style = .plain
        table.intercellSpacing = .zero; table.selectionHighlightStyle = .none
        table.dataSource = self; table.delegate = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.drawsBackground = false
        scroll.hasVerticalScroller = false; scroll.translatesAutoresizingMaskIntoConstraints = false

        hint.translatesAutoresizingMaskIntoConstraints = false
        for v in [title, count, search, rule, scroll, hint] as [NSView] { bg.addSubview(v) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: bg.topAnchor, constant: margin),
            title.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            count.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            count.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            search.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            search.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin - 2),
            search.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            rule.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 16),
            rule.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            rule.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            scroll.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -16),
            hint.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            hint.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -32),
        ])
    }

    /// ⌘K shows it; ⌘K again hides it.
    func toggle() { panel.isVisible ? panel.orderOut(nil) : show() }

    func show() {
        let c = config()
        // Set the fixed texts on every show, so a language change takes effect at once.
        title.attributedStringValue = Theme.text(L("Window shortcuts"), 10, .medium, caps: true)
        hint.attributedStringValue = Theme.text(L("Esc  close"), 10, .medium, color: .tertiaryLabelColor, caps: true)
        search.placeholderAttributedString = Theme.text(L("Type to filter"), 24, color: .tertiaryLabelColor)
        all = Action.all.compactMap { a in
            c.combo(a.id).map { Entry(keys: $0.parts.joined(separator: " "), name: L(a.title), spelled: $0.spelled, group: a.group) }
        } + [
            Entry(keys: "⌃ ←  ⌃ →", name: L("Switch space (macOS)"), spelled: "Ctrl + \(L("Left")) / \(L("Right"))", group: "macOS"),
            Entry(keys: "⌃ \(L("drag"))", name: L("Move window"), spelled: "Ctrl + \(L("drag"))", group: "Mouse"),
            Entry(keys: "⌃ \(L("right-drag"))", name: L("Resize window"), spelled: "Ctrl + \(L("right-drag"))", group: "Mouse"),
        ]
        search.stringValue = ""; filter()
        // Centre on the screen under the mouse.
        let mouse = NSEvent.mouseLocation
        if let f = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless(); panel.makeKey(); panel.makeFirstResponder(search)
    }

    private func filter() {
        let words = search.stringValue.lowercased().split(separator: " ")
        let hits = all.filter { h in words.allSatisfy { "\(h.name) \(h.group) \(h.keys) \(h.spelled)".lowercased().contains($0) } }
        rows = []
        for (i, h) in hits.enumerated() {
            if i > 0 && hits[i - 1].group != h.group { rows.append(.rule) }
            rows.append(.key(h))
        }
        count.attributedStringValue = Theme.text(String(format: "%02d / %02d", hits.count, all.count), 11, color: .secondaryLabelColor)
        table.reloadData()
    }

    // Clicking anywhere else closes it; so does Esc.
    func windowDidResignKey(_ n: Notification) { panel.orderOut(nil) }
    func controlTextDidChange(_ n: Notification) { filter() }
    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { panel.orderOut(nil); return true }
        return false
    }

    func numberOfRows(in t: NSTableView) -> Int { rows.count }
    func tableView(_ t: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .rule = rows[row] { return 17 } else { return 32 }
    }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSView()
        guard case .key(let h) = rows[row] else {
            // Draw the group break once, in the first column, spanning the full width.
            guard col?.identifier.rawValue == "keys" else { return cell }
            let r = Keysheet.hairline(); cell.addSubview(r)
            NSLayoutConstraint.activate([r.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                         r.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                                         r.widthAnchor.constraint(equalToConstant: 680)])
            return cell
        }
        let l: NSTextField
        switch col?.identifier.rawValue {
        case "keys": l = Keysheet.label(Theme.text(h.keys, 13, .medium))
        case "name": l = Keysheet.label(Theme.text(h.name, 14))
        default:     l = Keysheet.label(Theme.text(h.spelled, 12, color: .secondaryLabelColor))
        }
        cell.addSubview(l)
        NSLayoutConstraint.activate([l.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                     l.leadingAnchor.constraint(equalTo: cell.leadingAnchor)])
        return cell
    }
}
