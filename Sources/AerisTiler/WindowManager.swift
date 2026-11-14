// The window manager: reads the windows on screen, keeps one layout per space, and places
// windows through Accessibility. Everything runs on the main thread.
//
// Model: any event (window opened, closed, focused, space changed, hotkey) calls reconcile(),
// which reads the real windows, syncs each visible space's layout to them, and moves only the
// windows that are not where the layout wants them. There is no other state to keep in step.
import AppKit
import ApplicationServices
import CPrivate
import TilerCore

struct Win {
    let id: WindowID
    let pid: pid_t
    let ax: AXUIElement
    let app: String
    var frame: CGRect
    var screen: Int        // index into WindowManager.screens()
    let standard: Bool     // a normal window: not a dialog, sheet or popover
    let resizable: Bool
    let fullscreen: Bool
}

struct Screen {
    let visible: CGRect    // without menu bar and Dock, origin top left
    let space: UInt64      // the space this display shows now
    let fullscreen: Bool   // that space is a macOS full-screen app
}

final class SpaceState {
    var layout: Layout
    var preset: Preset           // grid arrangement
    var hard: Bool               // hard grid: sizes locked; soft grid: borders move
    let tree = Tree()            // tile: grows by splitting the focused window
    var grid = Tree()            // grid: built from the preset
    var gridKey = ""             // what `grid` was built for
    var order: [WindowID] = []   // grid: window order
    var zoomed: WindowID?        // maximized inside the layout
    var active: Tree { layout == .grid ? grid : tree }
    init(_ layout: Layout, _ preset: Preset, hard: Bool) { self.layout = layout; self.preset = preset; self.hard = hard }
}

final class WindowManager {
    var config = Config.load()
    var paused = false
    var onChange: (() -> Void)?   // the menu bar label follows the layout

    private(set) var wins: [Win] = []                  // last reading, front to back
    private(set) var targets: [WindowID: CGRect] = [:] // where the layout wants each tiled window
    private var spaces: [UInt64: SpaceState] = [:]
    private var floating: Set<WindowID> = []           // windows floated by hand
    private var restore: [WindowID: CGRect] = [:]      // frame before a floating maximize
    private var seen: Set<WindowID> = []
    private var seeded = false
    private var lastFocus: WindowID?
    private var axApps: [pid_t: AXUIElement] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var watched: Set<WindowID> = []
    private var pending: DispatchWorkItem?
    private var hold: Hold?
    let border = Border()
    private let cid = SLSMainConnectionID()
    private let me = getpid()

    // MARK: - Start

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.schedule() }
        }
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            // A new app has no window yet; watch it now and look again when it has drawn.
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.observe(app.processIdentifier) }
            for delay in [0.3, 1.0, 2.5] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.schedule() } }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.observers[app.processIdentifier] = nil
            self?.axApps[app.processIdentifier] = nil
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.schedule() }
        reconcile()
    }

    /// Reconcile soon; events that arrive together cost one pass.
    func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    func setConfig(_ c: Config) {
        config = c
        c.save()
        reconcile()
    }

    // MARK: - Reading the screen

    func screens() -> [Screen] {
        let managed = (SLSCopyManagedDisplaySpaces(cid) as? [[String: Any]]) ?? []
        return NSScreen.screens.map { s in
            var uuid = ""
            if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let u = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() {
                uuid = CFUUIDCreateString(nil, u) as String
            }
            // With "Displays have separate Spaces" off there is one entry, named "Main".
            let d = managed.first { $0["Display Identifier"] as? String == uuid } ?? managed.first
            let cur = d?["Current Space"] as? [String: Any]
            return Screen(visible: flip(s.visibleFrame), space: cur?["id64"] as? UInt64 ?? 0, fullscreen: (cur?["type"] as? Int ?? 0) != 0)
        }
    }

    /// Ids of the user's spaces in Mission Control order (full-screen apps left out).
    private func userSpaces() -> [UInt64] {
        let managed = (SLSCopyManagedDisplaySpaces(cid) as? [[String: Any]]) ?? []
        return managed.flatMap { ($0["Spaces"] as? [[String: Any]]) ?? [] }
            .filter { ($0["type"] as? Int ?? 0) == 0 }.compactMap { $0["id64"] as? UInt64 }
    }

    private func axApp(_ pid: pid_t) -> AXUIElement {
        if let a = axApps[pid] { return a }
        let a = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(a, 0.25)   // a hung app must not hang the window manager
        axApps[pid] = a
        return a
    }

    private func screenIndex(_ f: CGRect, _ screens: [Screen]) -> Int {
        let c = CGPoint(x: f.midX, y: f.midY)
        if let i = screens.firstIndex(where: { $0.visible.insetBy(dx: -1, dy: -40).contains(c) }) { return i }
        func overlap(_ s: Screen) -> CGFloat { let r = s.visible.intersection(f); return r.isNull ? 0 : r.width * r.height }
        return screens.indices.max { overlap(screens[$0]) < overlap(screens[$1]) } ?? 0
    }

    /// Every window on screen that Accessibility can reach, front to back.
    private func snapshot(_ screens: [Screen]) -> [Win] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var order: [WindowID] = [], pids: [pid_t] = []
        for e in list {
            guard e[kCGWindowLayer as String] as? Int == 0, let id = e[kCGWindowNumber as String] as? WindowID,
                  let pid = e[kCGWindowOwnerPID as String] as? pid_t, pid != me else { continue }
            order.append(id)
            if !pids.contains(pid) { pids.append(pid) }
        }
        let onScreen = Set(order)
        var found: [WindowID: Win] = [:]
        for pid in pids {
            observe(pid)
            guard let axWins: [AXUIElement] = axApp(pid).get(kAXWindowsAttribute) else { continue }
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
            for w in axWins {
                guard let id = w.windowID, onScreen.contains(id), let f = w.frame,
                      (w.get(kAXMinimizedAttribute) as Bool?) != true else { continue }
                watch(w, id, pid)
                found[id] = Win(id: id, pid: pid, ax: w, app: name, frame: f, screen: screenIndex(f, screens),
                                standard: (w.get(kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole,
                                resizable: w.canSet(kAXSizeAttribute),
                                fullscreen: (w.get("AXFullScreen") as Bool?) == true)
            }
        }
        return order.compactMap { found[$0] }
    }

    // MARK: - Events from apps

    /// Listen to one app: windows opening, closing to the Dock, focus moving.
    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, pid != me else { return }
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            Unmanaged<WindowManager>.fromOpaque(refcon!).takeUnretainedValue().axEvent(notification as String, element)
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                  kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(obs, axApp(pid), n as CFString, ref)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    /// Listen to one window: closed, moved, resized.
    private func watch(_ w: AXUIElement, _ id: WindowID, _ pid: pid_t) {
        guard !watched.contains(id), let obs = observers[pid] else { return }
        watched.insert(id)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXUIElementDestroyedNotification, kAXMovedNotification, kAXResizedNotification] {
            AXObserverAddNotification(obs, w, n as CFString, ref)
        }
    }

    private func axEvent(_ name: String, _ element: AXUIElement) {
        if name == kAXMovedNotification || name == kAXResizedNotification {
            // Only the border has to follow at once; the layout waits for the mouse button.
            if let id = element.windowID, id == border.target, let f = element.frame { border.show(id, f, config) }
        } else {
            schedule()
        }
    }

    // MARK: - Reconcile

    private func state(_ space: UInt64) -> SpaceState {
        if let s = spaces[space] { return s }
        // Saved per space as "grid/swiss/hard".
        let saved = ((UserDefaults.standard.dictionary(forKey: "layouts")?[String(space)] as? String) ?? "").split(separator: "/").map(String.init)
        let s = SpaceState(saved.first.flatMap(Layout.init) ?? config.defaultLayout,
                           saved.count > 1 ? Preset(rawValue: saved[1]) ?? config.gridPreset : config.gridPreset,
                           hard: saved.count > 2 ? saved[2] == "hard" : config.gridHard)
        spaces[space] = s
        return s
    }

    /// The state of the space under the mouse, unless it is a full-screen app.
    var current: (space: UInt64, state: SpaceState)? {
        let s = screens()
        guard mouseScreen < s.count, !s[mouseScreen].fullscreen else { return nil }
        return (s[mouseScreen].space, state(s[mouseScreen].space))
    }

    /// Change the space under the mouse and remember the choice.
    func update(_ change: (SpaceState) -> Void) {
        guard let (space, st) = current else { return }
        change(st)
        st.zoomed = nil
        var saved = UserDefaults.standard.dictionary(forKey: "layouts") ?? [:]
        saved[String(space)] = "\(st.layout.rawValue)/\(st.preset.rawValue)/\(st.hard ? "hard" : "soft")"
        UserDefaults.standard.set(saved, forKey: "layouts")
        reconcile(force: true)
    }

    func area(_ screen: Screen) -> CGRect { workArea(screen.visible, padding: config.padding) }

    func isTileable(_ w: Win) -> Bool {
        w.standard && w.resizable && !w.fullscreen && !floating.contains(w.id) && !config.floatApps.contains(w.app)
    }

    /// True when the layout places this window now.
    func isTiled(_ w: Win) -> Bool { targets[w.id] != nil }

    var focusedID: WindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != me else { return nil }
        return axApp(pid).element(kAXFocusedWindowAttribute)?.windowID
    }

    var focused: Win? { focusedID.flatMap { id in wins.first { $0.id == id } } }

    var mouseScreen: Int {
        NSScreen.screens.firstIndex { $0.frame.contains(NSEvent.mouseLocation) } ?? 0
    }

    /// Read the windows, sync the layouts, move what is out of place. `force` also moves
    /// windows while a mouse button is down.
    func reconcile(force: Bool = false) {
        pending?.cancel()
        guard AXIsProcessTrusted() else { return }
        let screens = self.screens()
        var snap = snapshot(screens)
        let focus = focusedID

        // New windows open on the display under the mouse.
        if seeded, config.openOnMouseDisplay, !paused, mouseScreen < screens.count {
            let target = mouseScreen, v = screens[target].visible
            for i in snap.indices where !seen.contains(snap[i].id) && snap[i].standard && snap[i].screen != target {
                let f = snap[i].frame
                let moved = CGRect(x: v.midX - min(f.width, v.width) / 2, y: v.midY - min(f.height, v.height) / 2, width: f.width, height: f.height)
                snap[i].ax.setPosition(moved.origin)
                snap[i].frame = moved
                snap[i].screen = target
            }
        }
        seen.formUnion(snap.map(\.id))
        seeded = true
        wins = snap
        targets = [:]

        if !paused {
            for (i, screen) in screens.enumerated() where !screen.fullscreen && screen.space != 0 {
                let st = state(screen.space), area = self.area(screen), gap = config.gap
                let tile = snap.filter { $0.screen == i && isTileable($0) }
                let ids = Set(tile.map(\.id))
                // First fill: left to right, top to bottom. Later, new windows go last.
                let fresh = tile.filter { st.layout == .tile ? !st.tree.contains($0.id) : !st.order.contains($0.id) }
                    .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
                for w in fresh { for (id, other) in spaces where id != screen.space { other.tree.remove(w.id); other.order.removeAll { $0 == w.id } } }
                var frames: [WindowID: CGRect] = [:]
                switch st.layout {
                case .tile:
                    for w in st.tree.windows where !ids.contains(w) { st.tree.remove(w) }
                    // One new window splits the window that had focus, like Hyprland.
                    let beside = fresh.count == 1 ? (focus == fresh[0].id ? lastFocus : focus) : nil
                    for w in fresh { st.tree.insert(w.id, beside: beside, in: area, gap: gap) }
                    frames = st.tree.frames(in: area, gap: gap)
                case .grid:
                    st.order = st.order.filter(ids.contains) + fresh.map(\.id)
                    // Build from the preset when the windows, the preset or the area change.
                    // Until then a soft grid keeps the borders the user moved.
                    let key = "\(st.preset) \(st.order.sorted()) \(area)"
                    if key != st.gridKey { st.grid = Tree(st.preset, windows: st.order, in: area, gap: gap); st.gridKey = key }
                    frames = st.grid.frames(in: area, gap: gap)
                case .float:
                    break
                }
                if let z = st.zoomed { if frames[z] != nil { frames[z] = area } else { st.zoomed = nil } }
                targets.merge(frames) { $1 }
            }
            // A window dragged by its title bar stays under the mouse until the button is up.
            if force || NSEvent.pressedMouseButtons & 1 == 0 { apply() }
        }
        if let focus, snap.contains(where: { $0.id == focus }) { lastFocus = focus }
        updateBorder()
        onChange?()
    }

    private func apply() {
        for i in wins.indices {
            guard let t = targets[wins[i].id], !near(wins[i].frame, t) else { continue }
            wins[i].ax.setFrame(t)
            var f = wins[i].ax.frame ?? t
            // A window sometimes keeps a wrong size (seen with Brave and Safari at full
            // height): ask for a clearly different size first, then the right one.
            if abs(f.width - t.width) > 1 || abs(f.height - t.height) > 1 {
                wins[i].ax.setSize(CGSize(width: t.width - 100, height: t.height - 100))
                wins[i].ax.setSize(t.size)
                f = wins[i].ax.frame ?? t
            }
            wins[i].frame = f
        }
    }

    private func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }

    private func updateBorder() {
        if config.border, let w = focused, w.standard, !w.fullscreen {
            border.show(w.id, w.ax.frame ?? w.frame, config)
        } else {
            border.hide()
        }
    }

    // MARK: - Focus

    func focus(_ w: Win, raise: Bool) {
        guard w.id != focusedID else { return }
        let cur = focused
        aeris_focus_window(w.pid, w.id, cur?.pid ?? 0, cur?.id ?? 0, raise)
        if raise { AXUIElementPerformAction(w.ax, kAXRaiseAction as CFString) }
    }

    /// The topmost window under a point, or nil when something that is not a normal window
    /// (a menu, the Dock, one of this app's panels) is on top there.
    func window(at p: CGPoint) -> Win? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for e in list {
            guard let b = e[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b), r.contains(p),
                  let id = e[kCGWindowNumber as String] as? WindowID else { continue }
            if id == border.windowID { continue }
            if e[kCGWindowLayer as String] as? Int != 0 {
                // Some apps keep an invisible overlay over a whole screen; a menu never is that big.
                if NSScreen.screens.contains(where: { r.contains(flip($0.frame).insetBy(dx: 1, dy: 1)) }) { continue }
                return nil
            }
            return wins.first { $0.id == id }
        }
        return nil
    }

    // MARK: - Actions

    /// Run an action by id (see Action.all). `pressed` is false when a hotkey is released.
    /// Returns false for an unknown id.
    @discardableResult
    func perform(_ id: String, pressed: Bool = true) -> Bool {
        let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        if parts[0] == "resize", let d = Direction(rawValue: arg) {
            if pressed { startResize(d) } else { hold?.released = true }
            return true
        }
        guard pressed else { return true }
        reconcile()   // act on what is on screen now
        switch (parts[0], arg) {
        case ("focus", _): guard let d = Direction(rawValue: arg) else { return false }; focus(d)
        case ("swap", _): guard let d = Direction(rawValue: arg) else { return false }; swap(d)
        case ("snap", _): guard let s = Snap(rawValue: arg) else { return false }; snap(s)
        case ("space", _): guard let n = Int(arg) else { return false }; toSpace(n)
        case ("cycle", "layout"): update { $0.layout = $0.layout.next }
        case ("cycle", "preset"): update { if $0.layout == .grid { $0.preset = $0.preset.next } else { $0.layout = .grid } }
        case ("toggle", "hard"): update { $0.hard.toggle() }
        case ("toggle", "split"): withState { st, w in if st.layout == .tile { st.tree.toggleSplit(w.id) } }
        case ("toggle", "float"): toggleFloat()
        case ("next", "display"): nextDisplay()
        case ("balance", _): withState { st, _ in st.tree.balance(); st.gridKey = "" }   // the grid goes back to its preset
        case ("maximize", _): maximize()
        case ("pause", _): paused.toggle()
        default: return false
        }
        reconcile(force: true)
        return true
    }

    private func focus(_ d: Direction) {
        guard let me = focused else {
            if let w = wins.first(where: { $0.screen == mouseScreen && $0.standard }) { focus(w, raise: true) }
            return
        }
        let others = wins.filter { $0.id != me.id && $0.standard }.map { (id: $0.id, frame: $0.frame) }
        if let id = neighbor(of: me.frame, d, among: others), let w = wins.first(where: { $0.id == id }) { focus(w, raise: true) }
    }

    /// The focused window, its space state and screen, when the layout places that window.
    private func withState(_ body: (SpaceState, Win) -> Void) {
        let s = screens()
        guard let w = focused, isTiled(w), w.screen < s.count else { return }
        body(state(s[w.screen].space), w)
    }

    private func swap(_ d: Direction) {
        withState { st, me in
            let others = wins.filter { $0.id != me.id && $0.screen == me.screen && isTiled($0) }.map { (id: $0.id, frame: targets[$0.id]!) }
            guard let other = neighbor(of: targets[me.id]!, d, among: others) else { return }
            st.active.swap(me.id, other)
            if let a = st.order.firstIndex(of: me.id), let b = st.order.firstIndex(of: other) { st.order.swapAt(a, b) }
        }
    }

    /// Swap a tiled window with the tiled window under a point (drop after a drag).
    func drop(_ id: WindowID, at p: CGPoint) {
        let s = screens()
        guard let me = wins.first(where: { $0.id == id }), isTiled(me), me.screen < s.count,
              let other = wins.first(where: { $0.id != id && $0.screen == me.screen && targets[$0.id]?.contains(p) == true }) else { return }
        let st = state(s[me.screen].space)
        st.active.swap(id, other.id)
        if let a = st.order.firstIndex(of: id), let b = st.order.firstIndex(of: other.id) { st.order.swapAt(a, b) }
    }

    private func maximize() {
        let s = screens()
        guard let w = focused, w.screen < s.count else { return }
        if isTiled(w) {
            let st = state(s[w.screen].space)
            st.zoomed = st.zoomed == w.id ? nil : w.id
        } else if let old = restore.removeValue(forKey: w.id) {
            w.ax.setFrame(old)
        } else {
            restore[w.id] = w.frame
            w.ax.setFrame(area(s[w.screen]))
        }
    }

    private func toggleFloat() {
        let s = screens()
        guard let w = focused, w.screen < s.count else { return }
        if floating.remove(w.id) != nil { return }
        floating.insert(w.id)
        let a = area(s[w.screen])   // centred, two thirds of the area
        w.ax.setFrame(CGRect(x: a.minX + a.width / 6, y: a.minY + a.height / 6, width: a.width * 2 / 3, height: a.height * 2 / 3).integral)
    }

    private func snap(_ pos: Snap) {
        let s = screens()
        guard let w = focused, w.screen < s.count else { return }
        floating.insert(w.id)   // a snapped window leaves the layout
        w.ax.setFrame(pos.frame(in: area(s[w.screen]), gap: config.gap, size: w.frame.size))
    }

    private func nextDisplay() {
        let s = screens()
        guard let w = focused, s.count > 1 else { return }
        let v = area(s[(w.screen + 1) % s.count])
        let size = CGSize(width: min(w.frame.width, v.width), height: min(w.frame.height, v.height))
        w.ax.setFrame(CGRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height).integral)
    }

    private func toSpace(_ n: Int) {
        let ids = userSpaces()
        guard let w = focused, n >= 1, n <= ids.count else { return }
        if !aeris_move_window_to_space(w.id, ids[n - 1]) { NSSound.beep() }
    }

    // MARK: - Resize: hold a key to keep moving a border

    private final class Hold { var released = false, steps = 0 }
    private let step: CGFloat = 20   // Safari ignores a top-edge shrink under about 20 px
    private let tapSteps = 3         // a tap moves 60 px

    private func startResize(_ d: Direction) {
        guard hold == nil else { return }
        reconcile()
        let s = screens()
        guard let w = focused, w.screen < s.count else { return }
        let st = state(s[w.screen].space), area = self.area(s[w.screen])
        let h = Hold()
        hold = h
        let delta = d.sign * step

        // A hard grid owns window sizes: shake the window as a "no".
        if isTiled(w), st.layout == .grid, st.hard {
            for dx in [10, -20, 20, -20, 10] as [CGFloat] {
                w.ax.setPosition(CGPoint(x: (w.ax.frame ?? w.frame).minX + dx, y: w.frame.minY))
                usleep(30_000)
            }
            hold = nil
            return
        }

        // Apps have a minimum size. A tiled neighbour that refuses to shrink would spill over
        // the next window, so each step checks how far windows exceed their targets.
        func spill() -> CGFloat {
            wins.reduce(0) { sum, x in
                guard let t = targets[x.id], let f = x.ax.frame else { return sum }
                return sum + max(f.width - t.width - 2, 0) + max(f.height - t.height - 2, 0)
            }
        }
        let tiled = isTiled(w)
        var before = tiled ? spill() : 0

        func tick() {
            guard hold === h else { return }
            if h.released && h.steps >= tapSteps { hold = nil; return }
            if tiled {
                guard st.active.adjust(w.id, horizontal: d.isHorizontal, delta: delta, in: area, gap: config.gap) else { hold = nil; return }
                reconcile(force: true)
                let after = spill()
                if after > before {   // a neighbour hit its minimum: undo and stop
                    st.active.adjust(w.id, horizontal: d.isHorizontal, delta: -delta, in: area, gap: config.gap)
                    reconcile(force: true)
                    hold = nil
                    return
                }
                before = after
            } else {
                // Free window: the right or bottom edge moves, or the left or top one when the
                // window sits against the right or bottom of the screen.
                guard var f = w.ax.frame else { hold = nil; return }
                if d.isHorizontal {
                    if area.maxX - f.maxX < 40 && f.minX - area.minX >= 40 { f.origin.x += delta; f.size.width -= delta } else { f.size.width += delta }
                } else {
                    if area.maxY - f.maxY < 40 && f.minY - area.minY >= 40 { f.origin.y += delta; f.size.height -= delta } else { f.size.height += delta }
                }
                guard f.width >= 120, f.height >= 80 else { hold = nil; return }
                w.ax.setFrame(f)
                border.show(w.id, w.ax.frame ?? f, config)
            }
            h.steps += 1
            DispatchQueue.main.async(execute: tick)   // let the key release in between steps
        }
        tick()
    }

    /// Move one border of a tiled window by a mouse distance (ctrl + right-drag).
    func drag(_ id: WindowID, dx: CGFloat, dy: CGFloat) {
        let s = screens()
        guard let w = wins.first(where: { $0.id == id }), isTiled(w), w.screen < s.count else { return }
        let st = state(s[w.screen].space)
        guard st.layout == .tile || !st.hard else { return }
        if dx != 0 { st.active.adjust(id, horizontal: true, delta: dx, in: area(s[w.screen]), gap: config.gap) }
        if dy != 0 { st.active.adjust(id, horizontal: false, delta: dy, in: area(s[w.screen]), gap: config.gap) }
        reconcile(force: true)
    }

    // MARK: - State for the command line and tests

    func query() -> [String: Any] {
        reconcile()
        let s = screens()
        func arr(_ r: CGRect) -> [Int] { [Int(r.minX), Int(r.minY), Int(r.width), Int(r.height)] }
        return [
            "trusted": AXIsProcessTrusted(), "paused": paused, "focused": focusedID as Any? ?? NSNull(),
            "screens": s.enumerated().map { i, x in
                ["index": i, "area": arr(area(x)), "space": x.space, "space_number": (userSpaces().firstIndex(of: x.space) ?? -1) + 1,
                 "layout": x.fullscreen ? "full" : state(x.space).layout.rawValue,
                 "preset": state(x.space).preset.rawValue, "hard": state(x.space).hard] as [String: Any]
            },
            "windows": wins.map { w in
                ["id": w.id, "app": w.app, "frame": arr(w.ax.frame ?? w.frame), "target": targets[w.id].map(arr) as Any? ?? NSNull(),
                 "screen": w.screen, "tiled": isTiled(w), "floating": floating.contains(w.id), "standard": w.standard] as [String: Any]
            },
        ]
    }
}
