// Aeris Tiler: Hyprland-style tiling for macOS in one app.
//
// Run with no arguments, it is the app (menu bar item, no Dock icon). Run with arguments, it is
// the command line for the running app, so scripts and agents can do all that the GUI can:
//   aeris-tiler <action>          any id from `aeris-tiler actions` (focus-left, snap-left-half, ...);
//                                 add `--window <id>` to act on that window, not the focused one
//   aeris-tiler set <key> <value> layout tile|grid|float · preset swiss|columns|main|board · hard true|false
//                                 (these three change the space under the mouse) · login true|false
//   aeris-tiler query             JSON: screens, layouts, windows, frames
//   aeris-tiler reload            read ~/.config/aeris-tiler/config.json again
import AppKit
import TilerCore

let commandName = Notification.Name("com.aeris.tiler.command")

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let wm = WindowManager()
    var mouse: MouseTap!
    var status: StatusMenu!
    var prefs: PrefsWindow!
    var keysheet: Keysheet!
    private var started = false

    func applicationDidFinishLaunching(_ n: Notification) {
        // A second launch opens the preferences of the first.
        if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            exit(CLI.run(["preferences"]))
        }
        Strings.language = Lang.resolve(wm.config.language)
        mouse = MouseTap(wm)
        keysheet = Keysheet { [wm] in wm.config }
        status = StatusMenu(wm) { [unowned self] in self.run($0) }
        prefs = PrefsWindow(PrefsModel(wm.config) { [unowned self] c in
            Strings.language = Lang.resolve(c.language)
            self.wm.setConfig(c)
            if self.prefs.model.recording == nil { Hotkeys.shared.register(c.bindings) }
        }) { [unowned self] in self.status.text }
        wm.onChange = { [unowned self] in self.status.refresh() }
        Hotkeys.shared.handler = { [unowned self] action, pressed in self.run(action, pressed: pressed) }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(command(_:)), name: commandName, object: nil, suspensionBehavior: .deliverImmediately)
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        startWhenTrusted()
    }

    /// Windows can only be read and moved once the user grants Accessibility.
    private func startWhenTrusted() {
        guard AXIsProcessTrusted() else {
            status.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startWhenTrusted() }
            return
        }
        started = true
        Hotkeys.shared.register(wm.config.bindings)
        mouse.start()
        wm.start()
    }

    /// Run an action from a hotkey, the menu or the command line.
    @discardableResult
    func run(_ action: String, pressed: Bool = true) -> Bool {
        switch action {
        case "keysheet": if pressed { keysheet.toggle() }
        case "preferences": if pressed { prefs.show() }
        default: return started && wm.perform(action, pressed: pressed)
        }
        return true
    }

    // MARK: Command line requests

    @objc private func command(_ n: Notification) {
        guard let info = n.userInfo, let cmd = info["cmd"] as? String, let reply = info["reply"] as? String else { return }
        let args = info["args"] as? [String] ?? []
        var out: [String: Any] = ["ok": true]
        switch cmd {
        case "query":
            out = wm.query()
        case "reload":
            wm.config = Config.load()
            Strings.language = Lang.resolve(wm.config.language)
            prefs.model.config = wm.config
            Hotkeys.shared.register(wm.config.bindings)
            wm.reconcile(force: true)
        case "set" where args.count == 2:
            switch (args[0], args[1]) {
            case ("layout", let v): if let l = Layout(rawValue: v) { wm.update { $0.layout = l } } else { out["ok"] = false }
            case ("preset", let v): if let p = Preset(rawValue: v) { wm.update { $0.layout = .grid; $0.preset = p } } else { out["ok"] = false }
            case ("hard", let v): wm.update { $0.hard = v == "true" }
            case ("login", let v): prefs.model.setLoginItem(v == "true"); out["login"] = prefs.model.loginItem
            default: out["ok"] = false
            }
        case "snapshot" where args.count == 2:   // draw a panel into a PNG, to check the design
            if let s = PrefsModel.Section(rawValue: args[0].capitalized) { prefs.model.section = s; prefs.show() } else { keysheet.show() }
            let win = PrefsModel.Section(rawValue: args[0].capitalized) != nil ? prefs.window : keysheet.panel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let v = win.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[1]))
            }
        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
        default:
            // `--window <id>` (ids come from `query`) acts on that window instead of the focused one.
            if args.count == 2, args[0] == "--window" { wm.subject = UInt32(args[1]) }
            out["ok"] = run(cmd)
            if cmd.hasPrefix("resize-") { run(cmd, pressed: false) }   // a tap: three steps
            wm.subject = nil
        }
        try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: reply), options: .atomic)
    }
}

// MARK: - Command line client

enum CLI {
    static func run(_ args: [String]) -> Int32 {
        switch args[0] {
        case "-h", "--help", "help":
            print("usage: aeris-tiler <action> [--window <id>] | set layout|preset|hard|login <value> | query | reload | actions | quit")
            return 0
        case "actions":
            let c = Config.load()
            for a in Action.all { print(a.id.padding(toLength: 24, withPad: " ", startingAt: 0), (c.bindings[a.id] ?? "").padding(toLength: 24, withPad: " ", startingAt: 0), a.title) }
            return 0
        case "make-icon":
            return args.count == 2 && Icon.write(iconset: args[1]) ? 0 : 1
        default: break
        }
        // Ask the running app; it answers through a file.
        let reply = NSTemporaryDirectory() + "aeris-tiler-\(UUID().uuidString).json"
        DistributedNotificationCenter.default().postNotificationName(commandName, object: nil,
            userInfo: ["cmd": args[0], "args": Array(args.dropFirst()), "reply": reply], deliverImmediately: true)
        for _ in 0..<250 {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: reply)) {
                try? FileManager.default.removeItem(atPath: reply)
                print(String(decoding: data, as: UTF8.self))
                return String(decoding: data, as: UTF8.self).contains("\"ok\" : false") ? 1 : 0
            }
            usleep(20_000)
        }
        FileHandle.standardError.write(Data("aeris-tiler: the app is not running\n".utf8))
        return 1
    }
}

// MARK: - App icon: a black field with white windows in 3 | 6 | 3

enum Icon {
    static func write(iconset dir: String) -> Bool {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let px = points * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return false }
            NSGraphicsContext.current = ctx
            let s = CGFloat(px) / 1024
            // Apple's icon grid: an 824 pt rounded square inside 1024 pt.
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s).fill()
            NSColor.white.setFill()
            let frames = Tree(.swiss, windows: [1, 2, 3, 4, 5], in: CGRect(x: 232, y: 262, width: 560, height: 500), gap: 28)
                .frames(in: CGRect(x: 232, y: 262, width: 560, height: 500), gap: 28)
            for f in frames.values { NSRect(x: f.minX * s, y: f.minY * s, width: f.width * s, height: f.height * s).fill() }
            ctx.flushGraphics()
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: URL(fileURLWithPath: dir + "/" + name))) != nil else { return false }
        }
        return true
    }
}

// MARK: - Entry

let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty { exit(CLI.run(arguments)) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
