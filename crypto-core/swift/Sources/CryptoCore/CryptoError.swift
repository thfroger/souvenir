public enum CryptoError: Error, Equatable {
    case initFailed
    case decryptionFailed
    case invalidLength
    case invalidShares          // malformed Shamir input (dup/zero index, bad lengths, too few)
    case shareIntegrityFailed   // reconstructed secret fails its integrity tag (corrupt or insufficient)
    case notImplemented(String)
}
