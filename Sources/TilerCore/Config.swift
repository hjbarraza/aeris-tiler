// Settings, actions and key combos. The config is one JSON file that people, the preferences
// window and agents all edit: ~/.config/aeris-tiler/config.json
import Foundation

// MARK: - Key combos, written like skhd: "ctrl+alt-left"

public struct KeyCombo: Equatable {
    public var mods: [String]   // subset of KeyCombo.modOrder, in that order
    public var key: String      // a name from KeyCombo.keyCodes

    public static let modOrder = ["ctrl", "alt", "shift", "cmd"]
    static let modSymbols = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
    static let modNames = ["ctrl": "Ctrl", "alt": "Option", "shift": "Shift", "cmd": "Cmd"]
    static let keySymbols = ["left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩",
                             "space": "Space", "tab": "⇥", "escape": "⎋", "delete": "⌫"]

    /// Key name -> macOS virtual key code (ANSI layout).
    public static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "'": 39, "k": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "`": 50, "delete": 51, "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    public static let keyNames: [UInt32: String] = Dictionary(uniqueKeysWithValues: keyCodes.map { ($1, $0) })

    public init(mods: [String], key: String) {
        self.mods = KeyCombo.modOrder.filter(mods.contains)
        self.key = key
    }

    /// Parse "ctrl+alt-left". At least one modifier is required.
    public init?(_ spec: String) {
        guard let dash = spec.firstIndex(of: "-") else { return nil }
        let mods = spec[..<dash].split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let key = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces).lowercased()
        guard !mods.isEmpty, mods.allSatisfy(KeyCombo.modOrder.contains), KeyCombo.keyCodes[key] != nil else { return nil }
        self.init(mods: mods, key: key)
    }

    public var spec: String { mods.joined(separator: "+") + "-" + key }
    public var keyCode: UInt32 { KeyCombo.keyCodes[key]! }
    /// ["⌃", "⌥", "←"]
    public var parts: [String] { mods.map { KeyCombo.modSymbols[$0]! } + [KeyCombo.keySymbols[key] ?? key.uppercased()] }
    /// "⌃⌥←"
    public var symbols: String { parts.joined() }
    /// "Ctrl + Option + Left"
    public var spelled: String { (mods.map { KeyCombo.modNames[$0]! } + [key.capitalized]).joined(separator: " + ") }
}

// MARK: - Actions: everything a hotkey, the menu or the command line can run

public struct Action {
    public let id: String, title: String, group: String, keys: String?

    public static let all: [Action] = {
        var a: [Action] = []
        for d in Direction.allCases { a.append(Action(id: "focus-\(d)", title: "Focus window \(d)", group: "Focus", keys: "ctrl+alt-\(d)")) }
        for d in Direction.allCases { a.append(Action(id: "swap-\(d)", title: "Swap window \(d)", group: "Swap", keys: "ctrl+alt+cmd-\(d)")) }
        for d in Direction.allCases { a.append(Action(id: "resize-\(d)", title: "Move border \(d) (hold)", group: "Resize", keys: "ctrl+cmd-\(d)")) }
        a += [
            Action(id: "cycle-layout", title: "Cycle layout: tile, grid, float", group: "Layout", keys: "alt+cmd-left"),
            Action(id: "cycle-preset", title: "Grid preset: swiss, columns, main, board", group: "Layout", keys: "ctrl+alt-g"),
            Action(id: "toggle-hard", title: "Grid hard or soft: lock or free the sizes", group: "Layout", keys: "ctrl+alt-h"),
            Action(id: "toggle-split", title: "Flip split: columns or rows", group: "Layout", keys: "ctrl+alt-j"),
            Action(id: "balance", title: "Balance splits", group: "Layout", keys: "ctrl+alt-b"),
            Action(id: "pause", title: "Pause or resume tiling", group: "Layout", keys: "ctrl+alt-p"),
            Action(id: "maximize", title: "Maximize or restore", group: "Window", keys: "alt+cmd-up"),
            Action(id: "toggle-float", title: "Float or unfloat", group: "Window", keys: "alt+cmd-down"),
            Action(id: "next-display", title: "Move to other display", group: "Window", keys: "alt+cmd-right"),
        ]
        let snapKeys: [Snap: String] = [
            .leftHalf: "left", .rightHalf: "right", .topHalf: "up", .bottomHalf: "down",
            .topLeft: "u", .topRight: "i", .bottomLeft: "j", .bottomRight: "k",
            .leftThird: "d", .centerThird: "f", .rightThird: "g",
            .leftTwoThirds: "e", .rightTwoThirds: "t", .center: "c", .full: "return",
        ]
        for s in Snap.allCases { a.append(Action(id: "snap-\(s.rawValue)", title: "Snap: \(s.title.lowercased())", group: "Snap", keys: "ctrl+alt+shift-\(snapKeys[s]!)")) }
        for n in 1...9 { a.append(Action(id: "space-\(n)", title: "Move window to space \(n)", group: "Spaces", keys: "ctrl+alt+cmd-\(n)")) }
        a += [
            Action(id: "keysheet", title: "Keysheet: search these keys", group: "App", keys: "cmd-k"),
            Action(id: "preferences", title: "Preferences", group: "App", keys: nil),
        ]
        return a
    }()

    public static let byID: [String: Action] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

// MARK: - Config

public enum FocusMode: String, Codable, CaseIterable { case off, focus, raise }

public struct Config: Codable, Equatable {
    public var gap = 8.0                    // gutter between windows
    public var padding = 8.0                // space to the screen edge
    public var defaultLayout = Layout.tile  // layout of a space seen for the first time
    public var gridPreset = Preset.swiss    // grid arrangement of a space seen for the first time
    public var gridHard = true              // hard grid: sizes are locked; soft grid: borders move
    public var openOnMouseDisplay = true    // new windows open on the display under the mouse
    public var focusFollowsMouse = FocusMode.focus
    public var mouseDrag = true             // ctrl + drag moves a window, ctrl + right-drag resizes it
    public var copyOnSelect = true          // selecting text copies it
    public var rightClickPaste = true       // right-click in the focused text field pastes
    public var clipboardSkipApps = ["com.mitchellh.ghostty", "com.apple.finder"]  // bundle ids
    public var border = true                // border on the focused window
    public var borderWidth = 4.0
    public var borderRadius = 16.0          // corner radius of the windows the border wraps
    public var borderColor = "#808080"
    public var floatApps = ["System Settings", "Calculator", "Archive Utility", "App Store", "Activity Monitor", "Raycast"]
    public var bindings: [String: String] = Dictionary(uniqueKeysWithValues: Action.all.compactMap { a in a.keys.map { (a.id, $0) } })

    public init() {}

    public static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aeris-tiler/config.json")
    }

    /// Decode a config; any key the JSON leaves out keeps its default. `bindings` merges per
    /// action, and an empty string unbinds an action.
    public static func decode(_ data: Data) throws -> Config {
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as! [String: Any]
        guard let given = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Config() }
        var merged = defaults.merging(given) { $1 }
        if let b = given["bindings"] as? [String: Any] {
            merged["bindings"] = (defaults["bindings"] as! [String: Any]).merging(b) { $1 }
        }
        return try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: url), let c = try? decode(data) else { return Config() }
        return c
    }

    public func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(self).write(to: Config.url, options: .atomic)
    }

    public func combo(_ action: String) -> KeyCombo? { bindings[action].flatMap { KeyCombo($0) } }
}
