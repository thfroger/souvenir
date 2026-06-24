# IMPLEMENTATION.md

> **État vivant du chantier** — *pas* un document d'autorité. La précédence reste
> `SECURITY.md` > `ARCHITECTURE.md` > `TESTING.md` > `DESIGN_INTEGRATION.md` > handoff design.
> Ce fichier dit *ce qui est construit aujourd'hui* et *les décisions prises en cours de route*,
> pour reprendre vite. Dernière mise à jour : **2026-06-24**.

---

## CI — 3 jobs bloquants, tous verts

`.github/workflows/ci.yml` : `crypto-core` (Swift, macos-14), `invariants` (backend `node --test`, ubuntu), `ios-app` (build simulateur, Xcode 15.4 / Swift 5.10 — **plus strict** que le Xcode local 26.x).

## Construit

### `crypto-core/` (noyau isolé, audité, figé dans le binaire — `SECURITY §1.5`)
- Swift Package + suite bloquante (`swift run CryptoCoreTests`, prérequis `brew install libsodium`).
- AEAD XChaCha20-Poly1305, emballage de clés, Argon2id, BLAKE2b, **Shamir GF(256) 2-sur-3** (`SECURITY §5`). `AEAD.Sealed` / `WrappedKey` `Codable` (base64) pour persistance/sync. Vecteurs partagés pour l'interop Kotlin à venir.

### `backend/` (store « bête » en mémoire, JS pur, zéro dépendance — `node --test`)
- Blobs adressés par contenu + lignes de métadonnées **opaques** (`wrapped_key`, `blob_hash`) ; allowlist/denylist de champs ; logs sans contenu.
- **Janitor** des blobs orphelins (`collectOrphans`, `ARCHITECTURE §5` / `TESTING §4`).
- **Auth équivalent-passkey** : `POST /auth/register` (clé publique P-256 X9.63 → coffre), `/auth/challenge` (nonce à usage unique), `/auth/verify` (vérif ECDSA → **jeton de session**). Routes blobs/entries autorisées par session. `tok-A`/`tok-B` = sessions de test pré-amorcées.
- **22 tests** : invariants + autorisation + janitor + auth.

### `ios/` (SwiftUI, natif — `ios/Souvenir/`)
- **Entrée** : `RootView` → `LockView` (déverrouillage **Face ID/Touch ID**, sans skip, repli code ; `NSFaceIDUsageDescription` requis). `ContentView`/store créés **après** déverrouillage.
- **Auth appareil** : `DeviceIdentity` (clé P-256 Secure Enclave sur device / logicielle sur simu), `AuthClient` (register→challenge→sign→session), `SecureStore` (Keychain + **repli fichier dev** pour le simu non signé, erreur `-34018`). `MemoryStore` s'authentifie au lancement → jeton de session (plus de `tok-A` dans l'app).
- **Capture** (`CaptureView`, `MemoryStore`) — 6 types : citation, mesure, photo (bibliothèque), **note vocale** (`AudioRecorder`/lecture réelle), **jalon** (texte), **dessin** (`CameraPicker` → **appareil photo**, `NSCameraUsageDescription`). Photos/dessins **EXIF-strippés** + chiffrés.
- **Persistance** : index **entièrement chiffré** sur disque (enfant/type/date civile inclus, `§6.4`) ; DEK par souvenir emballée sous la VK (Keychain).
- **Sync** : push chiffré + **pull/merge multi-appareils** (union par UUID, spike #3). Offline-first (échecs réseau rattrapés).
- **Frise** (écran A) : timeline + surprise + indicateur de sync. Identité `Memory` **stable** (id de l'entrée).
- **Ciel** (écran B, ex-Arbre — voir Décisions) : `ArbreView`.
- **Immersif** (écran C) : `ImmersiveMemoryView` (photo à sa hauteur naturelle, bouton retour visible, lecture audio).
- Vraies polices embarquées (Instrument Serif / Hanken Grotesk / Geist Mono), mode **clair forcé**.

## Décisions prises en cours de route (au-delà des docs)

1. **Écran B : arbre → « Le ciel » saisonnier** (décision produit). Souvenirs = créatures de saison qui bougent : fleurs (printemps), **poissons** (été, « L'océan de … »), feuilles (automne), flocons (hiver). `TimelineView(.animation)`, positions/couleurs **déterministes par id** (stables sur la session). Onglet « Ciel ». Cartes du bas = **filtre ANNÉE** (déroulant : années avec souvenirs + « Toutes ») + **compteur SOUVENIRS** vivant. La **mesure** n'apparaît pas comme créature. Consigné dans `DESIGN_INTEGRATION §0`.
   - Réglages déjà itérés : vitesse (bug de téléportation corrigé = id régénéré 60×/s ; déchiffrement hoisté hors de la boucle d'animation), grille jitterée anti-superposition, poissons ×1,5, direction re-tirée à chaque traversée.
2. **Auth V1 = équivalent passkey**, pas WebAuthn (cf. `SECURITY §6.3`) : WebAuthn exige un domaine HTTPS + AASA + entitlement, non disponibles ; reporté. Le backend émet déjà des sessions, prêt à recevoir WebAuthn.
3. **Replis dev (ne shippent pas)** : Keychain → fichier sur simu non signé ; backend en mémoire sur `http://localhost:8787`. Sur **iPhone physique**, `localhost` ne joint pas le Mac → sync KO en local (attendu) ; une **URL backend configurable** (IP du Mac) reste à faire.
4. **Signature** : `DEVELOPMENT_TEAM` **hors du repo**, dans `ios/Souvenir/Signing.local.xcconfig` (gitignored ; exemple `.example` versionné).

## Méthode de vérif (utile à reproduire)

Build simulateur → screenshot via hooks **temporaires** `DEMO_*` (bypass lock, présenter un écran, forcer une saison) → **on retire les hooks avant commit** → push → CI en arrière-plan → vert. Suite crypto/backend en local. (Face ID et caméra ne se testent pas en headless → confirmés sur l'appareil par l'utilisateur.)

## Prochaines pistes (par valeur)

1. **URL backend configurable** (sync depuis l'iPhone via l'IP du Mac).
2. **Vrais passkeys WebAuthn** (quand un domaine + entitlement existent).
3. **Persistance backend réelle** (Postgres + object storage) + spikes #1/#2 (plans d'exécution, burst de resync).
4. **Ciel** : densité/vitesse par saison, fond plus immersif (option).
5. Impl **Kotlin/Compose** (Android) rejouant les vecteurs crypto.

## Lancer

- Crypto : `cd crypto-core/swift && swift run CryptoCoreTests` (`brew install libsodium`).
- Backend : `cd backend && node --test` (tests) ; `node src/server.js` (serveur :8787).
- iOS : ouvrir `ios/Souvenir.xcodeproj` dans Xcode ; copier `Signing.local.xcconfig.example` → `Signing.local.xcconfig`, y mettre son `DEVELOPMENT_TEAM`.
