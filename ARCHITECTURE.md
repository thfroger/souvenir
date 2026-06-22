# ARCHITECTURE.md

> Le « comment » qui réalise les invariants de SECURITY.md.
> Convention : `[FIGÉ]` = décision constitutive, ne pas rediscuter sans raison forte.
> `[À VALIDER PAR SPIKE]` = hypothèse qui se vérifie en construisant, pas sur le papier. À ne PAS écrire comme une certitude.

---

## 1. Stack `[FIGÉ]`

- **Natif pur** : Swift (iOS) + Kotlin (Android), deux bases de code.
- **Pourquoi pas React Native** : les ponts JS vers la crypto native sont précisément le maillon qu'un auditeur n'aime pas.
- **Pourquoi pas Kotlin Multiplatform** : le seul argument KMP était d'économiser une 2e base de code en solo. Sans contrainte de temps, cet argument tombe, et le natif pur donne l'accès le plus direct au Secure Enclave / Android Keystore, la surface d'attaque la plus réduite, et le code le plus simple à auditer (aucun pont à expliquer).
- **Crypto** : `libsodium` partout. **Module crypto isolé, open-source, figé dans le binaire signé. Jamais d'OTA dessus** (invariant SECURITY §1.5). L'OTA (le cas échéant) ne touche que l'UI et la logique non sensible.
- **Voix** : enregistrement et lecture **uniquement, pas de transcription**. Capture (AVAudioRecorder iOS / MediaRecorder Android) → encodage AAC ou Opus → chiffrement du blob → traité comme tout autre souvenir. La forme d'onde du design se calcule depuis le fichier audio. *Transcription écartée du périmètre actif (aucun besoin de recherche/sous-titres pour l'instant) ; réintroductible un jour mais alors **obligatoirement on-device** pour préserver le ZK — jamais la Web Speech API, qui envoie l'audio chez Google/Apple.*
- **Stockage des clés** : Secure Enclave (iOS) / Android Keystore, clés non extractibles, déverrouillées par biométrie.
- **Backend** : volontairement bête. Entrepôt de blobs chiffrés + métadonnées opaques. Pas de traitement d'image, pas d'indexation de contenu, pas de crypto par requête. Postgres (métadonnées) + object storage (blobs).

### 1.1 Tout en natif, pas de consultation web `[FIGÉ]`
- **Écriture ET consultation natives** (capture, chiffrement, déchiffrement, voix, choix perso/partagé, feuilletage de la timeline) : tout ce qui touche aux clés vit dans le binaire signé. Le natif donne biométrie fluide, capture plein écran, voix sans latence réseau, offline réel, stockage persistant non purgeable.
- **Pas de consultation web `[FIGÉ]`.** Afficher un souvenir impose de le déchiffrer, donc de manipuler la chaîne MIK→VK→DEK ; le faire dans un JS re-servi à chaque session est précisément le maillon que `SECURITY.md §2.4` oppose au binaire natif signé — un web déchiffrant affaiblirait l'argument central du produit. Le confort « grand écran » éventuel se fera donc un jour en **app native iPad/Mac** (toujours du natif, manipulation de clés légitime), jamais en web.

---

## 2. Offline-first `[FIGÉ]`

L'offline n'est **pas** une exigence terrain (la cible est la France métropolitaine, connectivité globalement bonne) mais une **résilience structurelle non négociable** : l'app ne doit jamais être compromise par la connectivité. La justification est ZK, pas géographique : (1) la capture, le chiffrement et le self-check se font de toute façon sur l'appareil ; (2) un souvenir doit pouvoir être gardé dans une zone sans réseau ponctuelle (avion, sous-sol, coupure, déplacement) et se synchroniser ensuite. L'app DOIT être pleinement fonctionnelle hors-ligne **en écriture**, et synchroniser opportunément. Conséquences majeures sur le modèle de données (§3) et la concurrence (§4).

### 2.1 Politique de réplication locale par paliers `[FIGÉ]`
Ne PAS répliquer tout l'historique en local (croissance non bornée : ~1–1,5 Go/an/enfant en pleine résolution → plusieurs Go après quelques années). Réplication par paliers :
- **Toujours en local** : métadonnées + **miniatures** de *tous* les souvenirs (léger, quelques centaines de Mo même sur des années). → permet de feuilleter toute la Frise et l'Arbre **hors-ligne**.
- **Pleine résolution récente** : fenêtre glissante (≈ 6–12 mois) gardée en local.
- **Pleine résolution ancienne** : récupérée **à la demande** (blob chiffré → déchiffré → affiché → re-caché en LRU).

Empreinte stabilisée ≈ **~1 Go** quel que soit l'historique (binaire + miniatures + cache récent ; plus de modèle embarqué depuis le retrait de la transcription), au lieu d'une croissance illimitée.

**Conséquence offline assumée** : un parent hors-ligne quelques jours (déplacement, vacances) peut toujours *parcourir* sa timeline (miniatures) ; ouvrir la pleine résolution d'un vieux souvenir non caché peut nécessiter une connexion. C'est le prix d'une empreinte bornée — à exposer doucement dans l'UI (`DESIGN_INTEGRATION.md §8`). En métropole, ce cas est marginal mais doit rester gracieux.

**Lien décision enfant-chiffré** : « enfant chiffré » impose de synchroniser le coffre pour filtrer localement — mais « synchroniser » = métadonnées + miniatures, pas tous les pleins formats. La réplication par paliers rend donc l'option chiffrée viable sans gonfler l'appareil.

---

## 3. Modèle de données : journal append-only

`[FIGÉ]` — c'est la décision qui résout la concurrence (§4) et l'atomicité (§5).

- Un coffre = un **journal append-only d'entrées immuables**, PAS des lignes mutables.
- Chaque souvenir = une **entrée immuable**, clé par **UUID généré côté client**.
- Conséquence : deux ajouts ne collisionnent jamais ; ils survivent tous les deux.
- La règle « **une photo par jour** » est une **convention d'affichage côté client** (on montre les deux et le parent choisit), **JAMAIS une contrainte serveur destructive**. Le serveur ignore la date (chiffrée) ; il ne peut pas l'imposer, et hors-ligne entre deux appareils elle est inapplicable de toute façon.
- **Champs réellement mutables** (prénom de l'enfant, tags) : `last-writer-wins` **par champ** avec **version vectors (vector clock)** — *pas* une horloge de Lamport scalaire, qui ne sait pas distinguer « concurrent » de « causalement postérieur » et casserait le LWW par champ. Deux éditions de champs différents gagnent ainsi toutes les deux ; une vraie concurrence sur le *même* champ est détectée puis tranchée (LWW).
- **Date** : stocker la **date civile locale + le fuseau**, pas un instant UTC nu. Un souvenir créé à 23h à Cayenne n'est pas le même jour civil qu'en UTC ; sans ça, les souvenirs sautent de jour.
- **Entité « profil enfant »** : le journal append-only ne contient pas que des souvenirs ; il porte aussi une **entrée chiffrée par enfant** (prénom, **date de naissance complète**, avatar — `DESIGN_INTEGRATION.md §2.1`). Chaque souvenir référence son enfant par un `child_id` chiffré. C'est du **contenu chiffré**, jamais une métadonnée serveur (`SECURITY.md §8.1`) : le serveur ignore le nombre d'enfants et leurs dates de naissance. Le `prénom` est un champ mutable (LWW par champ, ci-dessus).

### 3.1 Métadonnées d'une entrée (côté serveur, opaques)
`entry_id (uuid client)`, `vault_id`, `seq` (monotone par coffre), `committed` (bool), `wrapped_key` (clé de données emballée — **embarquée dans la ligne** pour tuer le N+1, voir §6), `blob_hash`, `created_at` technique. **Aucun champ de contenu, aucune date civile en clair, aucun tag.**

---

## 4. Concurrence `[À VALIDER PAR SPIKE]` sur le merge

Le serveur ne peut pas merger : il ne lit pas le chiffré. Tout le merge est côté client.

- **Ajouts concurrents** : résolus par le journal append-only (§3) — rien n'est perdu, jamais d'écrasement (pas de lost update).
- **Édition concurrente de champs mutables** : LWW par champ + **version vectors** (§3).
- **Double-soumission de formulaire** : tuée par l'UUID d'idempotence client (§5).
- **Écritures concurrentes de la même ligne de sync depuis deux appareils** : **concurrence optimiste** (colonne `version`), PAS de verrous — sinon on crée des deadlocks sur un système qui doit rester sans état.

> `[À VALIDER PAR SPIKE #3 — V1]` **Sync multi-appareils d'une même utilisatrice.** Simuler deux appareils du *même* auteur (parent 1) hors-ligne — **pas de volontés concurrentes** — puis sync. Vérifier empiriquement : aucun souvenir perdu, convergence déterministe, comportement de la convention « une par jour » à l'affichage. C'est le cas **V1**.

> `[À VALIDER PAR SPIKE #4 — V2]` **Merge offline deux co-parents.** Le coffre partagé n'existe qu'en **V2** (SECURITY §4). Simuler deux *co-parents* hors-ligne éditant le même coffre partagé, puis sync. Ne pas figer la stratégie de merge fine **à deux auteurs** avant ce spike.

---

## 5. Gestion d'erreurs et atomicité `[FIGÉ]` (sauf mention)

Créer un souvenir n'est pas une écriture unique : chiffrer local → uploader blob (object storage) → écrire métadonnées (Postgres) → écrire clé emballée. Trois systèmes, pas d'atomicité native.

**Scénario de casse** : connexion qui saute en déplacement (sous-sol, avion, réseau faible) ; le blob s'uploade mais le POST métadonnées timeout → retry qui duplique, ou blob orphelin facturé, ou (pire) métadonnées pointant vers un blob absent → la timeline affiche les « premiers pas » en case cassée.

**Protocole de commit :**
1. **UUID d'idempotence** généré client → le retry ne duplique pas.
2. **Blobs adressés par hash** → deux uploads identiques convergent.
3. Métadonnées écrites **en dernier**, état `pending → committed`.
4. **On n'affiche jamais une entrée non `committed`.**
5. **Job balai** (janitor) : supprime les blobs sans métadonnée committée après N heures.
6. Atomicité intra-Postgres = vraies transactions. Atomicité inter-systèmes = pattern **outbox / saga**, jamais de 2PC.

**Erreur silencieuse spécifique ZK (la plus grave) :** une clé emballée écrite de travers ou un blob tronqué rend le souvenir **définitivement indéchiffrable**, et le serveur ne peut pas le détecter (il ne relit pas le chiffré).
**Parade non négociable (invariant SECURITY §1.6) :** après chaque upload, l'appareil **re-télécharge et re-déchiffre** le souvenir pour confirmer qu'il est lisible *avant* de marquer `committed`. **On ne supprime jamais l'original local tant que ce self-check n'est pas passé.** Un échec de self-check émet un beacon de télémétrie sans contenu (voir §8 et TESTING.md).

---

## 6. Performance et charge

La bonne nouvelle : le backend bête scale bien ; 500 utilisateurs en régime stable ne sont pas le problème. Ce qui casse en premier, c'est la **bande passante média**, pas le CPU.

- **Le vrai pic = le burst de resynchronisation** : un parent de retour en ligne après plusieurs jours hors-ligne (vacances, déplacement) déverse son arriéré de photos + notes vocales d'un coup, × N parents → saturation de l'endpoint d'upload et de l'object storage. Moins aigu qu'en contexte terrain (on parle de jours, pas de semaines), mais à dimensionner quand même.
- **N+1 sur la timeline** : 1 requête lignes + N clés + N blobs. Corrections : clé emballée **dans la ligne** (un seul fetch) ; **pagination par plage de dates avec curseur** (jamais de load-all) ; **lazy-load des blobs au scroll** avec miniatures.
- **Miniatures** : comme tout est chiffré, **générées côté client à la capture** et stockées comme petits blobs séparés.
- **Padding anti-empreinte** : le padding des blobs par paliers (`SECURITY.md §6.2`) s'applique **côté client avant upload**, sur les pleins formats *et* les miniatures. Il gonfle le stockage (ciphertext non compressible — ligne P&L, `SECURITY.md §10`) ; l'échelle des paliers se calibre empiriquement (spike ci-dessous).
- **Index qui compte** : composite `(vault_id, seq)` pour le delta de sync « tout ce qui a changé depuis le curseur Y ». Sans lui, chaque poll de chaque appareil fait un full scan.
- Les deux requêtes chaudes (delta de sync, plage de timeline) doivent être des **index-only scans** sur `(vault_id, seq)`.

> `[À VALIDER PAR SPIKE]` **Plan d'exécution réel.** Le `EXPLAIN (ANALYZE, BUFFERS)` des requêtes chaudes ne peut pas être produit sérieusement sans schéma réel + jeu de données représentatif. À mesurer, pas à supposer. Fabriquer un faux plan d'exécution serait de la fausse précision.

> `[À VALIDER PAR SPIKE]` **Burst de resync sous charge.** Bancher N appareils déversant chacun plusieurs jours de média simultanément. Mesurer où l'object storage / l'endpoint d'upload sature, et calibrer back-pressure / upload par lots / reprise.

> `[À VALIDER PAR SPIKE]` **Échelle de padding anti-empreinte (§6.2 SECURITY).** Mesurer le surcoût de stockage réel de plusieurs échelles géométriques (×1,1 / ×1,25 / ×1,5) vs leur capacité à brouiller les empreintes, sur un jeu représentatif de tailles photo/audio/note + miniatures. Figer l'échelle ensuite. Le **principe** (padding par paliers) est `[FIGÉ]` ; seule l'échelle reste à mesurer.

---

## 7. Edge cases `[FIGÉ]`

- **Fichier géant** : « une photo/jour » est une politique, pas une garantie. Plafonner la taille **côté client ET rejeter le dépassement à l'endpoint** (un client malveillant ignore la règle). Plafond par photo, durée max de note vocale, refus net d'un upload de 2 Go.
- **Unicode / contenu malveillant** : tags et prénom sont du texte libre chiffré, jamais validé serveur. Un client buggé pourrait stocker un blob malformé qui **fait planter l'app de l'autre parent** au rendu après déchiffrement. Principe : **traiter tout contenu déchiffré comme une entrée non fiable**, même « le sien » (il vient d'un autre appareil). Normaliser (**NFC**) + plafonner la longueur à l'entrée ; rendre **défensivement** à la sortie.
- **Dates impossibles** (31 février) : rejet côté client + fuseau tranché explicitement (§3).
- **Vides/nuls** : note sans photo, photo sans note, vocal vide = **états valides**, à concevoir comme tels, pas à laisser comme cas non gérés.

---

## 8. Observabilité `[FIGÉ]`

Déboguer une app ZK est intrinsèquement plus dur : on ne peut JAMAIS regarder les données d'un utilisateur. Observabilité conçue autour de **signaux sans contenu**.

Signaux qui peuvent réveiller à 3h :
- **Taux d'échec des opérations crypto** (un pic d'échecs de déchiffrement = une release qui corrompt silencieusement → alerte immédiate, scénario catastrophe).
- **Beacon « self-check échoué »** (§5) : métrique unique à ce produit. Un pic signifie qu'une release abîme des souvenirs → on stoppe le déploiement.
- Taux d'erreur de sync ; 5xx object store ; ratio de succès d'upload ; croissance des blobs orphelins ; pics d'erreurs d'auth (attaque) ; échecs de webhook paiement ; SLO de latence.

Outils : **Sentry avec scrubbing agressif** (même une stack trace ne doit pas contenir un buffer déchiffré), logs structurés par type d'événement, métriques (Datadog/Grafana), checks synthétiques d'uptime.

**Release canary + alerte échec-de-déchiffrement** : comme le natif ne se hotfixe pas en 5 minutes (review des stores), ce couple est ce qui évite de pousser un build destructeur à tout le monde.

---

## 9. Maintenabilité `[FIGÉ]`

Le risque n°1 d'un produit ZK n'est pas le code illisible, c'est la **dérive de valeur** : dans 6 mois, une feature « utile » côté serveur (recherche, tag auto par IA, modération, raccourci de récupération) casse silencieusement le zero-knowledge.

- **Liste d'invariants en tête de SECURITY.md** + règle : « si une feature exige que le serveur lise du contenu, elle est refusée ou redessinée côté client ».
- **ADR (Architecture Decision Records)** pour chaque choix contre-intuitif : pourquoi le natif et pas le web, pourquoi le serveur est volontairement bête, pourquoi « une photo/jour » est une règle d'affichage, pourquoi le merge est côté client, pourquoi aucune récupération opérateur, pourquoi backoff et pas verrouillage.
- Documenter les **raisons**, pas le **quoi** (le quoi se lit dans le code ; le pourquoi se perd).

---

## 10. Récapitulatif des spikes à mener avant de figer

| # | Inconnue | Ce que le spike décide |
|---|----------|------------------------|
| 1 | Plan d'exécution des requêtes chaudes (§6) — **V1** | Index réels, forme du schéma métadonnées |
| 2 | Burst de resync sous charge (§6) — **V1** | Back-pressure, upload par lots, dimensionnement |
| 3 | Sync multi-appareils d'une **même** utilisatrice (§4) — **V1** | Convergence déterministe sans volontés concurrentes ; version vectors pour le LWW par champ sur un seul auteur |
| 4 | Merge offline deux **co-parents** (§4) — **V2** | Stratégie de merge fine à deux auteurs, comportement « une/jour » |

Ces spikes sont jetables : on prototype, on mesure, **puis** on réécrit la section concernée avec ce qu'on a appris. Un `ARCHITECTURE.md` vrai vaut mieux qu'un `ARCHITECTURE.md` aspirationnel — et c'est le genre de document qu'un auditeur respecte, parce qu'il distingue ce qu'on sait de ce qu'on suppose.
