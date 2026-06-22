# CLAUDE.md

> Fichier d'orchestration. **À lire en premier, intégralement, avant toute action.**
> Il ne décrit pas le code ; il décrit comment se comporter sur ce repo et où trouver l'autorité.

---

## Mission

`souvenir` — coffre-fort numérique zero-knowledge à souvenirs d'enfant. **Persona primaire** : une femme de 25-35 ans en France métropolitaine qui conserve les souvenirs de ses enfants. **Parcours solo-first** : la co-parentalité (modèle à deux coffres) est une couche **optionnelle prévue en V2**, jamais un prérequis. Deux exigences inséparables : une **expérience tendre et éditoriale** où l'on aime revenir, et une **sécurité irréprochable et vérifiable** sur des données d'enfants non reproductibles. Quand les deux semblent s'opposer, ce n'est pas l'un contre l'autre : la friction de sécurité se conçoit **comme du soin**, pas contre l'expérience.

---

## Carte des documents et précédence

Ordre d'autorité en cas de conflit (le plus haut gagne) :

1. **`SECURITY.md`** — la constitution. Invariants non négociables, modèle de menace, hiérarchie de clés, posture réglementaire. **Rien ne prime dessus.**
2. **`ARCHITECTURE.md`** — le « comment » technique. Stack, modèle de données append-only, sync, erreurs, performance. Contient des zones `[À VALIDER PAR SPIKE]` à ne pas figer prématurément.
3. **`TESTING.md`** — stratégie de tests automatisés reliés aux risques ; CI ; tests d'invariants = preuve d'audit.
4. **`DESIGN_INTEGRATION.md`** — pont design ↔ sécurité. Arbitre les collisions. **Lire avant de toucher à l'UI** — et lire son **§0 (erratum du handoff) en premier** : il liste ce qui, dans les fichiers ci-dessous, est périmé (React Native, like, co-parent V2…).
5. **`DESIGN.md` + `README.md` + `*.dc.html`** — handoff design, conservé **tel quel** comme référence visuelle. Font foi pour l'**apparence** (hi-fi) et la **structure/flux** (wireframes), *dans la latitude laissée par les documents 1-4 et corrigé par l'erratum §0 de `DESIGN_INTEGRATION.md`*. Ne porter **aucun comportement** depuis les `*.dc.html`.

Règle simple : **un invariant de `SECURITY.md` l'emporte toujours sur un détail de design.** Dans tout ce qui ne touche pas un invariant, le design hi-fi fait foi.

---

## Règles non négociables pour l'agent

1. **Lire `SECURITY.md` avant d'écrire une ligne.** Toute feature qui exigerait que le serveur lise du contenu est **refusée ou redessinée côté client** — jamais implémentée en l'état.
2. **Ne jamais toucher au module crypto via OTA.** Il est isolé, open-source, figé dans le binaire signé (`SECURITY.md §1.5`). Modifications crypto = nouvelle release signée, jamais un patch poussé à chaud.
3. **Stack = natif pur** : SwiftUI (iOS) + Jetpack Compose/Kotlin (Android). **Ignorer la suggestion React Native du `README` de handoff** — elle est explicitement neutralisée (`DESIGN_INTEGRATION.md §1`, `ARCHITECTURE.md §1`).
4. **Ne jamais afficher un souvenir non `committed`** (self-check de re-déchiffrement réussi requis — `ARCHITECTURE.md §5`). Ne jamais supprimer l'original local avant ce self-check.
5. **Données de catégorie spéciale** (tag `maladie`, mesures taille/poids, dates civiles, tags, prénoms) = **contenu chiffré uniquement**. Jamais en métadonnée serveur, jamais en log.
6. **Tests d'invariants en CI, bloquants** (`TESTING.md §2`) : aucun endpoint ne renvoie de clair, aucun secret dans le bundle, aucun contenu dans les logs. Les écrire en même temps que le code, pas après.
7. **En cas de doute entre « beau » et « sûr », c'est `SECURITY.md` qui tranche**, puis on cherche la forme qui rend le sûr désirable.

---

## Ordre de travail recommandé

1. **Spikes V1 d'abord** (`ARCHITECTURE.md §10`) : #1 plans d'exécution, #2 burst de resync, #3 **synchro multi-appareils d'une même utilisatrice** (cas simple : une seule personne, pas de volontés concurrentes). Le **merge concurrent à deux co-parents (#4)** part en **V2** avec le co-parent. Prototype jetable → mesure → on réécrit la section concernée avec le fait.
2. **Flux à effet retour sur l'archi (V1)** : la **configuration de la récupération sociale Shamir** (`DESIGN_INTEGRATION.md §9`, `SECURITY.md §5`) — une utilisatrice solo a besoin d'un filet dès le premier jour. Le choix **perso/partagé à la capture** n'existe qu'avec un co-parent → **V2**.
3. **Écrans sécurité-critiques manquants (V1)** du handoff (`DESIGN_INTEGRATION.md §9`), hors invitation co-parent / séparation qui sont V2.
4. **Cœur joyeux** (Frise, Arbre, Immersif, Ajout) recréé fidèlement au hi-fi (`DESIGN_INTEGRATION.md §11`).
5. Le tout sous **tests automatisés au fur et à mesure** (`TESTING.md §0` : crypto + invariants bloquants à chaque commit).

---

## Pièges connus (déjà documentés, ne pas les rouvrir naïvement)

- **Dérive de valeur** : une feature « utile » côté serveur (recherche, tag auto par IA, modération, raccourci de récupération) casse silencieusement le ZK. Réflexe : la refuser ou la redessiner côté client (`ARCHITECTURE.md §9`).
- **Authentification ≠ récupération** : aucun facteur d'auth ne récupère une clé perdue. Pas de séquestre opérateur. Filet = synchro multi-appareils + Shamir (`SECURITY.md §7`).
- **Pas d'arbitrage de tutelle** : modèle double coffre, pas de clawback, pas d'éditeur juge des conflits familiaux (`SECURITY.md §4.3`).
- **Fausse précision** : ne pas écrire comme certaines les valeurs qui relèvent d'un spike (plans d'exécution, comportement sous charge, merge). Les baliser, les mesurer, puis les figer.
- **Time-release serveur** : une « lettre à ouvrir plus tard » (`DESIGN.md §5`, cadrée V2/V3) ne doit JAMAIS être un déverrouillage piloté par le serveur (clé libérée à une date = séquestre = casse le ZK). Convention d'affichage **côté client** uniquement (`DESIGN_INTEGRATION.md §0`).

---

## Structure du dépôt

Monorepo (les « deux bases de code » natives de `ARCHITECTURE.md §1` cohabitent ici) :

- `*.md` (racine) — corpus d'autorité (ci-dessus) + handoff design (`DESIGN.md`, `README.md`, `*.dc.html`, `support.js`), **conservés tels quels**, corrigés par l'erratum `DESIGN_INTEGRATION.md §0`. `SECURITY.md` = canon FR ; `SECURITY.en.md` = traduction générée (ne pas éditer à la main).
- `crypto-core/` — le noyau crypto isolé et audité (`SECURITY.md §1.5`). `swift/` = Swift Package + **suite crypto bloquante** (`TESTING.md §1`) ; `vectors/` = vecteurs partagés que l'impl Kotlin devra rejouer (interop multi-appareils).
- `ios/`, `android/` — apps natives (SwiftUI / Compose), UI fine sur le noyau. Non buildables sans Xcode / Android Studio.
- `.github/workflows/` — CI ; le job `crypto-core` (suite §1) est bloquant. Job d'invariants (`TESTING.md §2`) en attente du backend.
- `backend/` *(à venir)* — entrepôt de blobs « bête » + tests d'invariants.

Lancer la suite crypto : `cd crypto-core/swift && swift run CryptoCoreTests` (prérequis `brew install libsodium`).

---

## Convention de balises dans les docs

- `[FIGÉ]` — décision constitutive, ne pas rediscuter sans raison forte.
- `[À VALIDER PAR SPIKE]` — hypothèse empirique, à mesurer avant de figer.
- `[À TRANCHER]` / `[À CONCEVOIR]` — décision ou écran encore ouvert, recommandation fournie.
