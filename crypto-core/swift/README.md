# CryptoCore (Swift)

Swift Package implementing the crypto core over **libsodium**.

## Run the blocking crypto suite (TESTING.md §1)

```sh
brew install libsodium     # system dependency (SECURITY.md §3)
cd crypto-core/swift
swift run CryptoCoreTests   # exits non-zero on any failure
```

The suite is an **executable runner**, not XCTest, so it runs on a
Command-Line-Tools-only toolchain (no Xcode required) as well as on CI.
`Package.swift` auto-detects the Homebrew prefix (`/opt/homebrew` or `/usr/local`).

## Status

- ✅ AEAD (XChaCha20-Poly1305): round-trip, tamper/wrong-key rejection
- ✅ Key wrapping: DEK<VK<MIK<RK round-trip, clean failures
- ✅ Argon2id KDF (interactive params — **final params `[À VALIDER]`**, §3/§8.4)
- ✅ Shamir 2-of-3 over the Recovery Key: constant-time GF(256), non-zero leading
  coefficient, BLAKE2b integrity tag (corrupt/insufficient shares detected), full
  recovery flow (shares → RK → unwrap MIK). **Pending external audit** before
  freeze (SECURITY.md §8.4) — that review is what makes the claim verifiable.
