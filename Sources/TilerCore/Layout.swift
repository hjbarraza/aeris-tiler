// Layout maths. Rectangles use screen coordinates with the origin at the top left.
import CoreGraphics

public typealias WindowID = UInt32

public enum Layout: String, Codable, CaseIterable {
    case tile, grid, float
    public var next: Layout { self == .tile ? .grid : self == .grid ? .float : .tile }
    public var label: String { rawValue.uppercased() }
}

public enum Direction: String, CaseIterable {
    case left, right, up, down
    public var isHorizontal: Bool { self == .left || self == .right }
    public var sign: CGFloat { self == .left || self == .up ? -1 : 1 }
}

/// The area windows may use: the visible screen minus the outer padding.
public func workArea(_ visible: CGRect, padding: CGFloat) -> CGRect { visible.insetBy(dx: padding, dy: padding) }

// MARK: - Tile: a binary tree of splits (Hyprland dwindle, yabai bsp)

public enum Split { case columns, rows }

final class Node {
    weak var parent: Node?
    var first: Node?, second: Node?
    var split = Split.columns
    var ratio: CGFloat = 0.5
    var window: WindowID?
    init(window: WindowID? = nil) { self.window = window }
}

public final class Tree {
    var root: Node?
    public init() {}

    /// Windows in reading order of the tree (first child before second).
    public var windows: [WindowID] { leaves().compactMap(\.window) }
    public func contains(_ w: WindowID) -> Bool { leaf(w) != nil }

    private func leaves() -> [Node] {
        var out: [Node] = []
        func walk(_ n: Node?) {
            guard let n else { return }
            if n.window != nil { out.append(n) } else { walk(n.first); walk(n.second) }
        }
        walk(root)
        return out
    }

    private func leaf(_ w: WindowID) -> Node? { leaves().first { $0.window == w } }

    /// The rectangle of every node, keyed by identity.
    private func rects(_ area: CGRect, _ gap: CGFloat) -> [ObjectIdentifier: CGRect] {
        var out: [ObjectIdentifier: CGRect] = [:]
        func walk(_ n: Node?, _ r: CGRect) {
            guard let n else { return }
            out[ObjectIdentifier(n)] = r
            guard n.window == nil else { return }
            if n.split == .columns {
                let w = ((r.width - gap) * n.ratio).rounded()
                walk(n.first, CGRect(x: r.minX, y: r.minY, width: w, height: r.height))
                walk(n.second, CGRect(x: r.minX + w + gap, y: r.minY, width: r.width - w - gap, height: r.height))
            } else {
                let h = ((r.height - gap) * n.ratio).rounded()
                walk(n.first, CGRect(x: r.minX, y: r.minY, width: r.width, height: h))
                walk(n.second, CGRect(x: r.minX, y: r.minY + h + gap, width: r.width, height: r.height - h - gap))
            }
        }
        walk(root, area)
        return out
    }

    public func frames(in area: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        let r = rects(area, gap)
        var out: [WindowID: CGRect] = [:]
        for l in leaves() { out[l.window!] = r[ObjectIdentifier(l)] }
        return out
    }

    /// Add a window by splitting `target` (or the last window). The split follows the longer
    /// side of the window that is split, and the new window takes the second half.
    public func insert(_ w: WindowID, beside target: WindowID? = nil, in area: CGRect, gap: CGFloat) {
        guard !contains(w) else { return }
        guard root != nil else { root = Node(window: w); return }
        let host = target.flatMap(leaf) ?? leaves().last!
        let r = rects(area, gap)[ObjectIdentifier(host)] ?? area
        let a = Node(window: host.window), b = Node(window: w)
        a.parent = host; b.parent = host
        host.window = nil; host.first = a; host.second = b
        host.split = r.width >= r.height ? .columns : .rows
        host.ratio = 0.5
    }

    /// Remove a window; its sibling takes the freed space.
    public func remove(_ w: WindowID) {
        guard let l = leaf(w) else { return }
        guard let p = l.parent else { root = nil; return }
        let keep = (p.first === l ? p.second : p.first)!
        p.window = keep.window; p.first = keep.first; p.second = keep.second
        p.split = keep.split; p.ratio = keep.ratio
        p.first?.parent = p; p.second?.parent = p
    }

    public func swap(_ a: WindowID, _ b: WindowID) {
        guard let la = leaf(a), let lb = leaf(b) else { return }
        la.window = b; lb.window = a
    }

    /// Flip the split that holds a window between columns and rows.
    public func toggleSplit(_ w: WindowID) {
        guard let p = leaf(w)?.parent else { return }
        p.split = p.split == .columns ? .rows : .columns
    }

    public func balance() {
        func walk(_ n: Node?) { guard let n else { return }; n.ratio = 0.5; walk(n.first); walk(n.second) }
        walk(root)
    }

    /// Move one border of a window by `delta` points (positive = right or down). The border is
    /// the window's right or bottom one; when that one is the screen edge, its left or top one.
    /// Returns false when the window has no such border or the split is at its limit.
    @discardableResult
    public func adjust(_ w: WindowID, horizontal: Bool, delta: CGFloat, in area: CGRect, gap: CGFloat) -> Bool {
        guard var child = leaf(w) else { return false }
        let want: Split = horizontal ? .columns : .rows
        var near: Node?, far: Node?
        while let p = child.parent {
            if p.split == want {
                if p.first === child { near = p; break }
                if far == nil { far = p }
            }
            child = p
        }
        guard let n = near ?? far, let r = rects(area, gap)[ObjectIdentifier(n)] else { return false }
        let extent = (horizontal ? r.width : r.height) - gap
        guard extent > 0 else { return false }
        let ratio = min(max(n.ratio + delta / extent, 0.1), 0.9)
        guard abs(ratio - n.ratio) > 0.0001 else { return false }
        n.ratio = ratio
        return true
    }
}

// MARK: - Grid: preset arrangements

/// A preset decides where windows go from their count alone. Every preset is a row of
/// weighted columns, each a stack of equal rows.
public enum Preset: String, Codable, CaseIterable {
    case swiss     // 12-column Swiss grid: full, halves, then side | middle | side as 3 | 6 | 3
    case columns   // equal columns: compare documents side by side
    case main      // one large window and a stack beside it: focus work
    case board     // even rows and columns: overview of many windows

    public var next: Preset { Preset.allCases[(Preset.allCases.firstIndex(of: self)! + 1) % Preset.allCases.count] }
    public var label: String { rawValue.uppercased() }

    /// Columns for `n` windows, left to right: relative width and number of stacked windows.
    /// Windows fill the columns in order, top to bottom.
    public func columns(_ n: Int) -> [(weight: Int, rows: Int)] {
        guard n > 0 else { return [] }
        switch self {
        case .swiss:
            if n == 1 { return [(12, 1)] }
            if n == 2 { return [(6, 1), (6, 1)] }
            // Shared out evenly: one extra window goes to the middle, two extra to the sides.
            let b = n / 3, r = n % 3
            return [(3, b + (r == 2 ? 1 : 0)), (6, b + (r == 1 ? 1 : 0)), (3, b + (r == 2 ? 1 : 0))]
        case .columns:
            return Array(repeating: (1, 1), count: n)
        case .main:
            return n == 1 ? [(1, 1)] : [(2, 1), (1, n - 1)]
        case .board:
            let cols = Int(Double(n).squareRoot().rounded(.up))
            return (0..<cols).map { (1, n / cols + ($0 < n % cols ? 1 : 0)) }
        }
    }
}

extension Tree {
    /// A tree that places `windows` by a preset. It is an ordinary tree, so a soft grid can
    /// move its borders with `adjust`; a hard grid just never calls it.
    public convenience init(_ preset: Preset, windows: [WindowID], in area: CGRect, gap: CGFloat) {
        self.init()
        /// Chain `items` along one axis. `extent` is a grid of unit columns with gutters
        /// between them; an item of weight w spans w columns and the gutters inside its span.
        func chain(_ items: [(weight: Int, node: Node)], _ split: Split, _ extent: CGFloat) -> Node {
            guard items.count > 1 else { return items[0].node }
            let total = CGFloat(items.reduce(0) { $0 + $1.weight })
            let first = ((extent + gap) * CGFloat(items[0].weight) / total - gap).rounded()
            let n = Node()
            n.split = split
            n.ratio = extent > gap ? first / (extent - gap) : 0.5
            n.first = items[0].node
            n.second = chain(Array(items.dropFirst()), split, extent - first - gap)
            n.first?.parent = n; n.second?.parent = n
            return n
        }
        var rest = windows[...]
        let cols = preset.columns(windows.count).map { c -> (weight: Int, node: Node) in
            let leaves = rest.prefix(c.rows).map { (weight: 1, node: Node(window: $0)) }
            rest = rest.dropFirst(c.rows)
            return (c.weight, chain(leaves, .rows, area.height))
        }
        if !cols.isEmpty { root = chain(cols, .columns, area.width) }
    }
}

/// Frames that put free windows into a preset's grid, which fills `area`.
/// Each window takes the cell nearest to where it is: columns fill left to right, and the
/// windows of a column go top to bottom.
public func tidy(_ windows: [(id: WindowID, frame: CGRect)], _ preset: Preset = .swiss, in area: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
    var rest = windows.sorted { $0.frame.midX < $1.frame.midX }[...]
    var order: [WindowID] = []
    for c in preset.columns(windows.count) {
        order += rest.prefix(c.rows).sorted { $0.frame.midY < $1.frame.midY }.map(\.id)
        rest = rest.dropFirst(c.rows)
    }
    return Tree(preset, windows: order, in: area, gap: gap).frames(in: area, gap: gap)
}

// MARK: - Snap: fixed positions for one window

public enum Snap: String, CaseIterable {
    case leftHalf = "left-half", rightHalf = "right-half", topHalf = "top-half", bottomHalf = "bottom-half"
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"
    case leftThird = "left-third", centerThird = "center-third", rightThird = "right-third"
    case leftTwoThirds = "left-two-thirds", rightTwoThirds = "right-two-thirds"
    case center, full

    public var title: String {
        switch self {
        case .leftHalf: "Left half"; case .rightHalf: "Right half"
        case .topHalf: "Top half"; case .bottomHalf: "Bottom half"
        case .topLeft: "Top left"; case .topRight: "Top right"
        case .bottomLeft: "Bottom left"; case .bottomRight: "Bottom right"
        case .leftThird: "Left third"; case .centerThird: "Centre third"; case .rightThird: "Right third"
        case .leftTwoThirds: "Left two thirds"; case .rightTwoThirds: "Right two thirds"
        case .center: "Centre"; case .full: "Full"
        }
    }

    /// Cells `from..<to` of `of` equal cells along one axis, with gutters between cells.
    private static func span(_ origin: CGFloat, _ length: CGFloat, _ g: CGFloat, _ from: Int, _ to: Int, _ of: Int) -> (CGFloat, CGFloat) {
        let a = (origin + CGFloat(from) * (length + g) / CGFloat(of)).rounded()
        let b = (origin + CGFloat(to) * (length + g) / CGFloat(of) - g).rounded()
        return (a, b - a)
    }

    /// The frame for this position. `size` is the window's current size, kept by `center`.
    public func frame(in a: CGRect, gap g: CGFloat, size: CGSize) -> CGRect {
        func cells(_ x: (Int, Int, Int), _ y: (Int, Int, Int)) -> CGRect {
            let h = Snap.span(a.minX, a.width, g, x.0, x.1, x.2), v = Snap.span(a.minY, a.height, g, y.0, y.1, y.2)
            return CGRect(x: h.0, y: v.0, width: h.1, height: v.1)
        }
        let all = (0, 1, 1)
        switch self {
        case .leftHalf: return cells((0, 1, 2), all)
        case .rightHalf: return cells((1, 2, 2), all)
        case .topHalf: return cells(all, (0, 1, 2))
        case .bottomHalf: return cells(all, (1, 2, 2))
        case .topLeft: return cells((0, 1, 2), (0, 1, 2))
        case .topRight: return cells((1, 2, 2), (0, 1, 2))
        case .bottomLeft: return cells((0, 1, 2), (1, 2, 2))
        case .bottomRight: return cells((1, 2, 2), (1, 2, 2))
        case .leftThird: return cells((0, 1, 3), all)
        case .centerThird: return cells((1, 2, 3), all)
        case .rightThird: return cells((2, 3, 3), all)
        case .leftTwoThirds: return cells((0, 2, 3), all)
        case .rightTwoThirds: return cells((1, 3, 3), all)
        case .full: return a
        case .center:
            let w = min(size.width, a.width), h = min(size.height, a.height)
            return CGRect(x: (a.midX - w / 2).rounded(), y: (a.midY - h / 2).rounded(), width: w, height: h)
        }
    }
}

// MARK: - Neighbours

/// The window nearest to `me` in a direction, by centre point. Distance across the direction
/// counts double, so a window straight ahead wins over a closer one off to the side.
public func neighbor(of me: CGRect, _ dir: Direction, among others: [(id: WindowID, frame: CGRect)]) -> WindowID? {
    var best: (WindowID, CGFloat)?
    for o in others {
        let dx = o.frame.midX - me.midX, dy = o.frame.midY - me.midY
        let ahead: Bool
        switch dir {
        case .right: ahead = dx > 0
        case .left: ahead = dx < 0
        case .down: ahead = dy > 0
        case .up: ahead = dy < 0
        }
        guard ahead else { continue }
        let score = dir.isHorizontal ? abs(dx) + 2 * abs(dy) : abs(dy) + 2 * abs(dx)
        if best == nil || score < best!.1 { best = (o.id, score) }
    }
    return best?.0
}
