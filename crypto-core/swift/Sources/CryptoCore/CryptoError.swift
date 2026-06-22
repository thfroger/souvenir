public enum CryptoError: Error, Equatable {
    case initFailed
    case decryptionFailed
    case invalidLength
    case notImplemented(String)
}
