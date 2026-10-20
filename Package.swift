// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "comado",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "comado",
            targets: ["comado"]
        ),
        .library(
            name: "comadoWidget",
            targets: ["comadoWidget"]
        ),
    ],
    targets: [
        .target(
            name: "comado"
        ),
        .target(name: "comadoWidget"),
    ]
)
