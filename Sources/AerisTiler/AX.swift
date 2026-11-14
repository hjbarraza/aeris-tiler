// Small helpers over the macOS Accessibility API, which is how the app reads and moves windows.
import AppKit
import ApplicationServices
import CPrivate

extension AXUIElement {
    func get<T>(_ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success else { return nil }
        return v as? T
    }

    func element(_ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private func value(_ attr: String) -> AXValue? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }

    func canSet(_ attr: String) -> Bool {
        var ok: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, attr as CFString, &ok) == .success && ok.boolValue
    }

    /// The window server id of a window element.
    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    /// Frame in screen coordinates, origin top left.
    var frame: CGRect? {
        guard let p = value(kAXPositionAttribute), let s = value(kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p, .cgPoint, &origin)
        AXValueGetValue(s, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    func setPosition(_ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, v) }
    }

    func setSize(_ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, v) }
    }

    /// Size, position, size: macOS clips a size that would leave the screen at the old position,
    /// and clips a position for the old size, so the size goes on both sides of the move.
    func setFrame(_ r: CGRect) {
        setSize(r.size)
        setPosition(r.origin)
        setSize(r.size)
    }
}

/// AppKit screens count y from the bottom of the main screen; windows count from its top.
func flip(_ r: CGRect) -> CGRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

/// Press a key with ⌘ held (copy and paste for the mouse clipboard).
func pressCommand(_ key: CGKeyCode) {
    let src = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
        e?.flags = .maskCommand
        e?.post(tap: .cghidEventTap)
    }
}
