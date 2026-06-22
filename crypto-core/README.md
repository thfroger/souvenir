# crypto-core

The isolated, open-source crypto core (`SECURITY.md §1.5`): frozen in the signed
binary, never shipped via OTA, and the part that gets audited.

Pure-native means **two implementations** that must produce byte-compatible
output (a blob encrypted on iOS must decrypt on the same user's Android device —
multi-device sync, V1):

- `swift/` — Swift Package (libsodium). Implemented + blocking crypto suite (`TESTING.md §1`).
- `kotlin/` — *(à venir)* Jetpack/Kotlin implementation.
- `vectors/` — shared known-answer vectors. The Swift impl is the reference;
  the Kotlin impl must replay them to guarantee interop.

Primitives (`SECURITY.md §3`): `XChaCha20-Poly1305` (AEAD), key wrapping
(DEK<VK<MIK, MIK<{password-derived, device-local, Recovery Key}), `Argon2id`
(KDF), and Shamir 2-of-3 over the Recovery Key (`§5`) — implemented, **pending
external audit** before freeze (`§8.4`).
