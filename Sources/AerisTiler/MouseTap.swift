// Mouse behaviour (what yabai's mouse settings and the Hammerspoon script did), in one event tap:
//   focus follows mouse; ctrl + drag moves a window, ctrl + right-drag resizes it;
//   selecting text copies it; right-click in the focused text field pastes.
import AppKit
import ApplicationServices
import TilerCore

final class MouseTap {
    private let wm: WindowManager
    private var tap: CFMachPort?
    private var downAt: CGPoint?          // where the left button went down (copy on select, title-bar drags)
    private var lastHover = 0.0

    private struct Drag {
        let win: Win, resize: Bool, tiled: Bool, start: CGPoint, frame: CGRect
        let left: Bool, top: Bool         // which corner a resize moves
        var applied: CGPoint              // mouse position the window already follows
    }
    private var drag: Drag?
    private var dragPoint: CGPoint?       // newest mouse position not yet applied

    init(_ wm: WindowManager) { self.wm = wm }

    func start() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, ref in
            let me = Unmanaged<MouseTap>.fromOpaque(ref!).takeUnretainedValue()
            return me.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ e: CGEvent) -> Bool {
        let p = e.location, flags = e.flags, c = wm.config
        let plain = flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift]).isEmpty
        let ctrlOnly = flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift]) == .maskControl
        if wm.moving, type != .tapDisabledByTimeout { return false }   // the app's own hold on a window: hands off
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }   // macOS turns a slow tap off

        case .mouseMoved:
            hover(p)

        case .leftMouseDown, .rightMouseDown:
            let right = type == .rightMouseDown
            if c.mouseDrag, ctrlOnly, !wm.paused, let w = wm.window(at: p) {
                let f = w.ax.frame ?? w.frame
                drag = Drag(win: w, resize: right, tiled: wm.isTiled(w), start: p, frame: f, left: p.x < f.midX, top: p.y < f.midY, applied: p)
                wm.focus(w, raise: !wm.isTiled(w))
                return true
            }
            if right { return c.rightClickPaste && !flags.contains(.maskAlternate) && paste(p) }
            downAt = plain ? p : nil

        case .leftMouseDragged, .rightMouseDragged:
            guard drag != nil else { break }
            if dragPoint == nil { DispatchQueue.main.async { [weak self] in self?.applyDrag() } }   // at most one move per run-loop turn
            dragPoint = p
            return true

        case .leftMouseUp, .rightMouseUp:
            if let d = drag {
                drag = nil; dragPoint = nil
                DispatchQueue.main.async { [wm] in
                    if !d.resize { wm.drop(d.win.id, at: p) }
                    wm.reconcile(force: true)
                }
                return true
            }
            guard type == .leftMouseUp, let down = downAt else { break }
            downAt = nil
            let dragged = abs(p.x - down.x) + abs(p.y - down.y) > 6
            if dragged {
                // A tiled window dragged by its title bar: swap with the window it lands on, or go back.
                DispatchQueue.main.async { [wm] in
                    if let w = wm.focused, let t = wm.targets[w.id], let f = w.ax.frame, abs(f.minX - t.minX) + abs(f.minY - t.minY) > 6 { wm.drop(w.id, at: p) }
                    wm.reconcile(force: true)
                }
            }
            if c.copyOnSelect, plain, dragged || e.getIntegerValueField(.mouseEventClickState) >= 2 { copySelection(dragged) }

        default: break
        }
        return false
    }

    // MARK: Focus follows mouse

    private func hover(_ p: CGPoint) {
        let mode = wm.config.focusFollowsMouse, now = ProcessInfo.processInfo.systemUptime
        guard mode != .off, !wm.paused, now - lastHover > 0.04 else { return }
        lastHover = now
        // Not while a button is down, and not while one of this app's panels has the keyboard.
        guard NSEvent.pressedMouseButtons == 0, NSApp.keyWindow == nil, let w = wm.window(at: p), w.standard else { return }
        wm.focus(w, raise: mode == .raise)
    }

    // MARK: Ctrl + drag

    private func applyDrag() {
        guard var d = drag, let p = dragPoint else { dragPoint = nil; return }
        dragPoint = nil
        let dx = p.x - d.start.x, dy = p.y - d.start.y
        if !d.resize {
            d.win.ax.setPosition(CGPoint(x: d.frame.minX + dx, y: d.frame.minY + dy))
        } else if d.tiled {
            wm.drag(d.win.id, dx: p.x - d.applied.x, dy: p.y - d.applied.y)
        } else {
            var f = d.frame   // the corner nearest to where the drag started follows the mouse
            if d.left { f.origin.x += dx; f.size.width -= dx } else { f.size.width += dx }
            if d.top { f.origin.y += dy; f.size.height -= dy } else { f.size.height += dy }
            if f.width >= 120, f.height >= 80 { d.win.ax.setFrame(f) }
        }
        d.applied = p
        if drag != nil { drag = d }
    }

    // MARK: Linux-style clipboard

    private var skipped: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return wm.config.clipboardSkipApps.contains(id)
    }

    private var focusedElement: AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.2)
        return sys.element(kAXFocusedUIElementAttribute)
    }

    /// After a drag or a double / triple click: copy what is selected.
    private func copySelection(_ dragged: Bool) {
        guard !skipped else { return }
        // Wait for the app to finish updating its selection, then read it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
            let text: String? = focusedElement?.get(kAXSelectedTextAttribute)
            if let text, !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } else if dragged, text == nil {
                pressCommand(8)   // the app hides its selection from macOS: send a real ⌘C
            }
        }
    }

    /// Right-click on the focused text field pastes. Returns true when it did.
    private func paste(_ p: CGPoint) -> Bool {
        guard !skipped, let el = focusedElement, let role: String = el.get(kAXRoleAttribute),
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role),
              let f = el.frame, f.contains(p) else { return false }
        pressCommand(9)   // ⌘V
        return true
    }
}
