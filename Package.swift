// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Copak",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Copak",
            targets: ["ContextPacket"]
        ),
        .library(
            name: "ContextPacketCore",
            targets: ["ContextPacketCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ContextPacketCore",
            dependencies: []
        ),
        .executableTarget(
            name: "ContextPacket",
            dependencies: ["ContextPacketCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ContextPacketTests",
            dependencies: ["ContextPacketCore"]
        )
    ]
)
