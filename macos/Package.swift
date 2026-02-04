// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Colony",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Colony", targets: ["Colony"]),
    ],
    targets: [
        .executableTarget(
            name: "Colony",
            dependencies: ["ColonyCore"],
            path: "Sources/Colony",
            linkerSettings: [
                .unsafeFlags([
                    "-L../zig-out/lib",
                    "-lcolony_core",
                    "-lsqlite3",
                ]),
            ]
        ),
        .systemLibrary(
            name: "ColonyCore",
            path: "Sources/ColonyCore",
            pkgConfig: nil,
            providers: nil
        ),
    ]
)
