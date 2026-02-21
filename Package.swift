// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PuasaMenuBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "PuasaMenuBar", targets: ["PuasaMenuBar"]),
    ],
    targets: [
        .executableTarget(
            name: "PuasaMenuBar"
        ),
    ]
)
