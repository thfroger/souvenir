# Shared crypto vectors

Known-answer vectors that **both** implementations (Swift, Kotlin) must satisfy,
to guarantee cross-platform interop for multi-device sync (V1).

Plan:
- The frozen Swift impl (`../swift`) is the reference; vectors are generated from
  it (fixed keys/nonces/salts → expected ciphertext / derived key / shares).
- The Kotlin impl replays the same vectors in its own test suite.
- Format: one JSON file per primitive (`aead.json`, `keywrap.json`, `argon2id.json`,
  `shamir.json`), each a list of `{ inputs…, expected }` cases.

Not generated yet — produced when the vector-export step and the Kotlin impl land.
