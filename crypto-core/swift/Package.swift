// swift-tools-version:5.9
import PackageDescription

// libsodium is the only crypto dependency (SECURITY.md §3). It is provided here
// by swift-sodium's `Clibsodium` — a vendored xcframework covering all Apple
// platforms (macOS + iOS device/simulator), so the same core builds for the CLI,
// CI, and the iOS app. Pinned exactly: the crypto core is frozen and audited
// (SECURITY.md §1.5), it must not float.
let package = Package(
    name: "CryptoCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "CryptoCore", targets: ["CryptoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.9.1"),
    ],
    targets: [
        // The isolated, audited crypto core (SECURITY.md §1.5).
        .target(
            name: "CryptoCore",
            dependencies: [.product(name: "Clibsodium", package: "swift-sodium")]
        ),
        // Blocking crypto suite (TESTING.md §1) as an executable runner (no XCTest),
        // so it runs on a Command-Line-Tools-only toolchain and on CI.
        // `swift run CryptoCoreTests` exits non-zero on any failure.
        .executableTarget(
            name: "CryptoCoreTests",
            dependencies: ["CryptoCore"]
        ),
    ]
)
