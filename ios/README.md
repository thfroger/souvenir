# iOS app (SwiftUI) — `[À CONCEVOIR]`

Placeholder. Not buildable from Command Line Tools alone — open in **Xcode**.

- Pure-native **SwiftUI** (`ARCHITECTURE.md §1`). Thin UI over the crypto core;
  all key handling goes through `crypto-core/swift` (`CryptoCore`).
- The crypto core stays **isolated** (`SECURITY.md §1.5`) — never shipped via OTA.
- Screens to build:
  - Joyful core (recreate hi-fi faithfully): Frise, Arbre, Immersif, Ajout —
    `DESIGN_INTEGRATION.md §11`.
  - Security-critical + Réglages hub — `DESIGN_INTEGRATION.md §9`.
- Never display a memory until its re-decryption self-check passes
  (`SECURITY.md §1.6`, `ARCHITECTURE.md §5`).
