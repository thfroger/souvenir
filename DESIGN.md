# souvenir — Coffre-fort numérique à souvenirs d'enfant

> Document de référence design, en vue de produire les **wireframes**.
> Application mobile (iOS / Android) où les parents **déposent puis redécouvrent** les souvenirs de leurs enfants.

---

## 1. Intention

Un coffre-fort **tendre et nostalgique** où l'on aime passer du temps à découvrir et redécouvrir le passé. L'expérience prime : ça doit respirer, émouvoir, donner envie de revenir.

**Métaphore centrale, en trois temps :**
1. **La Frise** — une chronologie intime qui se déroule, lue comme un magazine.
2. **Le Souvenir surprise du jour** — « il y a 3 ans, aujourd'hui… ».
3. **L'Arbre** — un arbre par enfant, qui grandit ; les jalons y fleurissent.

**Multi-enfants (fratrie)** : Léa & Noé dans la maquette. Sélecteur d'enfant toujours accessible.

---

## 2. Direction visuelle

**Piste retenue : Frise éditoriale.** Papier crème, beaucoup d'air, icônes au trait fines.

| Élément | Choix |
|---|---|
| Ambiance | Pastel éditorial, tendre, premium, mat |
| Verre dépoli (Liquid Glass iOS 26) | **Réservé à la barre du bas flottante** — une touche, pas une ambiance |
| Émojis / smileys | **Interdits** — uniquement des icônes au trait fines |
| Imagerie | Photos réelles (placeholders rayés en diagonale dans la maquette) |

### Typographie
- **Instrument Serif** — titres, noms, accents éditoriaux (souvent en italique pour la nuance).
- **Hanken Grotesk** — interface, corps de texte, libellés.
- **Geist Mono** — métadonnées, dates, étiquettes (lettres espacées, MAJUSCULES).

### Palette
| Rôle | Couleur |
|---|---|
| Fond papier | `#f7f2ec` |
| Fond alterné (arbre) | `#f4eee5` |
| Encre / texte | `#3b3340` |
| Texte secondaire | `#6b6470` / `#9a9088` |
| Accent chaud (actif, audio) | `#c08a72` (terracotta) |
| Pastels souvenirs | rose `#f1c8d4` · lilas `#c9c2ee` · bleu `#bcd6ee` · vert `#c4ddcb` · jaune `#f0dfae` · pêche `#f4cdb6` |
| Carte / surface | `#fff`, ombres très douces |

### Formes
- Coins très arrondis (cartes 26px, vignettes 16px, pastilles 100px).
- Ombres basses et diffuses, jamais dures.
- Photos = dégradés pastel rayés en placeholder.

---

## 3. Écrans

### A. Frise (accueil)
- **En-tête** : date du jour (mono), « Bonjour, Camille » (serif), icône réglages.
- **Sélecteur d'enfant** : pastilles Léa / Noé (l'actif en sombre plein) + bouton `+` pour ajouter un enfant.
- **Carte Souvenir surprise** : grande photo, badge « IL Y A 3 ANS · AUJOURD'HUI », titre serif + sous-titre. Cliquable → vue immersive.
- **Section « Cette semaine »** : timeline verticale (trait + pastilles colorées), chaque entrée = vignette 66px + titre serif + méta (type, durée audio). Les citations affichent un grand guillemet serif au lieu d'une photo.

### B. Souvenir — vue immersive *(écran prioritaire)*
- Monte depuis le bas par-dessus l'écran courant.
- **Grande photo** (≈430px) avec, en surimpression : bouton **retour** (‹) et **cœur** ❤ (verre léger).
- **Panneau éditorial** (feuille crème arrondie) : date + âge (mono), grand titre serif, note manuscrite (corps).
- **Lecteur de note vocale** : bouton play/pause terracotta + forme d'onde animée qui se remplit + durée. Légende « la voix de Léa ».
- **Jalon** éventuel : pastille avec icône « pousse » au trait.

### C. Arbre
- Titre « L'ARBRE DE » + prénom (serif).
- **Arbre dessiné en formes simples** : tronc, branches, 3–4 feuillages pastel superposés.
- **Jalons = pastilles pastel** (cerclées de couleur, **sans émoji**) ; le jalon actif est terracotta plein, relié à une **étiquette éditoriale** (âge + libellé). Cliquable → vue immersive.
- **Deux cartes statistiques** : `TAILLE — 78 cm` · `SOUVENIRS — 142 éclats`.

### D. Feuille d'ajout (＋)
- Bottom sheet (poignée, titre « Garder un souvenir », sous-titre « de Léa — aujourd'hui »).
- **Grille 6 types**, chacun une icône au trait colorée : **Photo · Note vocale · Citation · Jalon · Mesure · Dessin**.
- Voile sombre derrière ; se ferme en tapant à côté.

---

## 4. Navigation

```
        ┌──────────────── Barre de verre flottante (bas) ────────────────┐
        │   « Frise »        (  ＋  )        « Arbre »                     │
        └────────────────────────────────────────────────────────────────┘
Frise ⇄ Arbre  (onglet, actif en serif sombre / inactif beige)
  ＋  → Feuille d'ajout (modale du bas)
Toute carte / entrée / pastille-jalon → Souvenir immersif (monte du bas, ‹ pour fermer)
Sélecteur Léa / Noé → recharge Frise + Arbre + Surprise
```

Le bouton `+` central reste constant sur Frise et Arbre. La barre est le **seul** élément en verre dépoli.

---

## 5. Types de contenu d'un souvenir
Photos · Notes vocales / sons (rires, premiers mots) · Citations / phrases drôles · Jalons (1er sourire, 1ère dent, 1er pas…) · Dessins / créations scannés · Mesures (taille, poids) · *(à venir : lettres écrites à l'enfant pour plus tard)*.

---

## 6. Notes pour les wireframes
- Garder la **hiérarchie**, pas le style : la version filaire doit montrer structure, zones et flux, pas les couleurs.
- Bien marquer les **3 entrées vers la vue immersive** (surprise, frise, jalon-arbre).
- La barre du bas (Frise · ＋ · Arbre) est persistante sur les écrans de niveau 1 (Frise, Arbre), masquée/derrière sur les modales (Souvenir, Ajout).
- Prévoir l'**état multi-enfants** : montrer le sélecteur et le fait que tout le contenu se recharge.
- États à wireframer : audio en lecture vs pause, souvenir liké vs non, citation (sans photo) vs photo.

---

## 7. Fichiers du projet
| Fichier | Rôle |
|---|---|
| `Souvenir.dc.html` | Exploration initiale — 3 pistes comparées |
| `Souvenir - Frise éditoriale.dc.html` | Piste retenue, statique (3 écrans) |
| `Souvenir - Prototype.dc.html` | **Prototype cliquable** (référence d'interaction) |
