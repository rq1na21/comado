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
        .target(
            name: "comadoWidget",
            linkerSettings: [
                // xtool は入口を _NSExtensionMain にするため、@main 由来の _main がどこからも参照されず
                // ld64.lld の dead strip でウィジェットのコードごと消える。_NSExtensionMain は
                // __swift5_entry から @main を探すので、_main を生かしておけば起動できる
                // (https://github.com/xtool-org/xtool/issues/313)
                .unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"]),
            ]
        ),
    ]
)
