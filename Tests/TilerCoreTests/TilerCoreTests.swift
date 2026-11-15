import XCTest
@testable import TilerCore

final class TilerCoreTests: XCTestCase {
    let area = CGRect(x: 8, y: 8, width: 1904, height: 1064)

    /// Frames must stay inside the area, not overlap, and leave exactly the gutters uncovered.
    func assertTiles(_ frames: [CGRect], gap: CGFloat = 8, file: StaticString = #filePath, line: UInt = #line) {
        for (i, a) in frames.enumerated() {
            XCTAssertTrue(area.contains(a), "frame \(i) leaves the area", file: file, line: line)
            for b in frames[(i + 1)...] {
                XCTAssertTrue(a.insetBy(dx: -gap / 2 + 0.5, dy: -gap / 2 + 0.5).intersection(b).isEmpty, "\(a) too close to \(b)", file: file, line: line)
            }
        }
    }

    func testTreeSplitsTheLongerSideAndTiles() {
        let t = Tree()
        for w in 1...5 as ClosedRange<WindowID> { t.insert(w, in: area, gap: 8) }
        let f = t.frames(in: area, gap: 8)
        XCTAssertEqual(f.count, 5)
        XCTAssertEqual(f[1], CGRect(x: 8, y: 8, width: 948, height: 1064))  // first split: columns
        XCTAssertEqual(f[2]!.minX, 964)                                    // second half, split into rows
        XCTAssertEqual(f[2]!.height, 528)
        assertTiles(Array(f.values))
        XCTAssertEqual(t.windows, [1, 2, 3, 4, 5])
    }

    func testInsertBesideAndRemove() {
        let t = Tree()
        t.insert(1, in: area, gap: 8); t.insert(2, in: area, gap: 8)
        t.insert(3, beside: 1, in: area, gap: 8)   // 1 is tall: rows
        var f = t.frames(in: area, gap: 8)
        XCTAssertEqual(f[3]!.minX, f[1]!.minX)
        XCTAssertGreaterThan(f[3]!.minY, f[1]!.minY)
        t.remove(1)
        f = t.frames(in: area, gap: 8)
        XCTAssertEqual(f[3], CGRect(x: 8, y: 8, width: 948, height: 1064))
        t.remove(3); t.remove(2)
        XCTAssertTrue(t.windows.isEmpty)
        t.remove(9)   // unknown: no crash
    }

    func testSwapToggleBalance() {
        let t = Tree()
        t.insert(1, in: area, gap: 8); t.insert(2, in: area, gap: 8)
        let before = t.frames(in: area, gap: 8)
        t.swap(1, 2)
        XCTAssertEqual(t.frames(in: area, gap: 8)[1], before[2])
        t.toggleSplit(1)
        XCTAssertEqual(t.frames(in: area, gap: 8)[2]!.width, 1904)
        t.adjust(1, horizontal: false, delta: 100, in: area, gap: 8)
        t.balance()
        XCTAssertEqual(t.frames(in: area, gap: 8)[2]!.height, 528)
    }

    func testAdjustMovesTheRightBorderOrTheLeftOneAtTheScreenEdge() {
        let t = Tree()
        t.insert(1, in: area, gap: 8); t.insert(2, in: area, gap: 8)
        XCTAssertTrue(t.adjust(1, horizontal: true, delta: 60, in: area, gap: 8))
        var f = t.frames(in: area, gap: 8)
        XCTAssertEqual(f[1]!.width, 1008)
        XCTAssertEqual(f[2]!.minX, 1024)
        // Window 2 touches the right screen edge: the same key moves its left border.
        XCTAssertTrue(t.adjust(2, horizontal: true, delta: 60, in: area, gap: 8))
        f = t.frames(in: area, gap: 8)
        XCTAssertEqual(f[2]!.minX, 1084)
        XCTAssertFalse(t.adjust(1, horizontal: false, delta: 60, in: area, gap: 8))  // no rows split
        for _ in 0..<50 { t.adjust(1, horizontal: true, delta: 60, in: area, gap: 8) }
        XCTAssertFalse(t.adjust(1, horizontal: true, delta: 60, in: area, gap: 8))   // limit reached
        assertTiles(Array(t.frames(in: area, gap: 8).values))
    }

    func grid(_ p: Preset, _ n: Int) -> [CGRect] {
        let ids = (0..<n).map { WindowID($0 + 1) }
        let f = Tree(p, windows: ids, in: area, gap: 8).frames(in: area, gap: 8)
        return ids.map { f[$0]! }
    }

    func testSwissGrid() {
        XCTAssertEqual(grid(.swiss, 0), [])
        XCTAssertEqual(grid(.swiss, 1), [area])
        XCTAssertEqual(grid(.swiss, 2).map(\.width), [948, 948])
        // 3 | 6 | 3 of 12 columns with 8 pt gutters.
        XCTAssertEqual(grid(.swiss, 3).map(\.width), [470, 948, 470])
        XCTAssertEqual(grid(.swiss, 3).map(\.minX), [8, 486, 1442])
        XCTAssertEqual(Preset.swiss.columns(4).map(\.rows), [1, 2, 1])
        XCTAssertEqual(Preset.swiss.columns(5).map(\.rows), [2, 1, 2])
        XCTAssertEqual(Preset.swiss.columns(7).map(\.rows), [2, 3, 2])
        // Stacked windows share the height equally, to the pixel.
        let heights = grid(.swiss, 7).filter { $0.width == 948 }.map(\.height)
        XCTAssertEqual(heights, [349, 350, 349])
    }

    func testOtherPresets() {
        XCTAssertEqual(grid(.columns, 4).map(\.width), [470, 470, 470, 470])
        XCTAssertEqual(grid(.main, 1), [area])
        let main = grid(.main, 4)
        XCTAssertEqual(main[0].height, 1064)
        XCTAssertEqual(main[0].width, 1267)   // two of three columns, same as Snap.leftTwoThirds
        XCTAssertEqual(Set(main[1...].map(\.minX)), [1283])
        XCTAssertEqual(Preset.board.columns(4).map(\.rows), [2, 2])
        XCTAssertEqual(Preset.board.columns(7).map(\.rows), [3, 2, 2])
        for p in Preset.allCases {
            for n in 1...9 {
                XCTAssertEqual(p.columns(n).reduce(0) { $0 + $1.rows }, n)
                assertTiles(grid(p, n))
            }
        }
    }

    func testSoftGridMovesBorders() {
        let ids: [WindowID] = [1, 2, 3]
        let t = Tree(.swiss, windows: ids, in: area, gap: 8)
        XCTAssertTrue(t.adjust(2, horizontal: true, delta: 40, in: area, gap: 8))
        let f = t.frames(in: area, gap: 8)
        XCTAssertEqual(f[2]!.width, 988)
        XCTAssertEqual(f[3]!.width, 430)
        assertTiles(Array(f.values))
    }

    func testTidyFillsTheAreaAndKeepsWindowsNearTheirPlace() {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: 300, height: 200) }
        // Scattered windows: 1 bottom right, 2 top left, 3 top right, 4 bottom left.
        let f = tidy([(1, at(900, 600)), (2, at(40, 30)), (3, at(1000, 10)), (4, at(100, 500))], .board, in: area, gap: 8)
        assertTiles(Array(f.values))
        XCTAssertEqual(f[2]!.origin, area.origin)
        XCTAssertTrue(f[4]!.minX == f[2]!.minX && f[4]!.minY > f[2]!.minY)
        XCTAssertTrue(f[3]!.minX > f[2]!.minX && f[3]!.minY == f[2]!.minY)
        XCTAssertTrue(f[1]!.minX == f[3]!.minX && f[1]!.minY > f[3]!.minY)
        // Swiss is the default: side | middle | side, left to right by position.
        let s = tidy([(1, at(900, 600)), (2, at(40, 30)), (4, at(400, 500))], in: area, gap: 8)
        assertTiles(Array(s.values))
        XCTAssertTrue(s[2]!.minX < s[4]!.minX && s[4]!.minX < s[1]!.minX && s[4]!.width > s[2]!.width)
    }

    func testSnap() {
        let size = CGSize(width: 800, height: 600)
        XCTAssertEqual(Snap.leftHalf.frame(in: area, gap: 8, size: size), CGRect(x: 8, y: 8, width: 948, height: 1064))
        XCTAssertEqual(Snap.bottomRight.frame(in: area, gap: 8, size: size), CGRect(x: 964, y: 544, width: 948, height: 528))
        XCTAssertEqual(Snap.full.frame(in: area, gap: 8, size: size), area)
        XCTAssertEqual(Snap.center.frame(in: area, gap: 8, size: size), CGRect(x: 560, y: 240, width: 800, height: 600))
        assertTiles([Snap.leftThird, .centerThird, .rightThird].map { $0.frame(in: area, gap: 8, size: size) })
        assertTiles([Snap.leftTwoThirds, .rightThird].map { $0.frame(in: area, gap: 8, size: size) })
        assertTiles([Snap.topLeft, .topRight, .bottomLeft, .bottomRight].map { $0.frame(in: area, gap: 8, size: size) })
    }

    func testNeighbor() {
        let me = CGRect(x: 0, y: 0, width: 100, height: 100)
        let others: [(id: WindowID, frame: CGRect)] = [
            (2, CGRect(x: 110, y: 0, width: 100, height: 100)),     // right, level
            (3, CGRect(x: 105, y: 300, width: 100, height: 100)),   // right, far below
            (4, CGRect(x: 0, y: 110, width: 100, height: 100)),     // below
        ]
        XCTAssertEqual(neighbor(of: me, .right, among: others), 2)
        XCTAssertEqual(neighbor(of: me, .down, among: others), 4)
        XCTAssertNil(neighbor(of: me, .left, among: others))
        XCTAssertNil(neighbor(of: me, .up, among: others))
    }

    func testKeyCombo() {
        let k = KeyCombo("cmd+ctrl+alt-left")!
        XCTAssertEqual(k.spec, "ctrl+alt+cmd-left")
        XCTAssertEqual(k.symbols, "⌃⌥⌘←")
        XCTAssertEqual(k.spelled, "Ctrl + Option + Cmd + Left")
        XCTAssertEqual(KeyCombo("ctrl+alt--")!.key, "-")
        XCTAssertNil(KeyCombo("k"))
        XCTAssertNil(KeyCombo("hyper-k"))
        XCTAssertNil(KeyCombo("cmd-nokey"))
    }

    func testDefaultBindingsAreValidAndUnique() {
        let specs = Action.all.compactMap(\.keys)
        XCTAssertEqual(Set(specs).count, specs.count, "two actions share a default key")
        for s in specs { XCTAssertNotNil(KeyCombo(s), s) }
        XCTAssertEqual(Set(Action.all.map(\.id)).count, Action.all.count)
    }

    func testConfigKeepsDefaultsForMissingKeys() throws {
        let c = try Config.decode(Data(#"{"gap": 12, "bindings": {"keysheet": "ctrl+alt-k", "pause": ""}}"#.utf8))
        XCTAssertEqual(c.gap, 12)
        XCTAssertEqual(c.padding, 8)
        XCTAssertEqual(c.bindings["keysheet"], "ctrl+alt-k")
        XCTAssertNil(c.combo("pause"))
        XCTAssertEqual(c.bindings["focus-left"], "ctrl+alt-left")
        XCTAssertEqual(try Config.decode(JSONEncoder().encode(c)), c)
    }

    func testTranslations() {
        defer { Strings.language = .en }
        // Every row has one text per language besides English, none empty.
        for k in translationKeys {
            XCTAssertEqual(translationRow(k)!.count, Lang.allCases.count - 1, k)
            XCTAssertFalse(translationRow(k)!.contains(""), k)
        }
        // Every action title, group and snap position has a translation.
        Strings.language = .de
        for a in Action.all where a.group != "App" && a.group != "Snap" { XCTAssertNotEqual(L(a.title), a.title, a.title) }
        for s in Snap.allCases { XCTAssertNotNil(translationRow(s.title), s.title) }
        XCTAssertEqual(L("Snap: left half"), "Einrasten: Linke Hälfte")
        XCTAssertEqual(L("Move window to space 3"), "Fenster auf Space 3 bewegen")
        XCTAssertEqual(KeyCombo("ctrl+alt-left")!.spelled, "Ctrl + Wahl + Links")
        Strings.language = .es
        XCTAssertEqual(L("Gap"), "Separación")
        XCTAssertEqual(L("not in the table"), "not in the table")
        Strings.language = .en
        XCTAssertEqual(L("Gap"), "Gap")
        XCTAssertEqual(Lang.resolve("fr"), .fr)
    }
}
