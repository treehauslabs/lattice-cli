// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LatticeCLI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "lattice", targets: ["LatticeCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(path: "../lattice"),
        .package(path: "../AcornMemoryWorker"),
    ],
    targets: [
        .executableTarget(
            name: "LatticeCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Lattice", package: "lattice"),
                .product(name: "AcornMemoryWorker", package: "AcornMemoryWorker"),
            ]),
    ]
)
