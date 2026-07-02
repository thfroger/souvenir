import CryptoCore

// Blocking crypto suite (TESTING.md §1). The local crypto round-trip is the
// automated mirror of the production re-decryption self-check (SECURITY.md §1.6).

let h = Harness()

// ───────────────────────────── AEAD ─────────────────────────────
h.section("AEAD — round-trip & properties")

h.test("round-trip returns identical bytes") {
    let key = try SymmetricKey.generate()
    let message = Array("la voix de Léa — premiers mots".utf8)
    let sealed = try AEAD.seal(message, key: key.bytes)
    try expectEqual(try AEAD.open(sealed, key: key.bytes), message)
}

h.test("empty plaintext round-trips") {
    let key = try SymmetricKey.generate()
    let sealed = try AEAD.seal([], key: key.bytes)
    try expectEqual(try AEAD.open(sealed, key: key.bytes), [])
}

h.test("wrong key fails cleanly") {
    let key = try SymmetricKey.generate()
    let other = try SymmetricKey.generate()
    let sealed = try AEAD.seal(Array("souvenir".utf8), key: key.bytes)
    try expectThrowsError({ _ = try AEAD.open(sealed, key: other.bytes) }) {
        ($0 as? CryptoError) == .decryptionFailed
    }
}

h.test("tampered ciphertext fails cleanly") {
    let key = try SymmetricKey.generate()
    let original = try AEAD.seal(Array("souvenir".utf8), key: key.bytes)
    var c = original.ciphertext
    c[0] ^= 0x01
    let tampered = AEAD.Sealed(nonce: original.nonce, ciphertext: c)
    try expectThrows { _ = try AEAD.open(tampered, key: key.bytes) }
}

h.test("nonces are unique per seal") {
    let key = try SymmetricKey.generate()
    let a = try AEAD.seal([1, 2, 3], key: key.bytes)
    let b = try AEAD.seal([1, 2, 3], key: key.bytes)
    try expectNotEqual(a.nonce, b.nonce)
    try expectNotEqual(a.ciphertext, b.ciphertext)
}

// ─────────────────────── Key wrapping (§3) ───────────────────────
h.section("Key wrapping — DEK<VK<MIK<RK")

h.test("full hierarchy round-trip") {
    let dek = try DataKey.generate()
    let vk = try VaultKey.generate()
    let mik = try MasterIdentityKey.generate()
    let rk = try RecoveryKey.generate()

    let dekUnderVK = try KeyWrap.wrap(dek, under: vk)
    let vkUnderMIK = try KeyWrap.wrap(vk, under: mik)
    let mikUnderRK = try KeyWrap.wrap(mik, under: rk)

    let mik2 = try KeyWrap.unwrap(mikUnderRK, with: rk)
    let vk2 = try KeyWrap.unwrap(vkUnderMIK, with: mik2)
    let dek2 = try KeyWrap.unwrap(dekUnderVK, with: vk2)

    try expectEqual(mik2, mik)
    try expectEqual(dek2, dek)
}

h.test("unwrap with wrong key fails cleanly") {
    let dek = try DataKey.generate()
    let vk = try VaultKey.generate()
    let wrong = try VaultKey.generate()
    let wrapped = try KeyWrap.wrap(dek, under: vk)
    try expectThrowsError({ _ = try KeyWrap.unwrap(wrapped, with: wrong) }) {
        ($0 as? CryptoError) == .decryptionFailed
    }
}

h.test("rejects wrong-length key") {
    try expectThrowsError({ _ = try SymmetricKey(bytes: [1, 2, 3]) }) {
        ($0 as? CryptoError) == .invalidLength
    }
}

// ─────────────────────── Argon2id KDF (§3) ───────────────────────
h.section("KDF — Argon2id")

h.test("deterministic for same inputs") {
    let salt = [UInt8](repeating: 0x42, count: KDF.saltBytes)
    let pw = Array("correct horse battery staple".utf8)
    let a = try KDF.deriveKey(password: pw, salt: salt)
    let b = try KDF.deriveKey(password: pw, salt: salt)
    try expectEqual(a, b)
    try expectEqual(a.count, 32)
}

h.test("different salt gives different key") {
    let pw = Array("correct horse battery staple".utf8)
    let a = try KDF.deriveKey(password: pw, salt: [UInt8](repeating: 0x01, count: KDF.saltBytes))
    let b = try KDF.deriveKey(password: pw, salt: [UInt8](repeating: 0x02, count: KDF.saltBytes))
    try expectNotEqual(a, b)
}

h.test("derived key can wrap the MIK") {
    let salt = try KDF.generateSalt()
    let derived = try SymmetricKey(bytes: try KDF.deriveKey(password: Array("pw".utf8), salt: salt))
    let mik = try MasterIdentityKey.generate()
    let wrapped = try KeyWrap.wrap(mik, under: derived)
    try expectEqual(try KeyWrap.unwrap(wrapped, with: derived), mik)
}

// Device-to-device enrollment flow (SECURITY.md §3): the device that holds the
// VK publishes {salt, MIK-under-KEK, VK-under-MIK}; another device of the same
// user recovers the SAME VK from the passphrase alone — no memory re-encrypted.
h.test("passphrase enrollment recovers the same VK on another device") {
    let phrase = Array("un été à la mer".utf8)
    let vk = try VaultKey.generate()

    // Origin device: wrap VK under a fresh MIK, MIK under the passphrase-derived KEK.
    let salt = try KDF.generateSalt()
    let kek = try SymmetricKey(bytes: try KDF.deriveKey(password: phrase, salt: salt))
    let mik = try MasterIdentityKey.generate()
    let wrappedMIK = try KeyWrap.wrap(mik, under: kek)
    let wrappedVK = try KeyWrap.wrap(vk, under: mik)

    // Second device: only the passphrase + the published (salt, wrappedMIK, wrappedVK).
    let kek2 = try SymmetricKey(bytes: try KDF.deriveKey(password: phrase, salt: salt))
    let mik2 = try KeyWrap.unwrap(wrappedMIK, with: kek2)
    let vk2 = try KeyWrap.unwrap(wrappedVK, with: mik2)
    try expectEqual(vk2, vk)
}

h.test("a wrong passphrase fails the MIK unwrap, never yields a key") {
    let salt = try KDF.generateSalt()
    let kek = try SymmetricKey(bytes: try KDF.deriveKey(password: Array("le bon mot".utf8), salt: salt))
    let mik = try MasterIdentityKey.generate()
    let wrappedMIK = try KeyWrap.wrap(mik, under: kek)

    let wrongKEK = try SymmetricKey(bytes: try KDF.deriveKey(password: Array("le mauvais mot".utf8), salt: salt))
    try expectThrowsError({ _ = try KeyWrap.unwrap(wrappedMIK, with: wrongKEK) }) {
        ($0 as? CryptoError) == .decryptionFailed
    }
}

// ─────────────────────── Shamir (§5) ─────────────────────────────
h.section("Shamir 2-of-3 over the Recovery Key")

h.test("every 2-of-3 subset reconstructs the secret") {
    let rk = try RecoveryKey.generate().bytes
    let shares = try Shamir.split(secret: rk) // default 2-of-3
    try expect(shares.count == 3, "expected 3 shares")
    try expectEqual(try Shamir.combine([shares[0], shares[1]]), rk)
    try expectEqual(try Shamir.combine([shares[0], shares[2]]), rk)
    try expectEqual(try Shamir.combine([shares[1], shares[2]]), rk)
    try expectEqual(try Shamir.combine(shares), rk) // all three too
}

h.test("a single share is rejected (reveals nothing)") {
    let shares = try Shamir.split(secret: try RecoveryKey.generate().bytes)
    try expectThrowsError({ _ = try Shamir.combine([shares[0]]) }) {
        ($0 as? CryptoError) == .invalidShares
    }
}

h.test("a corrupted share is detected") {
    let rk = try RecoveryKey.generate().bytes
    var shares = try Shamir.split(secret: rk)
    var bad = shares[1].data
    bad[0] ^= 0x01
    shares[1] = Shamir.Share(index: shares[1].index, data: bad)
    try expectThrowsError({ _ = try Shamir.combine([shares[0], shares[1]]) }) {
        ($0 as? CryptoError) == .shareIntegrityFailed
    }
}

h.test("duplicate index is rejected") {
    let shares = try Shamir.split(secret: try RecoveryKey.generate().bytes)
    try expectThrowsError({ _ = try Shamir.combine([shares[0], shares[0]]) }) {
        ($0 as? CryptoError) == .invalidShares
    }
}

h.test("RK rotation invalidates old shares") {
    let rk1 = try RecoveryKey.generate().bytes
    let rk2 = try RecoveryKey.generate().bytes
    let s1 = try Shamir.split(secret: rk1)
    let s2 = try Shamir.split(secret: rk2)
    try expectEqual(try Shamir.combine([s2[0], s2[1]]), rk2)    // new shares -> new RK
    try expectNotEqual(try Shamir.combine([s1[0], s1[1]]), rk2) // old shares never yield new RK
    try expectThrows { _ = try Shamir.combine([s1[0], s2[1]]) } // mixing generations is detected
}

h.test("full recovery flow: shares -> RK -> unwrap MIK (§5)") {
    let rk = try RecoveryKey.generate()
    let mik = try MasterIdentityKey.generate()
    let mikUnderRK = try KeyWrap.wrap(mik, under: rk) // the opaque blob the server stores
    let shares = try Shamir.split(secret: rk.bytes)
    let rkRecovered = try SymmetricKey(bytes: try Shamir.combine([shares[0], shares[2]]))
    try expectEqual(try KeyWrap.unwrap(mikUnderRK, with: rkRecovered), mik)
}

// The social door all the way to the VK (mirrors MemoryStore.setupSocialRecovery /
// recoverWithShares): the server stores only {MIK-under-RK, VK-under-MIK}; two of
// three guardian shares rebuild the RK and reach the SAME vault key.
h.test("social recovery recovers the vault key from any 2 of 3 shares") {
    let vk = try VaultKey.generate()
    let mik = try MasterIdentityKey.generate()
    let rk = try RecoveryKey.generate()
    let mikUnderRK = try KeyWrap.wrap(mik, under: rk)
    let vkUnderMIK = try KeyWrap.wrap(vk, under: mik)
    let shares = try Shamir.split(secret: rk.bytes)

    for pair in [[shares[0], shares[1]], [shares[0], shares[2]], [shares[1], shares[2]]] {
        let rk2 = try SymmetricKey(bytes: try Shamir.combine(pair))
        let mik2 = try KeyWrap.unwrap(mikUnderRK, with: rk2)
        try expectEqual(try KeyWrap.unwrap(vkUnderMIK, with: mik2), vk)
    }
}

// ───────────────── Padding by tiers (§6.2) ─────────────────
h.section("Padding by tiers — size-fingerprint quantization (SECURITY §6.2)")

h.test("pad/unpad round-trips at every size class") {
    for n in [0, 1, 17, 1023, 1024, 1025, 5000, 300_000] {
        let payload = (0..<n).map { UInt8(truncatingIfNeeded: $0) }
        let padded = try Padding.pad(payload)
        try expectEqual(padded.count, Padding.tier(for: n))
        try expectEqual(try Padding.unpad(padded), payload)
    }
}

h.test("small content blobs share the common floor (indistinguishable)") {
    let note = try Padding.pad(Array("première dent !".utf8))
    let measure = try Padding.pad(Array("78 cm".utf8))
    let quote = try Padding.pad(Array(String(repeating: "a", count: 900).utf8))
    try expectEqual(note.count, Padding.floorBytes)
    try expectEqual(note.count, measure.count)
    try expectEqual(note.count, quote.count)
}

h.test("a payload exactly at a tier moves strictly up (7816-4 always pads)") {
    let t = Padding.tier(for: 0) // the floor
    let padded = try Padding.pad([UInt8](repeating: 7, count: t))
    try expectEqual(padded.count, Padding.tier(for: t))
    try expect(padded.count > t, "tier did not grow strictly")
}

h.test("corrupt padding fails cleanly, never guesses") {
    // An all-zeros tail has no 0x80 marker: unpad must refuse.
    try expectThrowsError({ _ = try Padding.unpad([UInt8](repeating: 0, count: Padding.floorBytes)) }) {
        ($0 as? CryptoError) == .invalidPadding
    }
    try expectThrowsError({ _ = try Padding.unpad([]) }) {
        ($0 as? CryptoError) == .invalidPadding
    }
}

h.test("overhead is bounded (≤ ratio) and scale is not power-of-two") {
    // Bound: for n ≥ floor, tier(n) < n · ratio · (1 + ε rounding).
    for n in stride(from: Padding.floorBytes, through: 2_000_000, by: 37_313) {
        let t = Padding.tier(for: n)
        try expect(Double(t) <= Double(n) * Padding.ratio + 2, "overhead > ratio at n=\(n): tier=\(t)")
    }
    // Not powers of two: at least one tier below 1 MiB is not a power of two.
    var t = Padding.floorBytes, sawNonPow2 = false
    while t < 1 << 20 {
        if t & (t - 1) != 0 { sawNonPow2 = true }
        t = Padding.tier(for: t)
    }
    try expect(sawNonPow2, "tier scale degenerated to powers of two")

    // Spike measurement (ARCHITECTURE §6 — reported, to be frozen by the owner):
    // average overhead over representative corpora.
    func avgOverhead(_ sizes: [Int]) -> Double {
        let os = sizes.map { Double(Padding.tier(for: $0) - $0) / Double($0) }
        return os.reduce(0, +) / Double(os.count)
    }
    let photos = stride(from: 150_000, through: 600_000, by: 9_973).map { $0 }   // stripped JPEGs (1600px q0.82)
    let voices = stride(from: 40_000, through: 400_000, by: 7_919).map { $0 }    // short voice notes
    print(String(format: "    [spike §6.2] floor=%dB ratio=%.2f — avg overhead photos %.1f%%, voice %.1f%%",
                 Padding.floorBytes, Padding.ratio, avgOverhead(photos) * 100, avgOverhead(voices) * 100))
}

h.finish()
