// swift-tools-version:5.9
import PackageDescription
import Foundation

// libsodium is a system dependency (SECURITY.md §3: libsodium exclusively).
// Resolve the Homebrew prefix for both Apple-Silicon (/opt/homebrew) and Intel
// (/usr/local) so `swift test` works locally and on either macOS CI runner,
// without requiring pkg-config to be installed.
func sodiumPrefix() -> String {
    let candidates = [
        "/opt/homebrew/opt/libsodium",
        "/usr/local/opt/libsodium",
        "/opt/homebrew",
        "/usr/local",
        "/usr",
    ]
    let fm = FileManager.default
    for c in candidates where fm.fileExists(atPath: c + "/include/sodium.h") {
        return c
    }
    return "/usr/local"
}

let prefix = sodiumPrefix()
let includeFlags: [String] = ["-Xcc", "-I\(prefix)/include"]
let linkFlags: [String] = ["-L\(prefix)/lib"]

let package = Package(
    name: "CryptoCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CryptoCore", targets: ["CryptoCore"]),
    ],
    targets: [
        // Thin system-library shim over libsodium.
        .systemLibrary(name: "Csodium", path: "Sources/Csodium"),

        // The isolated, audited crypto core (SECURITY.md §1.5 — frozen in the
        // signed binary; this is what gets audited).
        .target(
            name: "CryptoCore",
            dependencies: ["Csodium"],
            swiftSettings: [.unsafeFlags(includeFlags)]
        ),

        // Blocking crypto suite (TESTING.md §1).
        // Implemented as an executable runner (not XCTest) so it runs on a
        // Command-Line-Tools-only toolchain as well as full Xcode / CI runners.
        // `swift run CryptoCoreTests` exits non-zero on any failure.
        .executableTarget(
            name: "CryptoCoreTests",
            dependencies: ["CryptoCore"],
            swiftSettings: [.unsafeFlags(includeFlags)],
            linkerSettings: [.unsafeFlags(linkFlags)]
        ),
    ]
)
