# Android app (Jetpack Compose / Kotlin) — `[À CONCEVOIR]`

Placeholder. Not buildable here (no JDK / Android SDK) — open in **Android Studio**.

- Pure-native **Jetpack Compose / Kotlin** (`ARCHITECTURE.md §1`). Thin UI over a
  Kotlin crypto core that must replay the shared vectors (`crypto-core/vectors`)
  so blobs interoperate with iOS (multi-device sync, V1).
- Keys in the **Android Keystore**, non-extractable, biometric-unlocked
  (`ARCHITECTURE.md §1`). Crypto core isolated, never OTA (`SECURITY.md §1.5`).
- Screens: same as iOS — `DESIGN_INTEGRATION.md §9` and §11.
