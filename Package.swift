// swift-tools-version:5.9
import PackageDescription

// Aeris Tiler: one native app in place of yabai + skhd + Hammerspoon + jq + JankyBorders.
//   TilerCore  pure layout maths and config (unit-tested, no macOS window APIs)
//   CPrivate   declarations for the private window-server calls (all work with SIP on)
//   AerisTiler the app: Accessibility window control, hotkeys, mouse, border, GUI, CLI
let package = Package(
    name: "AerisTiler",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CPrivate"),
        .target(name: "TilerCore"),
        .executableTarget(
            name: "AerisTiler",
            dependencies: ["CPrivate", "TilerCore"],
            linkerSettings: [.unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"])]
        ),
        .testTarget(name: "TilerCoreTests", dependencies: ["TilerCore"]),
    ]
)
