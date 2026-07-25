// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "shitty-shortcuts",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CLua",
            cSettings: [
                .define("LUA_USE_MACOSX"),
            ]
        ),
        .executableTarget(
            name: "ShittyShortcuts",
            dependencies: ["CLua"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
            ]
        ),
    ]
)
