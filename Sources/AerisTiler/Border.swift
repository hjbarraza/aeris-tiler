// A border around the focused window (what JankyBorders did): a transparent, click-through
// window of our own, drawn just outside the focused window and stacked right above it.
import AppKit
import CPrivate
import TilerCore

final class Border {
    private let window: NSWindow
    private let shape = CAShapeLayer()
    private(set) var target: WindowID?

    var windowID: WindowID { WindowID(window.windowNumber) }

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView?.wantsLayer = true
        shape.fillColor = nil
        shape.actions = ["path": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull()]   // no implicit animation
        window.contentView?.layer?.addSublayer(shape)
    }

    /// Wrap the window `id`, whose frame is `frame` (origin top left).
    func show(_ id: WindowID, _ frame: CGRect, _ c: Config) {
        let w = CGFloat(c.borderWidth)
        let outer = flip(frame.insetBy(dx: -w, dy: -w))
        window.setFrame(outer, display: false)
        let rect = CGRect(origin: .zero, size: outer.size).insetBy(dx: w / 2, dy: w / 2)
        let radius = CGFloat(c.borderRadius) + w / 2
        shape.frame = CGRect(origin: .zero, size: outer.size)
        shape.path = CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil)
        shape.lineWidth = w
        shape.strokeColor = NSColor(hex: c.borderColor).cgColor
        if !window.isVisible { window.orderFrontRegardless() }
        SLSOrderWindow(SLSMainConnectionID(), windowID, 1 /* above */, id)
        target = id
    }

    func hide() {
        target = nil
        window.orderOut(nil)
    }
}

extension NSColor {
    /// "#808080" -> colour; anything unreadable is mid grey.
    convenience init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x808080
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    var hex: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
