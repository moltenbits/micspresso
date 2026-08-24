// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Micspresso",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MicspressoCore", targets: ["MicspressoCore"]),
        .executable(name: "micspresso", targets: ["micspresso"]),
    ],
    targets: [
        .target(
            name: "MicspressoCore"
        ),
        .executableTarget(
            name: "micspresso",
            dependencies: ["MicspressoCore"]
        ),
        .testTarget(
            name: "MicspressoCoreTests",
            dependencies: ["MicspressoCore"]
        ),
        .testTarget(
            name: "MicspressoAppTests",
            dependencies: ["micspresso"]
        ),
    ]
)
