// The preferences window. Swiss style: black and white, Helvetica, a fixed grid, hairlines,
// square controls. Every control edits the same Config the JSON file holds.
import AppKit
import ServiceManagement
import SwiftUI
import TilerCore

// MARK: - Model

final class PrefsModel: ObservableObject {
    enum Section: String, CaseIterable { case general = "General", grid = "Grid", mouse = "Mouse", border = "Border", shortcuts = "Shortcuts", apps = "Apps" }

    @Published var config: Config { didSet { if config != oldValue { apply(config) } } }
    @Published var section = Section.general
    @Published var recording: String?   // the action that waits for a key combo
    @Published var loginItem = SMAppService.mainApp.status == .enabled
    private let apply: (Config) -> Void
    private var monitor: Any?

    init(_ config: Config, apply: @escaping (Config) -> Void) {
        self.config = config
        self.apply = apply
    }

    func setLoginItem(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        loginItem = SMAppService.mainApp.status == .enabled
    }

    /// Wait for the next key combo and bind it to `action`. Esc cancels, Delete unbinds.
    func record(_ action: String) {
        stopRecording()
        recording = action
        Hotkeys.shared.unregister()   // or the hotkeys would swallow the combo
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.recording != nil else { return e }
            let f = e.modifierFlags
            let mods = [("ctrl", f.contains(.control)), ("alt", f.contains(.option)), ("shift", f.contains(.shift)), ("cmd", f.contains(.command))].filter(\.1).map(\.0)
            var c = self.config
            if mods.isEmpty, e.keyCode == 51 {
                c.bindings[action] = ""
            } else if !mods.isEmpty, let key = KeyCombo.keyNames[UInt32(e.keyCode)] {
                let spec = KeyCombo(mods: mods, key: key).spec
                for (other, s) in c.bindings where s == spec && other != action { c.bindings[other] = "" }   // one combo, one action
                c.bindings[action] = spec
            } else if !(mods.isEmpty && e.keyCode == 53) {
                NSSound.beep()   // a key without modifier cannot be a global hotkey
                return nil
            }
            self.stopRecording()
            self.config = c
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording != nil else { return }
        recording = nil
        Hotkeys.shared.register(config.bindings)
    }
}

// MARK: - Type and colour

private extension Font {
    static func swiss(_ size: CGFloat, _ face: Theme.Face = .regular) -> Font { .custom(face.rawValue, fixedSize: size) }
}

private extension View {
    /// Text in the shared type system: see Theme.
    func swiss(_ size: CGFloat, _ face: Theme.Face = .regular) -> some View { font(.swiss(size, face)).tracking(Theme.tracking(size)) }
}

/// Controls have slightly rounded corners; rules and the layout stay square.
private let box = RoundedRectangle(cornerRadius: 4, style: .continuous)

private extension View {
    /// The outline of a control.
    func outlined(_ width: CGFloat = 1) -> some View { overlay(box.strokeBorder(Color.primary, lineWidth: width)) }
    /// Several cells joined into one control: square inside, rounded outside.
    func joined() -> some View { clipShape(box).outlined() }
}

private let ink = Color.primary
private let paper = Color(nsColor: Theme.background)

/// Small capitals label: the section marks of the layout.
private struct Caps: View {
    let text: String
    var body: some View { Text(L(text).uppercased()).font(.swiss(10, .medium)).tracking(1.5) }
}

private struct Hairline: View {
    var weight: CGFloat = 1
    var body: some View { Rectangle().fill(ink.opacity(weight > 1 ? 1 : 0.22)).frame(height: weight) }
}

// MARK: - Controls

/// A square switch: outline when off, solid when on.
private struct Switch: View {
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                box.fill(on ? ink : .clear).outlined()
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(on ? paper : ink).frame(width: 12, height: 12).padding(3)
            }
            .frame(width: 36, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One of several options, as a row of square cells.
private struct Choice<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var value: T
    var body: some View {
        HStack(spacing: -1) {
            ForEach(options, id: \.0) { o in
                Button { value = o.0 } label: {
                    Text(L(o.1)).swiss(12, value == o.0 ? .medium : .regular)
                        .foregroundStyle(value == o.0 ? paper : ink)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(value == o.0 ? ink : .clear)
                        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .joined()
    }
}

/// A number with minus and plus.
private struct Number: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = "px"
    var zero: String?   // what to show at 0, e.g. "None"
    private func cell(_ s: String, _ d: Double) -> some View {
        Button { value = min(max(value + d, range.lowerBound), range.upperBound) } label: {
            Text(s).swiss(14).frame(width: 26, height: 26).overlay(Rectangle().strokeBorder(ink, lineWidth: 1)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    var body: some View {
        HStack(spacing: -1) {
            cell("−", -1)
            Text(value == 0 && zero != nil ? L(zero!) : "\(Int(value)) \(unit)").swiss(12, .medium).monospacedDigit().frame(width: 64, height: 26).overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
            cell("+", 1)
        }
        .joined()
    }
}

/// A small drawing of an arrangement: `frames` in a unit square.
private struct Diagram: View {
    let frames: [CGRect]
    let selected: Bool
    var body: some View {
        Canvas { ctx, size in
            for f in frames {
                let r = CGRect(x: f.minX * size.width, y: f.minY * size.height, width: f.width * size.width, height: f.height * size.height).insetBy(dx: 1.5, dy: 1.5)
                selected ? ctx.fill(Path(r), with: .color(paper)) : ctx.stroke(Path(r.insetBy(dx: 0.5, dy: 0.5)), with: .color(ink), lineWidth: 1)
            }
        }
        .frame(width: 72, height: 46).padding(6)
        .background(selected ? ink : .clear)
        .clipShape(box)
        .outlined()
    }
}

/// Options shown as diagrams with a caption.
private struct DiagramChoice<T: Hashable>: View {
    let options: [(T, String, [CGRect])]
    @Binding var value: T
    var body: some View {
        HStack(spacing: 12) {
            ForEach(options, id: \.0) { o in
                Button { value = o.0 } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Diagram(frames: o.2, selected: value == o.0)
                        Text(L(o.1)).swiss(11, value == o.0 ? .medium : .regular)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

private let layoutDiagrams: [(TilerCore.Layout, String, [CGRect])] = [
    (.tile, "Tile", tileFrames),
    (.grid, "Grid", presetFrames(.swiss, 5)),
    (.float, "Float", floatFrames),
]

// MARK: - Rows

/// One setting: title and note on the left, control on the right, hairline below.
private struct Row<Control: View>: View {
    let title: String
    var note: String?
    var stacked = false   // wide controls go under the text
    @ViewBuilder let control: Control
    var body: some View {
        let text = VStack(alignment: .leading, spacing: 4) {
            Text(L(title)).swiss(13, .medium)
            if let note { Text(L(note)).swiss(12).lineSpacing(3).foregroundStyle(ink.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440, alignment: .leading) }   // a measure of about 70 characters
        }
        VStack(spacing: 0) {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 14) { text; control }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: 24) { text; Spacer(minLength: 16); control }
                }
            }
            .padding(.vertical, 16)
            Hairline()
        }
    }
}

// MARK: - Window content

struct PrefsView: View {
    @ObservedObject var m: PrefsModel
    let status: () -> String

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 224)
            Rectangle().fill(ink.opacity(0.16)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                let n = PrefsModel.Section.allCases.firstIndex(of: m.section)! + 1
                Caps(text: String(format: "%02d", n)).foregroundStyle(ink.opacity(0.5)).padding(.bottom, 2)
                // Large glyphs carry side bearing: pull the line left so its stem meets the rule.
                Text(L(m.section.rawValue)).swiss(48, .bold).offset(x: -2.5)
                Hairline(weight: 2).padding(.top, 12)
                ScrollView { VStack(spacing: 0) { content }.padding(.bottom, 24) }.scrollIndicators(.never)
            }
            .padding(.top, 52).padding(.horizontal, 40)
        }
        .frame(width: 900, height: 640)
        .background(paper)
        .foregroundStyle(ink)
        .id(m.config.language)   // texts come from L(): draw everything again when the language changes
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: -7) {
                Text("Aeris").swiss(28, .bold)
                Text("Tiler").swiss(28, .bold)
            }
            .offset(x: -1.5).padding(.bottom, 40)
            ForEach(Array(PrefsModel.Section.allCases.enumerated()), id: \.1) { i, s in
                Button { m.stopRecording(); m.section = s } label: {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", i + 1)).swiss(11).monospacedDigit().foregroundStyle(ink.opacity(0.5))
                        Text(L(s.rawValue)).swiss(14, m.section == s ? .medium : .regular)
                        Spacer()
                        if m.section == s { Rectangle().fill(ink).frame(width: 8, height: 8) }
                    }
                    .frame(height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Hairline()
            }
            Spacer()
            Caps(text: "Now").foregroundStyle(ink.opacity(0.5)).padding(.bottom, 4)
            Text(status()).swiss(12, .medium).padding(.bottom, 14)
            Caps(text: "Config").foregroundStyle(ink.opacity(0.5)).padding(.bottom, 4)
            Button { NSWorkspace.shared.activateFileViewerSelecting([Config.url]) } label: {
                Text("~/.config/aeris-tiler").swiss(12).underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 52).padding(.horizontal, 24).padding(.bottom, 28)
    }

    @ViewBuilder private var content: some View {
        switch m.section {
        case .general:
            Row(title: "Language") {
                Choice(options: [("system", "System")] + Lang.allCases.map { ($0.rawValue, $0.rawValue.uppercased()) }, value: $m.config.language)
            }
            Row(title: "Launch at login") { Switch(on: Binding(get: { m.loginItem }, set: m.setLoginItem)) }
            Row(title: "Layout of a new space", note: "Each space keeps its own layout after that.") {
                DiagramChoice(options: layoutDiagrams, value: $m.config.defaultLayout)
            }
            Row(title: "Gap", note: "Gutter between windows.") { Number(value: $m.config.gap, range: 0...64) }
            Row(title: "Padding", note: "Space to the screen edge.") { Number(value: $m.config.padding, range: 0...64) }
            Row(title: "Open on the display under the mouse", note: "New windows appear where you work, not on the main display.") { Switch(on: $m.config.openOnMouseDisplay) }
        case .grid:
            Row(title: "Preset of a new space", note: "Swiss: 3 | 6 | 3 columns. Columns: compare side by side. Main: one large window and a stack. Board: even rows and columns.", stacked: true) {
                DiagramChoice(options: Preset.allCases.map { ($0, $0.rawValue.capitalized, presetFrames($0, $0 == .board ? 6 : $0 == .columns ? 3 : 5)) }, value: $m.config.gridPreset)
            }
            Row(title: "Sizes", note: "Hard: the grid owns the sizes; a resize shakes the window.\nSoft: borders move, until the windows on the space change.") {
                Choice(options: [(true, "Hard"), (false, "Soft")], value: $m.config.gridHard)
            }
        case .mouse:
            Row(title: "Focus follows mouse", note: "Focus: the window under the pointer takes the keyboard.\nRaise: it also comes to the front.") {
                Choice(options: [(.off, "Off"), (.focus, "Focus"), (.raise, "Raise")], value: $m.config.focusFollowsMouse)
            }
            Row(title: "Drag windows with Ctrl", note: "⌃ + drag moves a window. ⌃ + right-drag resizes it.") { Switch(on: $m.config.mouseDrag) }
            Row(title: "Copy on select", note: "Selecting text with the mouse copies it.") { Switch(on: $m.config.copyOnSelect) }
            Row(title: "Paste with right-click", note: "In the text field you type in. ⌥ + right-click opens the normal menu.") { Switch(on: $m.config.rightClickPaste) }
        case .border:
            Row(title: "Width", note: "The border marks the focused window. 0 is no border.") { Number(value: $m.config.borderWidth, range: 0...32, zero: "None") }
            Row(title: "Corner radius", note: "Match the corners of your windows.") { Number(value: $m.config.borderRadius, range: 0...40) }
            Row(title: "Colour", note: "Pick a swatch, press + for any colour, or type a hex value.") {
                HStack(spacing: 8) {
                    ForEach(["#000000", "#FFFFFF", "#808080", "#FF3B00"], id: \.self) { hex in
                        Button { m.config.borderColor = hex } label: {
                            box.fill(Color(nsColor: NSColor(hex: hex))).frame(width: 26, height: 26)
                                .outlined(m.config.borderColor.uppercased() == hex ? 3 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { ColorPanel.shared.open(NSColor(hex: m.config.borderColor)) { m.config.borderColor = $0.hex } } label: {
                        Text("+").swiss(15).frame(width: 26, height: 26).outlined().contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(L("More colours"))
                    TextField("#808080", text: $m.config.borderColor).textFieldStyle(.plain).swiss(12, .medium)
                        .frame(width: 72, height: 26).padding(.horizontal, 8).outlined()
                }
            }
        case .shortcuts:
            let groups = Dictionary(grouping: Action.all.filter { $0.id != "preferences" }, by: \.group)
            ForEach(Action.all.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.filter { groups[$0] != nil }, id: \.self) { g in
                HStack { Caps(text: g).foregroundStyle(ink.opacity(0.5)); Spacer() }.padding(.top, 20).padding(.bottom, 6)
                Hairline()
                ForEach(groups[g]!, id: \.id) { a in
                    VStack(spacing: 0) {
                        HStack {
                            Text(L(a.title)).swiss(13)
                            Spacer()
                            Button { m.recording == a.id ? m.stopRecording() : m.record(a.id) } label: {
                                let rec = m.recording == a.id
                                Text(rec ? L("Press keys") : m.config.combo(a.id)?.parts.joined(separator: " ") ?? "—")
                                    .swiss(12, .medium).foregroundStyle(rec ? paper : ink)
                                    .frame(width: 120, height: 24).background(rec ? ink : .clear).clipShape(box)
                                    .outlined().contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        Hairline()
                    }
                }
            }
            HStack {
                Text(L("Click a key field, then press the new keys. Delete clears it, Esc cancels.")).swiss(12).foregroundStyle(ink.opacity(0.55))
                Spacer()
                Button { m.stopRecording(); m.config.bindings = Config().bindings } label: {
                    Text(L("Reset all")).swiss(12, .medium).padding(.horizontal, 12).frame(height: 26).outlined().contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
        case .apps:
            AppsList(apps: $m.config.floatApps)
        }
    }
}

/// Apps whose windows always float.
private struct AppsList: View {
    @Binding var apps: [String]
    @State private var name = ""
    private func add() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty, !apps.contains(n) { apps.append(n) }
        name = ""
    }
    var body: some View {
        Row(title: "Floating apps", note: "Windows of these apps are never tiled. Use the name the menu bar shows.") {
            HStack(spacing: -1) {
                TextField(L("App name"), text: $name).textFieldStyle(.plain).swiss(12).onSubmit(add)
                    .frame(width: 180, height: 26).padding(.horizontal, 8)
                Button(action: add) {
                    Text(L("Add")).swiss(12, .medium).foregroundStyle(paper).padding(.horizontal, 14).frame(height: 26).background(ink).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .joined()
        }
        ForEach(apps, id: \.self) { app in
            VStack(spacing: 0) {
                HStack {
                    Text(app).swiss(13)
                    Spacer()
                    Button { apps.removeAll { $0 == app } } label: { Text(L("Remove")).swiss(12).underline().contentShape(Rectangle()) }.buttonStyle(.plain)
                }
                .padding(.vertical, 9)
                Hairline()
            }
        }
    }
}

/// The system colour panel, for the border colour.
final class ColorPanel: NSObject {
    static let shared = ColorPanel()
    private var pick: ((NSColor) -> Void)?

    func open(_ color: NSColor, pick: @escaping (NSColor) -> Void) {
        self.pick = pick
        let p = NSColorPanel.shared
        p.showsAlpha = false
        p.color = color
        p.setTarget(self)
        p.setAction(#selector(changed(_:)))
        p.orderFront(nil)
    }

    @objc private func changed(_ p: NSColorPanel) { pick?(p.color) }
}

// MARK: - Window

final class PrefsWindow: NSObject, NSWindowDelegate {
    let model: PrefsModel
    let window: NSWindow

    init(_ model: PrefsModel, status: @escaping () -> String) {
        self.model = model
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "Aeris Tiler"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.background
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: PrefsView(m: model, status: status))
        window.center()
    }

    func show() {
        model.loginItem = SMAppService.mainApp.status == .enabled
        model.objectWillChange.send()   // refresh the "Now" line
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) { model.stopRecording() }
}
