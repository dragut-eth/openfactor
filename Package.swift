// swift-tools-version: 6.0

import PackageDescription

// OpenFactorCore holds every security sensitive piece of the app: encoding, code
// generation, URI parsing, and secret storage. It contains no user interface code and
// has no third party dependencies, so it can be audited on its own.
//
// The dependency list below is empty and is meant to stay that way. See CONTRIBUTING.md.
let package = Package(
    name: "OpenFactorCore",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        // macOS is here only so the suite can run with `swift test` on a Mac and in CI.
        // The app itself does not ship for macOS.
        .macOS(.v15),
    ],
    products: [
        .library(name: "OpenFactorCore", targets: ["OpenFactorCore"]),
    ],
    targets: [
        .target(name: "OpenFactorCore"),
        .testTarget(
            name: "OpenFactorCoreTests",
            dependencies: ["OpenFactorCore"],
            // Read through #filePath rather than Bundle.module, because these sources are
            // also compiled into the app test target, where Bundle.module does not exist.
            exclude: ["Fixtures"]
        ),
    ]
)
