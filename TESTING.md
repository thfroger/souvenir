# TESTING.md

> Stratégie de tests automatisés, exécutés en CI à chaque commit.
> Principe directeur : **chaque test est rattaché à un risque** de SECURITY.md ou ARCHITECTURE.md. Un test qui ne protège aucun invariant ni aucun scénario de casse identifié est du bruit.
> Objectif double : robustesse **et** dossier d'audit (une suite verte est une preuve, pas une promesse).

---

## 0. Stratégie générale

- **Le cœur crypto + sync est de la logique pure** → testé jusqu'à l'os, **bloquant en CI**.
- **L'UI native reste fine et légèrement testée** (peu de logique à casser dedans).
- Tout tourne à **chaque commit**. Les suites « crypto » et « invariants » sont **bloquantes** (un échec casse le build, pas de merge).
- Les tests liés aux **spikes** (ARCHITECTURE §10) forment une **piste séparée** : ils valident des hypothèses empiriques et alimentent la finalisation des docs ; ils ne bloquent pas tant que la décision n'est pas figée.

---

## 1. Tests crypto — propriété & round-trip (BLOQUANT)
Rattachement : SECURITY §1, §3, §5 — ARCHITECTURE §5.

- **Round-trip complet** : chiffrer → uploader → télécharger → déchiffrer redonne l'octet identique. C'est le socle (et le miroir automatisé du self-check de prod).
- **Emballage/déballage de clés** : DEK sous VK, VK sous MIK ; un mauvais wrap échoue proprement, jamais en silence.
- **Shamir (sur la Recovery Key, SECURITY §3/§5)** : reconstitution correcte de la **RK** avec **tous** les sous-ensembles 2-sur-3, puis déballage de la MIK depuis le blob `MIK-emballée-sous-RK` ; échec attendu avec 1 part ; parts corrompues détectées ; **rotation de RK** (changement de gardien) → nouvelle RK + MIK ré-emballée, **aucun souvenir ré-chiffré**, anciennes parts inopérantes.
- **Rotation de clé** (séparation, SECURITY §4.2) : après rotation de la SVK, l'ancienne clé ne déchiffre plus les nouveaux souvenirs ; l'accès ancien est bien révoqué.
- **Dérivation** : `Argon2id` déterministe, paramètres conformes à la cible.

Caractère : purs, rapides, déterministes. Aucun réseau, aucune horloge réelle.

---

## 2. Tests d'invariants — la preuve d'audit (BLOQUANT)
Rattachement : SECURITY §1 (rend la dérive de valeur *mécaniquement détectable*).

- **Aucun endpoint ne renvoie de clair** : pour chaque route, assert que la réponse ne contient que blobs chiffrés / clés emballées / métadonnées opaques.
- **Aucun endpoint n'accepte de contenu sans clé emballée** (pas de chemin par lequel du clair pourrait entrer côté serveur).
- **Grep anti-secrets sur le bundle** : échoue si une clé de test, un secret serveur ou une backdoor est embarqué (SECURITY §1.7).
- **Aucun log ne contient de contenu de coffre** : injecter un souvenir, déclencher les chemins de log, assert que rien de déchiffré n'apparaît (ni dans les logs, ni dans une stack trace Sentry après scrubbing).
- **Pas de date civile / tag en clair côté serveur** : assert que les métadonnées persistées ne contiennent aucun champ de catégorie spéciale (SECURITY §1.4, §6.2).

Ces tests sont ce qu'un auditeur regarde en premier. Les écrire en même temps que les invariants, jamais après.

---

## 3. Tests de concurrence / merge (property-based)
Rattachement : ARCHITECTURE §3, §4.

### 3.1 Multi-appareils d'une **même utilisatrice** — V1 (BLOQUANT)
`[lié au SPIKE #3]`. Un seul auteur (parent 1), plusieurs de ses appareils, **pas de volontés concurrentes**.
- **Deux appareils de la même utilisatrice hors-ligne**, puis sync : **aucun souvenir perdu**, convergence **déterministe** quel que soit l'ordre.
- **Ajouts concurrents même date** (depuis ses deux appareils) : les deux entrées survivent (la règle « une/jour » n'efface jamais — ARCHITECTURE §3).
- **Édition du même champ depuis deux appareils** (ex. prénom de l'enfant) : LWW par champ, résultat déterministe.
- **Concurrence optimiste** : écritures simultanées de la même ligne de sync → pas de deadlock, conflit résolu par `version`.
- **Property-based** : entrelacements aléatoires d'ajouts/éditions d'un seul auteur ; invariants de convergence vérifiés à chaque exécution.

### 3.2 Merge à **deux co-parents** (coffre partagé) — V2 (piste spike, NON bloquant)
`[lié au SPIKE #4]`. N'existe pas en V1 (pas de coffre partagé, SECURITY §4). Tests écrits **avec** la feature, non bloquants tant que la stratégie de merge n'est pas figée (§8 piste spikes).
- **Deux co-parents hors-ligne** éditant le même coffre partagé, puis sync : aucun souvenir perdu, merge déterministe.
- **Édition concurrente de champs différents** (prénom vs tags) par **deux auteurs** : les deux gagnent (LWW par champ).

---

## 4. Tests d'échec partiel — injection de panne
Rattachement : ARCHITECTURE §5.

- Injecter une panne **entre l'upload du blob et le commit des métadonnées** : assert **pas d'orphelin visible**, **retry idempotent** (même UUID → pas de doublon), **original local non supprimé** tant que le self-check n'a pas réussi.
- **Self-check échoué simulé** (blob tronqué / clé de travers) : l'entrée n'est jamais marquée `committed`, jamais affichée, et un **beacon sans contenu** est émis.
- **Job balai** : un blob sans métadonnée committée est bien collecté après N heures ; un blob committé ne l'est jamais.

---

## 5. Fuzzing des edge cases
Rattachement : ARCHITECTURE §7.

- **Unicode** sur le chemin de rendu : surrogates cassées, zalgo, longueurs géantes, normalisation NFC. Assert : l'app de l'autre parent **ne plante pas** au rendu après déchiffrement.
- **Blobs** : vides, géants (refus à l'endpoint), corrompus, troncatures.
- **Dates** impossibles (31 février), limites de fuseau (souvenir à 23h Cayenne).
- **Entrées** : nulles, négatives, vides comme **états valides** à gérer (pas à planter).

---

## 6. Tests d'autorisation
Rattachement : SECURITY §2.3, §6.1, §6.3.

- **Co-parent retiré** (post-séparation) : ne peut plus récupérer les **nouveaux** blobs du coffre partagé ; la rotation SVK neutralise les ID pré-collectés.
- **Forge d'appartenance** : une requête « ajoute-moi au coffre X » sans action signée d'un membre existant est rejetée.
- **Accès inter-comptes** : un compte ne peut pas récupérer les blobs/clés d'un autre.
- **Auth** : pas de chemin « skip » biométrie ; backoff exponentiel actif ; aucun verrouillage dur exploitable en DoS.

---

## 7. Intégration CI

- **À chaque commit** : suites 1 (crypto) et 2 (invariants) **bloquantes** ; suites 3.1, 4, 5, 6 exécutées, échec = build rouge. **Non bloquants** : la suite 3.2 (merge co-parents V2) et la piste spikes (§8), tant que la feature V2 ou la décision n'est pas figée.
- **Pré-release** : suite complète + **canary** + surveillance du **taux d'échec de déchiffrement** et du **beacon self-check** (ARCHITECTURE §8) avant déploiement large. Comme le natif ne se hotfixe pas en 5 minutes, le canary est la dernière barrière avant de toucher tout le monde.
- **Couverture pondérée par le risque** : viser la quasi-exhaustivité sur crypto/sync/invariants ; ne pas courir après le pourcentage global sur l'UI.

---

## 8. Piste spikes (non bloquante, alimente les docs)
Rattachement : ARCHITECTURE §10.

| Spike | Test de validation | Finalise |
|-------|--------------------|----------|
| #1 Plan d'exécution | `EXPLAIN (ANALYZE, BUFFERS)` sur jeu représentatif ; assert index-only scan sur `(vault_id, seq)` | Schéma + index dans ARCHITECTURE §6 |
| #2 Burst resync | Banc de charge N appareils déversant plusieurs jours de média | Back-pressure / upload par lots |
| #3 Sync multi-appareils (même utilisatrice, V1) | Property-based un seul auteur (§3.1 ci-dessus) | Convergence déterministe ; version vectors dans ARCHITECTURE §3/§4 |
| #4 Merge offline deux co-parents (V2) | Property-based deux auteurs (§3.2 ci-dessus) | Stratégie de merge dans ARCHITECTURE §4 |

Boucle : prototype jetable → mesure → on réécrit la section concernée de `ARCHITECTURE.md` avec le fait, et on promeut le test de validation en test permanent si pertinent.
