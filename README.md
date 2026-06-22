# Handoff : souvenir — Coffre-fort numérique à souvenirs d'enfant

## Overview
Application mobile (iOS / Android) où les parents **déposent puis redécouvrent** les souvenirs de leurs enfants (fratrie). L'expérience émotionnelle prime : tendre, nostalgique, on doit aimer y revenir. Trois mécaniques de redécouverte : une **Frise** chronologique, un **Souvenir surprise du jour** (« il y a 3 ans, aujourd'hui… »), et un **Arbre** par enfant qui grandit avec lui.

## About the Design Files
Les fichiers `.dc.html` de ce bundle sont des **références de design créées en HTML** — des prototypes qui montrent l'apparence et le comportement visés, **pas du code de production à copier tel quel**. Ils s'appuient sur un petit runtime maison (`support.js`, balises `<x-dc>`, `<sc-if>`, `<sc-for>`, classe `Component extends DCLogic`) qui n'a pas vocation à être réutilisé.

La tâche est de **recréer ces designs dans l'environnement du codebase cible** (React Native, Expo, Flutter, SwiftUI, etc.) en suivant ses patterns établis. Si aucun environnement n'existe encore, choisir le framework le plus adapté à une app mobile riche en animations (recommandation : **React Native + Expo**, ou **SwiftUI** si iOS-only) et y implémenter les designs.

Pour visualiser un prototype : ouvrir le `.dc.html` dans un navigateur (il charge `support.js` à côté). `Souvenir - Prototype.dc.html` est la **référence d'interaction** la plus complète.

## Fidelity
**Mixte — deux niveaux fournis :**
- **Hi-fi** : `Souvenir - Prototype.dc.html` et `Souvenir - Frise éditoriale.dc.html` — couleurs, typo, espacements et interactions finaux. À **recréer fidèlement**.
- **Lo-fi** : `Souvenir - Wireframes.dc.html` — storyboard filaire (structure + flux). Sert de carte mentale des écrans et de la navigation.

En cas de doute sur un détail visuel, **le hi-fi fait foi** ; le wireframe fait foi pour la structure/les flux.

---

## Système de design

### Typographie
| Usage | Police | Détails |
|---|---|---|
| Titres, noms, accents | **Instrument Serif** (Google Fonts) | regular + italic ; grands corps (24–84px) ; line-height serré (~1.0–1.05) |
| Interface, corps, libellés | **Hanken Grotesk** (Google Fonts) | 400/500/600/700 ; corps 13–17px, line-height 1.5–1.62 |
| Métadonnées, dates, étiquettes | **Geist Mono** (Google Fonts) | 9–11px, MAJUSCULES, `letter-spacing` .1–.22em, couleur sourde |

### Couleurs (tokens)
```
--paper            #f7f2ec   /* fond principal (papier crème) */
--paper-alt        #f4eee5   /* fond haut de l'écran Arbre (dégradé vers --paper) */
--ink              #3b3340   /* texte principal / éléments sombres pleins */
--ink-soft         #5e5862   /* corps de texte */
--text-muted       #6b6470
--text-faint       #9a9088 / #a89c8e / #b3a591  /* métadonnées, dégradés de gris chaud */
--accent           #c08a72   /* terracotta : actif, lecture audio, point actif */
--surface          #ffffff   /* cartes */
--chip             #ece4d8   /* puces / pastilles inactives */
--divider          #e2d8c9

/* Pastels souvenirs (dégradés de vignettes/photos) */
--rose    #f1c8d4    --lilas  #c9c2ee    --bleu   #bcd6ee
--vert    #c4ddcb    --jaune  #f0dfae    --peche  #f4cdb6
```
Avatars : `linear-gradient(135deg, …)` de deux pastels (Léa = rose→lilas, Noé = bleu→vert).
Photos (placeholder) : dégradé pastel + sur-couche `repeating-linear-gradient(135deg, rgba(255,255,255,.14) 0 16px, transparent 16px 32px)` — **à remplacer par de vraies photos**.

### Formes & élévation
```
radius : cartes 26px · vue immersive sheet 32px · vignettes 16px · feuilles d'ajout 20px · pastilles/onglets 100px
shadow carte      : 0 14px 30px -16px rgba(80,50,60,.28)
shadow téléphone  : 0 30px 60px -20px rgba(60,40,60,.4)
shadow douce      : 0 1px 3px rgba(0,0,0,.05)
```

### Liquid Glass — **strictement limité à la barre du bas**
Seul élément en verre dépoli. Recette :
```
background: rgba(255,255,255,.55);
backdrop-filter: blur(22px) saturate(1.5);   /* + -webkit- */
border: 1px solid rgba(255,255,255,.7);
border-radius: 100px;
box-shadow: 0 12px 30px -8px rgba(80,50,60,.22);
```
**Ne pas** étendre l'effet de verre au reste de l'app (le reste est mat).

### ⚠ Règles non négociables
- **Aucun émoji / smiley.** Uniquement des **icônes au trait fines** (stroke ~1.6–1.8, `currentColor`, style Lucide/Feather). Les pictos du bundle sont des `<svg>` inline réutilisables.
- Le verre dépoli **ne sert que** pour la barre de navigation du bas.
- Beaucoup d'air, ton éditorial, ça doit « respirer ».

---

## Écrans / Vues

### A. Frise (accueil, niveau 1)
- **But** : point d'entrée ; voir le souvenir surprise du jour + la frise récente de l'enfant sélectionné.
- **Layout** (de haut en bas, padding latéral 26px, zone scrollable sous la status bar 54px) :
  1. **En-tête** : ligne mono `MARDI 22 JUIN` + titre serif `Bonjour, Camille` ; à droite, bouton réglages rond 40px (`#ece4d8`, icône « sliders »).
  2. **Sélecteur d'enfant** : pastilles 100px — enfant actif = fond `#3b3340` texte blanc ; inactif = fond `#ece4d8` texte `#6b6470` ; avatar rond 28px en dégradé. Suivi d'un bouton `+` rond 40px (bordure pointillée) → ajouter un enfant.
  3. **Carte Souvenir surprise** (cliquable → écran C) : carte blanche radius 26px ; photo 188px avec badge verre sombre `IL Y A 3 ANS · AUJOURD'HUI` (mono 10px) en haut-gauche et légende mono en bas-droite ; corps = titre serif 24px + sous-titre 13.5px `#7a7280`.
  4. **Section** : libellé mono `CETTE SEMAINE`.
  5. **Timeline verticale** : trait 1.5px `#e2d8c9` à gauche ; chaque entrée (cliquable → C) = pastille colorée 11px (couleur = type) + date mono + ligne[vignette 66px radius 16px | titre serif 19px + méta 12px]. **Citation** = pas de photo, grand guillemet serif `"` sur fond pastel.
- **Barre du bas** (voir Navigation).

### B. Arbre (niveau 1)
- **But** : vue « vivante » de la croissance de l'enfant ; jalons fleuris + stats.
- **Layout** : fond dégradé `#f4eee5`→`#f7f2ec`.
  1. Titre centré : mono `L'ARBRE DE` + prénom serif 32px.
  2. **Arbre** (formes simples, ~400px) : tronc (dégradé brun, radius 12px), 2 branches inclinées, 3–4 cercles de feuillage pastel superposés (vert/lilas/pêche/jaune, `radial-gradient`).
  3. **Jalons = pastilles** : cercle blanc 16px cerclé d'une couleur pastel (3px), **sans pictogramme**. Le **jalon actif** = pastille terracotta `#c08a72` 22px + **étiquette éditoriale** reliée (carte blanche : âge mono + libellé serif). Cliquable → écran C.
  4. **Deux cartes stats** côte à côte (blanches, radius 18px) : `TAILLE — 78 cm` et `SOUVENIRS — 142 éclats` (label mono + valeur serif 26px).
- **Barre du bas** : onglet « Arbre » actif.

### C. Souvenir — vue immersive ⭐ (modale, écran PRIORITAIRE)
- **But** : revivre un souvenir en plein écran ; lire la note vocale ; aimer.
- **Présentation** : monte depuis le bas par-dessus l'écran courant (`translateY 102%→0`, `transition .42s cubic-bezier(.4,0,.2,1)`).
- **Layout** :
  1. **Grande photo ~430px** (dégradé pastel + rayures). En surimpression à 54px du haut : bouton **retour** `‹` (rond 38px, verre léger `rgba(255,255,255,.6)` + blur 8px) à gauche ; **cœur** ❤ à droite (même style ; rempli `#c08a72` quand liké). Légende mono en bas-droite.
  2. **Feuille éditoriale** crème (radius haut 32px, chevauche la photo) : date+âge mono `#b3a591` → titre serif 36–38px → note (corps 15px, line-height 1.62, `#5e5862`).
  3. **Lecteur de note vocale** (si présent) : carte blanche radius 20px = bouton play/pause rond 42px terracotta + **forme d'onde** (≈14 barres 3px) qui **se remplit en terracotta** selon la progression + durée mono. Légende dessous : `la voix de Léa` (12px `#a89c8e`).
  4. **Jalon** (si présent) : puce `#ece4d8` radius 100px, icône « pousse » au trait verte + texte.
- **États à gérer** : audio play vs pause (icône + remplissage de l'onde) ; liké vs non (cœur rempli/vide) ; souvenir avec photo vs **citation sans photo** ; présence ou non de note vocale / de jalon.

### D. Feuille d'ajout (＋, modale)
- **But** : choisir le type de souvenir à enregistrer.
- **Présentation** : bottom-sheet (`translateY 100%→0`, `.4s`) + voile `rgba(28,22,30,.32)` (fade .3s) ; **tap sur le voile = fermer**.
- **Layout** : poignée 44×5px ; titre serif `Garder un souvenir` + sous-titre `de {enfant} — aujourd'hui` ; **grille 3×2** de 6 tuiles blanches (radius 20px) : **Photo · Note vocale · Citation · Jalon · Mesure · Dessin**, chacune = icône au trait colorée + libellé. (Les tuiles ferment la feuille dans le proto ; à brancher sur les vrais flux de capture.)

---

## Interactions & Behavior
- **Onglets Frise ⇄ Arbre** : bascule l'écran de niveau 1 ; l'onglet actif passe en serif sombre, l'inactif en `#b3a591`.
- **Ouvrir un souvenir** (carte surprise / entrée de frise / pastille-jalon) → écran C monte du bas. `‹` redescend.
- **Like** : toggle, cœur se remplit en `#c08a72`.
- **Lecture audio** : play → progression simulée (`setInterval ~90ms`, +0.022/tick) ; les barres d'onde passent en terracotta proportionnellement ; pause/fin gèle l'état. À remplacer par un vrai lecteur audio.
- **＋** (barre du bas, présent sur A et B) → ouvre la feuille D.
- **Changer d'enfant** (Léa/Noé) → recharge surprise + frise + arbre + stats. Bouton `+` du sélecteur → ajout d'un enfant.
- **Transitions** : `cubic-bezier(.4,0,.2,1)`, ~.3–.42s ; voiles en `ease`.

## State Management
```
screen   : 'frise' | 'arbre'          // onglet niveau 1
child    : 'lea' | 'noe' | …           // enfant sélectionné, recharge tout le contenu
openId   : id du souvenir ouvert | null  // null = écran C fermé
addOpen  : bool                        // feuille D
playing  : bool                        // lecture audio
progress : 0..1                        // progression audio → remplissage de l'onde
liked    : { [memoryId]: bool }
```
- Données : liste de souvenirs filtrée par `child` ; un souvenir « surprise » + N entrées de frise par enfant.
- Données par enfant pour l'Arbre : nom, jalon actif (id, libellé, âge), taille, nombre de souvenirs (« éclats »).
- **Fetch réel à prévoir** : souvenirs (photo/audio/texte/jalon/mesure/dessin) par enfant ; le « surprise du jour » = requête sur la date anniversaire (même jour, années précédentes).

## Modèle de données (souvenir)
```
id, child, type(photo|voice|citation|jalon|mesure|dessin),
date, ageLabel, title, note,
photo?, audio?{url,durée}, milestone?, measure?{type,valeur,unité},
isSurprise(bool), liked(bool)
```

## Design Tokens
Voir la section **Système de design** ci-dessus (couleurs, typo, radius, ombres, recette du verre). Espacements observés : padding écran 26px ; gaps 8–14px ; rythme vertical des sections 16–28px.

## Assets
- **Polices** : Instrument Serif, Hanken Grotesk, Geist Mono (Google Fonts — à charger via le système de polices du codebase).
- **Icônes** : jeu d'icônes au trait (style Lucide/Feather). Dans le bundle ce sont des `<svg>` inline ; côté app, utiliser la lib d'icônes du codebase. Pictos utilisés : sliders/réglages, plus, retour (chevron), cœur, micro, play/pause, pousse (jalon), appareil photo, règle/mesure, crayon (dessin), guillemet serif (citation), nav (liste / arbre).
- **Photos** : aucune fournie — placeholders rayés. À remplacer par les photos réelles des utilisateurs.
- **Aucune marque tierce.**

## Files (dans ce bundle)
| Fichier | Rôle | Fidélité |
|---|---|---|
| `Souvenir - Prototype.dc.html` | **Prototype cliquable** — référence d'interaction principale (états, navigation, audio, ajout, multi-enfants) | hi-fi |
| `Souvenir - Frise éditoriale.dc.html` | 3 écrans statiques de la piste retenue (Accueil, Souvenir, Arbre) | hi-fi |
| `Souvenir - Wireframes.dc.html` | Storyboard filaire + carte des flux | lo-fi |
| `Souvenir - Explorations 3 pistes.dc.html` | Exploration initiale (Frise / Liquid Glass / Jardin) — contexte uniquement | hi-fi |
| `DESIGN.md` | Synthèse design (intention, système, écrans, flux) | — |
| `support.js` | Runtime des prototypes — **référence d'exécution uniquement, ne pas porter** | — |

> Pour lire un proto : ouvrir le `.dc.html` dans un navigateur (les polices se chargent depuis Google Fonts, `support.js` doit être dans le même dossier).
