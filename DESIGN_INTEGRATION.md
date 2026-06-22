# DESIGN_INTEGRATION.md

> Pont entre le handoff design (`DESIGN.md`, `README.md`, `*.dc.html`) et la fondation technique (`SECURITY.md`, `ARCHITECTURE.md`, `TESTING.md`).
> Le design a été conçu sans référence aux contraintes zero-knowledge. Ce document arbitre les collisions.
> **Règle de précédence** : un invariant de `SECURITY.md` l'emporte toujours sur un détail de design. Dans la latitude UI (tout ce qui ne touche pas un invariant), le **hi-fi fait foi** (cf. README).

---

## 0. Erratum du handoff — ce qui est périmé dans `DESIGN.md` / `README.md` / `*.dc.html`

> Les fichiers de handoff sont conservés **tels quels** (références visuelles). Cette liste les corrige sans les modifier. **En cas de divergence, cette liste gagne.** Les `*.dc.html` restent des références d'apparence uniquement — n'en porter aucun comportement.

| Dans le handoff | Statut | Correction |
|---|---|---|
| `README` recommande **React Native + Expo** | **PÉRIMÉ** | Natif pur (SwiftUI + Compose/Kotlin). Voir §1 et `CLAUDE.md` règle 3. Ignorer la reco RN. |
| **Like / bouton cœur** (écran C), état `liked`, champ `liked` du modèle | **SUPPRIMÉ** | Retiré du périmètre. Pas de cœur dans la vue immersive. Voir §6. |
| Feuille d'ajout (écran D) **sans choix perso/partagé** | **CORRECT POUR LA V1** | En V1 (solo, pas de co-parent) il n'y a PAS de choix perso/partagé — l'écran D est bon tel quel. Le perso/partagé (§7) est une évolution **V2**. |
| Co-parentalité présentée comme centrale | **V2** | Le défaut est solo. Coffre partagé, invitation, séparation = V2. Voir `CLAUDE.md` mission. |
| Note vocale | **OK, mais sans transcription** | Enregistrement + lecture seulement. Aucune transcription (jamais demandée par le design). Voir §5. |
| Sélecteur d'enfant « recharge tout » | **À PRÉCISER** | Appartenance enfant **chiffrée**, filtrage 100 % local. Voir §2. |
| « Surprise du jour », stats de l'Arbre | **À PRÉCISER** | Calculés **côté client** après déchiffrement (le serveur ne lit ni dates ni contenus). Voir §3. |
| Photos = placeholders | **À COMPLÉTER** | Strip EXIF à la capture + miniatures chiffrées générées côté client. Voir §4. |
| `DESIGN.md §7` liste le fichier `Souvenir.dc.html` | **NOM ERRONÉ** | Le fichier réel est `Souvenir - Explorations 3 pistes.dc.html` (cf. table des fichiers de `README.md`). Contexte/exploration uniquement, pas une référence d'interaction. `support.js` (runtime des protos) est présent. |
| `DESIGN.md §5` mentionne « lettres écrites à l'enfant pour plus tard » *(à venir)* | **CADRÉ V2/V3** | Si réintroduite : un souvenir chiffré + date cible ; « ouverture à la date » = **convention d'affichage côté client** (comme « une photo/jour »), jamais un time-release **serveur** (clé libérée à une date = séquestre = casse le ZK). Aucun verrou temporel cryptographique promis. Voir piège dans `CLAUDE.md`. |

---

## 1. Framework : natif pur, PAS React Native `[FIGÉ — corrige le README]`

Le `README` de handoff recommande « React Native + Expo, ou SwiftUI ». **Cette recommandation est neutralisée.** `ARCHITECTURE.md §1` a écarté React Native : les ponts JS vers la crypto native sont le maillon qu'un auditeur n'aime pas, et le produit *est* vendu sur l'irréprochabilité vérifiable.

- On recrée le design en **SwiftUI (iOS) + Jetpack Compose / Kotlin (Android)**.
- Le design est une **référence visuelle agnostique** au framework — le porter en natif ne perd rien.
- Animations riches, transitions `cubic-bezier`, Liquid Glass de la barre du bas : entièrement à la portée du natif. L'argument « app riche en animations → RN » ne tient pas.
- Le **module crypto isolé** (`SECURITY.md §1.5`) reste séparé de la couche UI, quelle que soit la beauté de cette dernière.

---

## 2. Modèle enfant × coffre `[FIGÉ — enfant chiffré]`

Le design traite l'enfant comme un simple sélecteur « qui recharge tout ». En ZK + co-parents, c'est plus subtil : **l'enfant est une dimension orthogonale au coffre.**

Un souvenir appartient à un couple **(enfant, coffre ∈ {perso, partagé})** :
- `enfant` = Léa / Noé / … (dimension d'affichage)
- `coffre` = perso (visible de son seul auteur) ou partagé (visible des deux co-parents) — dimension de visibilité cryptographique (`SECURITY.md §4`)

Le sélecteur d'enfant de la Frise/Arbre est donc un **filtre côté client**, pas une requête serveur.

**Décision à prendre : l'appartenance à un enfant est-elle métadonnée serveur ou chiffrée ?**
- Si métadonnée serveur → le serveur sait que tu as 2 enfants et combien de souvenirs chacun (fuite).
- Si chiffrée → filtrage 100 % local, le serveur ne voit que des blobs par coffre.
- **Décision : chiffrée** (cohérent avec la minimisation, `SECURITY.md §8.1`). Le serveur ne voit que des blobs par coffre, pas la structure familiale. Conséquence : on synchronise le coffre (métadonnées + miniatures, pas tous les pleins formats — `ARCHITECTURE.md §2.1`) puis on filtre localement par enfant. La réplication par paliers rend cette option viable côté taille d'app.

### 2.1 Entité « profil enfant » `[FIGÉ — chiffrée]`
L'enfant n'est pas qu'un tag sur les souvenirs : c'est une **entité à part entière**, parce que le design exige des infos propres à l'enfant — prénom affiché, **date de naissance** (indispensable pour l'âge « 3 ans » et le « il y a 3 ans, aujourd'hui »), avatar. Modélisée comme **entrée chiffrée** dans le coffre perso (même journal append-only que les souvenirs, `ARCHITECTURE.md §3`), **jamais en métadonnée serveur** : le serveur ne sait ni combien d'enfants, ni leurs noms, ni leurs dates de naissance (`SECURITY.md §8.1`).

Champs (tous contenu chiffré) :
- `child_id` (UUID client) — c'est la référence (chiffrée) que chaque souvenir porte pour son appartenance enfant.
- `prénom` / surnom / emoji.
- `date de naissance` **complète** (jour/mois/année). Donnée civile d'un mineur = **catégorie spéciale**, chiffrée au même titre que le tag `maladie` (`SECURITY.md §1.4`). Comme elle ne quitte jamais l'appareil, la date complète est acceptable et donne des libellés d'âge précis.
- style d'avatar (couleurs du dégradé — Léa = rose→lilas, Noé = bleu→vert).

**Pas dans l'entité enfant** : la taille / le poids ne s'y stockent pas — ce sont des souvenirs de type « Mesure » ; l'Arbre affiche la valeur la plus récente (calcul client, §3). On garde l'entité enfant **minimale**.

---

## 3. Trois features du design = calculs côté client `[FIGÉ]`

Le serveur ne lit ni les dates ni les contenus chiffrés. Donc :

- **« Souvenir surprise du jour »** (« il y a 3 ans, aujourd'hui ») : **calculé localement après déchiffrement**, sur les souvenirs déjà synchronisés/en cache. Repose sur la **date civile locale + fuseau** (`ARCHITECTURE.md §3`) — un souvenir « du même jour » dépend du jour civil, pas d'un instant UTC. Conséquence UX : la surprise ne couvre que ce qui est disponible localement ; à gérer gracieusement hors-ligne (ne pas promettre une surprise si rien n'est en cache).
- **Stats de l'Arbre** (« 142 éclats », « 78 cm ») : **comptées/agrégées côté client** après déchiffrement. Jamais un compteur servi par le serveur.
- **Filtrage par enfant** : côté client (voir §2).

---

## 4. Données sensibles dans le design `[FIGÉ]`

- **Mesures (taille / poids)** : ce sont des données personnelles sensibles d'un mineur. Traitées **comme du contenu chiffré**, au même titre que le tag `maladie` (`SECURITY.md §1.4`). Jamais en métadonnée serveur, jamais en log. La carte stat « TAILLE — 78 cm » est rendue à partir d'une valeur déchiffrée localement.
- **Photos** : strip **EXIF** systématique à la capture (`SECURITY.md §8.1` — la géoloc EXIF trahit « cet enfant était à tel endroit tel jour »). **Miniatures générées côté client à la capture** (`ARCHITECTURE.md §6`), stockées comme blobs chiffrés séparés.
- **Tailles d'image du design** : vignette 66px, carte surprise 188px, immersif ≈430px. → au moins **deux paliers** (miniature + plein), idéalement trois, chacun un blob chiffré distinct. ⚠ Ces paliers de **résolution** sont distincts du **padding de taille anti-empreinte** (`SECURITY.md §6.2`, politique figée) : appliquer le padding **aussi** sur les miniatures, sinon leur taille exacte fuit.
- **Prénoms (Camille, Léa, Noé)** : acceptables (prénom/surnom/emoji autorisés, `SECURITY.md §8.1`) ; ce sont du **contenu chiffré**, pas une métadonnée.

---

## 5. Voix `[FIGÉ — déjà aligné]`

Le lecteur de note vocale (« la voix de Léa », forme d'onde, play/pause terracotta) est compatible tel quel. Rappels d'implémentation :
- Audio capturé et chiffré localement ; le blob audio ne quitte jamais l'appareil en clair.
- **Pas de transcription** : enregistrement et lecture seulement (`ARCHITECTURE.md §1`). La forme d'onde et la progression sont du rendu local ; remplacer le `setInterval` simulé du proto par un vrai lecteur. Si la transcription revenait un jour (recherche/sous-titres), ce serait obligatoirement on-device, jamais la Web Speech API.

---

## 6. État « like » `[FIGÉ — supprimé du périmètre]`

Le like n'est pas nécessaire et n'a pas vocation à être public. **Retiré du périmètre.** Conséquence design : le **bouton cœur de la vue immersive** (écran C, `DESIGN.md`) est **supprimé**, pas remplacé. Le champ `liked` disparaît du modèle de données (§10). Si un besoin réapparaissait un jour, il serait privé/local par utilisateur, jamais un flag serveur en clair.

---

## 7. La feuille d'ajout doit porter le choix perso/partagé `[À CONCEVOIR — priorité]`

C'est la réconciliation design↔sécurité la plus importante. L'écran D actuel choisit un **type** mais pas le **destinataire** (perso vs partagé). Or `SECURITY.md` fait du « quel souvenir va dans quel coffre » le défi UX n°1 : un parent ne doit **jamais** croire privé ce qui est partagé.

Exigences pour le flux d'ajout révisé :
- **Solo-first** : le persona par défaut est une mère seule. Tant qu'aucun co-parent n'est lié, **le choix perso/partagé n'apparaît pas** — tout va dans le coffre perso. Le partage est une couche **optionnelle** qui s'active à l'invitation d'un co-parent ; ce n'est jamais un prérequis de configuration.
- Une fois un co-parent lié : le **destinataire (perso / partagé)** est un choix **explicite et visible**, pas un défaut caché.
- L'état du souvenir (perso ou partagé) reste **lisible en permanence** après création (un marqueur discret mais non ambigu sur la vignette de frise et dans la vue immersive).
- En multi-enfants, le couple (enfant, coffre) est affiché sans ambiguïté au moment de garder le souvenir (« de Léa — partagé avec l'autre parent » vs « de Léa — privé »).
- Friction placée comme un **soin**, pas comme une corvée : le moment où l'on décide qui verra ce souvenir fait partie de l'intention tendre du produit, pas contre elle.

Ce flux a un **effet retour possible sur l'archi** : à prototyper tôt (cf. §9 et `ARCHITECTURE.md §10`).

---

## 8. Indicateurs offline / sync à ajouter à l'UI `[À CONCEVOIR]`

Le design suppose une connexion et un contenu toujours présent. L'offline-first (`ARCHITECTURE.md §2`, résilience structurelle liée au ZK — plus une exigence terrain) impose des affordances que le handoff ne couvre pas :
- **Ne jamais afficher un souvenir non `committed`** (`ARCHITECTURE.md §5`) : la frise ne montre que des souvenirs dont le self-check de re-déchiffrement a réussi.
- État **« en cours de synchronisation »** discret et tendre (pas un spinner anxiogène) pour les souvenirs en attente d'upload.
- Indicateur **hors-ligne** honnête mais doux.
- Le **burst de resync** (retour en ligne après des jours) ne doit pas figer l'UI.

Principe directeur, cohérent avec l'éthos éditorial : la friction de sécurité se *ressent comme du soin*, jamais comme une corvée.

---

## 9. Écrans sécurité-critiques manquants dans le handoff `[À CONCEVOIR]`

Le handoff ne contient que le cœur joyeux (Frise, Arbre, Immersif, Ajout). Manquent tous les écrans qui portent les invariants. À concevoir dans la même direction visuelle (Instrument Serif / Hanken / Geist Mono, papier crème, icônes au trait, zéro émoji) :

| Écran manquant | V1/V2 | Atteint depuis | Porte quel invariant / section |
|---|---|---|---|
| **Réglages (hub)** | **V1** | bouton sliders de l'en-tête Frise | **point d'entrée** vers les écrans ci-dessous |
| Onboarding / création de compte (pseudonyme) | **V1** | premier lancement | `SECURITY.md §8.1` minimisation |
| Déverrouillage biométrique (rituel d'entrée) | **V1** | ouverture de l'app | `SECURITY.md §3`, `§6.3` |
| Configuration synchro multi-appareils (appareil de confiance) | **V1** | hub Réglages | `SECURITY.md §7` |
| **Récupération sociale Shamir** (choix des 3 gardiens) | **V1** | onboarding (filet jour-1) + hub | `SECURITY.md §5` — effet retour archi |
| Export / album papier (rituel côté client) | **V1** | hub Réglages | `SECURITY.md §9` |
| Paywall / abonnement (porte le **gate d'âge**) | **V1** | onboarding + hub | `SECURITY.md §8.2`, §10 |
| Signalement | **V1** | hub Réglages + vue immersive | `SECURITY.md §8.3` |
| Invitation co-parent *(optionnel, solo-first)* | **V2** | hub Réglages | `SECURITY.md §4` |
| **Séparation** (arrêt du partage + rotation SVK) | **V2** | hub Réglages | `SECURITY.md §4.2` — effet retour archi |

Le **hub Réglages** est la destination, aujourd'hui non dessinée, du bouton sliders de l'en-tête : c'est lui qui rend les écrans ci-dessus atteignables. Les deux écrans en gras (Shamir **V1**, séparation **V2**) sont les flux **à effet retour sur l'archi** : à prototyper avant de figer. Tout reste à dessiner en hi-fi dans la même direction visuelle (Instrument Serif / Hanken / Geist Mono, papier crème, icônes au trait, zéro émoji).

---

## 10. Réconciliation du modèle de données

Le modèle du `README` (`id, child, type, date, ageLabel, title, note, photo?, audio?, milestone?, measure?, isSurprise, liked`) se mappe ainsi sur l'entrée immuable de `ARCHITECTURE.md §3` :

- **Métadonnées serveur (opaques)** : `entry_id` (UUID client), `vault_id`, `seq`, `committed`, `wrapped_key`, `blob_hash`, horodatage technique. **Rien d'autre.**
- **Contenu chiffré (jamais côté serveur en clair)** : `child_id` (réf. → entité profil enfant §2.1), `type`, `date civile + fuseau`, `title`, `note`, `measure`, `milestone`, et les blobs `photo`/`audio` (+ miniatures).
- **Entité enfant séparée (§2.1)** : `child` du `README` n'est pas un champ texte sur chaque souvenir mais un **`child_id`** (référence chiffrée) vers l'entité profil enfant, qui porte `prénom` + `date de naissance` complète.
- **Calculé côté client, jamais stocké** : `ageLabel` (= date civile du souvenir − date de naissance de l'enfant, §2.1 — **déplacé** de « contenu chiffré » vers « calculé »), `isSurprise` (dérivé de la date anniversaire locale), les stats de l'Arbre, le filtrage par enfant.
- **`liked`** : supprimé du périmètre (§6).

---

## 11. Ce qui est compatible tel quel (à recréer fidèlement)

Pour éviter de sur-corriger : l'essentiel du design ne pose aucun problème et doit être recréé fidèlement (hi-fi fait foi) — système typographique, palette papier crème, formes très arrondies, Liquid Glass limité à la barre du bas, **interdiction des émojis** (icônes au trait uniquement), Frise éditoriale, vue immersive, Arbre, transitions. La sécurité ne change pas l'apparence ; elle change *où vivent les données* et *quels écrans manquent*.
