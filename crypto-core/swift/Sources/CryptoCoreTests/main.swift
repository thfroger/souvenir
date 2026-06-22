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

// ─────────────────────── Shamir (§5) — PENDING ───────────────────
h.section("Shamir 2-of-3 over the Recovery Key — PENDING (see Shamir.swift)")

h.test("every 2-of-3 subset reconstructs") { try skip("Shamir.split/combine not implemented") }
h.test("single share reveals nothing") { try skip("Shamir reconstruction with 1 share must fail") }
h.test("corrupted share is detected") { try skip("tampered share must be detected") }
h.test("RK rotation invalidates old shares") { try skip("new RK, zero re-encryption, old shares inert") }
h.test("stub throws notImplemented (stays honest)") {
    try expectThrowsError({ _ = try Shamir.split(secret: [1, 2, 3]) }) {
        if case .some(.notImplemented) = ($0 as? CryptoError) { return true }
        return false
    }
}

h.finish()
