# SECURITY.md

> Document constitutif — **version française canonique (fait foi)**. Il décrit *ce qui ne doit jamais être violé* et *pourquoi*.
> Toute fonctionnalité future qui contredit un invariant de §1 est refusée ou redessinée — pas négociée.
> Lecteurs visés : toi dans 6 mois, un prestataire, un auditeur externe, la CNIL.
> Note de langue : ce fichier (français) **fait foi**. Une traduction anglaise, destinée aux contributeurs open-source internationaux du noyau crypto, vit dans `SECURITY.en.md` — **générée depuis ce fichier, jamais éditée à la main** ; en cas de divergence, le présent fichier l'emporte.

---

## 1. Invariants (les murs porteurs)

Ces propriétés priment sur toute demande produit, tout confort d'UX, toute optimisation.
Si une feature exige d'en casser une, **la feature est le problème, pas l'invariant**.

1. **Le serveur ne peut jamais lire le contenu d'un souvenir.** Il ne stocke que des blobs chiffrés et des clés emballées illisibles sans la clé maîtresse de l'utilisateur, qu'il ne détient pas.
2. **L'opérateur n'a aucun mécanisme de récupération du contenu.** Il n'existe nulle part une voie par laquelle l'éditeur pourrait redonner accès aux données d'un utilisateur ayant tout perdu. (Conséquence directe : voir §7, le théorème de récupération.)
3. **La clé maîtresse (MIK) n'existe jamais en clair côté serveur, ni dans les logs, ni dans la télémétrie, ni dans une sauvegarde.**
4. **Aucune donnée de catégorie spéciale (santé : tag `maladie`, etc.) ne quitte l'appareil en clair, ni comme contenu, ni comme métadonnée.** Tout filtrage/recherche sur ces données est strictement local.
5. **Le noyau crypto est un module isolé, open-source, figé dans le binaire signé.** Jamais poussé en OTA (voir ARCHITECTURE.md). C'est lui qu'on audite ; il ne doit pas pouvoir changer dans le dos de l'utilisateur.
6. **Un souvenir n'est jamais affiché ni l'original local supprimé tant qu'un self-check de re-déchiffrement n'a pas confirmé qu'il est lisible** (anti-corruption silencieuse, voir ARCHITECTURE.md §5).
7. **Aucun secret serveur, aucune clé de test, aucune backdoor n'est embarqué dans le bundle client.**

> Convention de référence : ces invariants sont cités ailleurs comme **§1.1 à §1.7** (p. ex. §1.5 = le noyau crypto figé, §1.6 = le self-check). Ce sont des items de liste dans §1, pas des sous-sections distinctes.

Une suite de tests d'invariants (voir TESTING.md §2) rend ces propriétés *mécaniquement vérifiables* en CI. Un invariant qui n'est pas testé est un invariant qui dérivera.

---

## 2. Modèle de menace, par adversaire

La méthode : pour chaque adversaire, on dit explicitement **ce qu'on défend** et **ce qu'on ne défend pas**. Prétendre tout couvrir serait du théâtre de sécurité.

### 2.1 L'opérateur (nous-mêmes)
- **Défendu :** chiffrement de bout en bout (E2E). Le serveur ne voit que du chiffré. Un employé malveillant, un dump de base, une assignation : rien d'exploitable côté contenu.
- **Non défendu / accepté :** nous voyons des métadonnées techniques (existence d'un compte, volume de blobs, horodatage des syncs, taille des blobs — voir §6 canal auxiliaire). Nous minimisons mais ne supprimons pas tout.

### 2.2 Les attaquants externes (hackers)
- **Défendu :** contenu inutile même en cas de compromission totale du serveur. TLS + épinglage de certificat dans l'app native. Auth par passkeys. Anti-credential-stuffing par backoff exponentiel (pas de verrouillage dur — voir §6.3).
- **Non défendu :** la compromission de l'appareil déverrouillé de l'utilisateur lui-même (malware sur le téléphone du parent). Hors de portée de toute app grand public.

### 2.3 Le proche / ex-conjoint
- **Défendu :** modèle en double coffre (§4). À la séparation, retrait de l'accès aux nouveaux souvenirs **+ rotation de la clé du coffre partagé**, pour qu'un ex ayant scrappé des ID de blobs ne déchiffre rien après la rupture.
- **Non défendu / par construction impossible :** reprendre ce qui a déjà été déchiffré et vu. On ne « dé-déchiffre » pas le passé. La coupure ne vaut que pour le futur.
- **Non défendu volontairement :** nous n'arbitrons PAS la tutelle légale. Pas de vérification de jugement de divorce, pas de clawback décidé par un parent contre l'autre. Voir §4.3 pour pourquoi c'est un choix et pas une lacune.

### 2.4 L'État
- **Défendu :** réquisition de masse → ne livre que du chiffré illisible. Réquisition ciblée du serveur → l'épinglage de certificat et le code crypto figé/auditable limitent le MITM et le code piégé.
- **Non défendu, et il faut l'assumer par écrit :** un État qui cible *cet* enfant précis et compromet l'appareil du parent gagne. Aucune app grand public ne protège contre ça. Le natif élève le mur (binaire signé auditable vs JS resservi à chaque session) ; il ne rend pas insaisissable.
- **Dépendance résiduelle :** App Store / Play Store sont des points de confiance américains réquisitionnables qui livrent les mises à jour signées. Le natif déplace une partie du risque du serveur (qu'on contrôle) vers le store (qu'on ne contrôle pas). C'est un compromis assumé, pas une victoire totale.

---

## 3. Hiérarchie de clés

Trois étages, par emballage de clés (key wrapping). Jamais une clé unique dérivée du mot de passe.

```
Emballée EN PARALLÈLE par (chacune déballe la MÊME MIK) :
  • clé dérivée du mot de passe (Argon2id)
  • la clé locale de chaque appareil de confiance (Secure Enclave / Keystore, déverrouillée par biométrie)
  • Recovery Key (RK) ── Shamir 2-sur-3 répartie entre gardiens (voir §5)
        │
        ▼
Clé maîtresse d'identité (MIK)        ← synchronisée entre appareils de confiance,
        │                               JAMAIS en clair sur le serveur
        ├── emballe ──▶ Clé de coffre perso ──▶ emballe les clés de données ──▶ chiffrent chaque souvenir
        └── emballe ──▶ Clé de coffre partagé (voir §4)
```

- **Clé de données (DEK)** : une par souvenir, jetable, `XChaCha20-Poly1305`. Chiffre le blob.
- **Clé de coffre (VK)** : emballe les DEK du coffre. Permet de révoquer/partager au grain du coffre.
- **Clé maîtresse (MIK)** : le seul vrai secret de l'utilisateur. Emballe les VK. La MIK elle-même est emballée *en parallèle* par plusieurs clés (dérivée du mot de passe, locale par appareil, récupération) — chacune est une façon indépendante de déballer la même MIK.
- **Recovery Key (RK)** : une clé dédiée à haute entropie dont l'*unique* rôle est d'emballer une copie de la MIK. C'est la RK — **jamais la MIK directement** — qui est éclatée en Shamir entre les gardiens (§5). Indirection volontaire : changer de gardien, ou réagir à une part fuitée, revient à générer une nouvelle RK et à ré-emballer la MIK, **sans ré-chiffrer aucun souvenir** (même bénéfice structurel qu'un changement de mot de passe).
- **Dérivation depuis le mot de passe** : `Argon2id`. Changer de mot de passe re-chiffre la MIK seule, pas les souvenirs.
- **Bibliothèque** : `libsodium` exclusivement. Rien de maison, rien d'exotique. C'est ce que l'audit veut voir.

Bénéfices structurels : changer de mot de passe = re-chiffrer la MIK uniquement ; révoquer un partage = toucher une VK ; le serveur ne stocke que des blobs + clés emballées opaques.

---

## 4. Modèle co-parent : double coffre

> **Périmètre** : le persona primaire est solo (une mère seule). Le co-parent est une **couche optionnelle prévue en V2**, jamais un prérequis. En **V1, le coffre partagé n'existe pas** : tout est dans le coffre perso de l'utilisatrice, et la surface de menace exclut le partagé (§2.3 ne concerne que la V2). La section ci-dessous décrit le modèle cible une fois le co-parent introduit.

### 4.1 Principe
La clé du coffre partagé (SVK) est emballée **deux fois** : une fois sous la MIK du parent A, une fois sous la MIK du parent B. Chaque parent détient sur son appareil une copie de la SVK qu'il déballe avec *sa* clé — sans jamais accéder à la MIK de l'autre.

- Souvenir **commun** → chiffré avec la SVK → visible des deux.
- Souvenir **privé** → reste dans le coffre perso de son auteur → invisible à l'autre, par construction cryptographique.

### 4.2 Séparation
Opération triviale, sans arbitre :
1. On cesse d'emballer les **nouveaux** souvenirs sous la SVK.
2. Chacun garde sa copie de ce qui était commun (c'est physiquement chez lui, on ne le reprend pas).
3. **Rotation de la SVK** : la clé du coffre partagé est tournée côté serveur (révocation de l'accès aux blobs) ET cryptographiquement, pour neutraliser un ex ayant pré-collecté des ID.
4. Chacun continue son coffre perso.

### 4.3 Pourquoi pas d'arbitrage de tutelle (choix, pas lacune)
Nous n'avons aucun moyen fiable de vérifier qui est le tuteur légal (lire des jugements ? arbitrer une garde contestée ?). Le jour où nous nous trompons, nous donnons les souvenirs d'un enfant à un parent dont l'autre nous disait qu'il était dangereux. Le modèle double coffre évite entièrement le tribunal : pas de vérification, pas de clawback unilatéral (qui deviendrait une arme dans un divorce conflictuel), pas d'éditeur au milieu d'un conflit familial qu'il ne peut pas trancher.

### 4.4 Suppression par propriétaire, jamais par coffre
Un co-parent qui se désabonne/supprime n'efface QUE sa copie. La copie de l'autre survit. La « suppression définitive » du modèle éco (voir §8) est toujours scopée au propriétaire.

---

## 5. Récupération sociale (Shamir 2-sur-3)

C'est la **Recovery Key (RK, §3)** — jamais la MIK directement — qui est éclatée par partage de secret de Shamir : **3 parts confiées à des proches, 2 suffisent** à reconstituer. Flux de récupération : réunir 2 parts → reconstituer la RK → récupérer le blob opaque `MIK-emballée-sous-RK` → déballer → retrouver la MIK → ré-enrôler l'appareil. Personne seul ne peut rien faire avec une seule part.

**« L'opérateur n'est jamais dans la boucle »** signifie qu'il ne peut ni déclencher ni exécuter une récupération. Seul, il ne détient que le blob opaque `MIK-emballée-sous-RK` (cohérent avec le backend volontairement bête, ARCHITECTURE.md §1) et n'a aucune RK ; ce blob est inutile sans 2 parts de gardiens sur 3. L'opérateur n'est jamais l'un des gardiens. C'est le seul filet de secours compatible avec l'invariant §1.2 (pas de récupération opérateur).

Combiné à la synchro multi-appareils, il rend la perte quasi impossible : il faut perdre *tous* ses appareils d'un coup ET ne pas pouvoir réunir 2 gardiens sur 3.

**La remise des parts compte :** une part transmise en clair (SMS, e-mail) est une fuite. Les parts sont remises hors-bande / chiffrées — idéalement le gardien fait tourner l'app et stocke sa part sous sa propre clé. L'UX de configuration porte ce point (DESIGN_INTEGRATION.md §9).

**Deux pièges documentés :**
- **Piège familial** : si un gardien de part est l'ex-conjoint avec qui ça tourne mal, le filet devient une faille. → L'UX de configuration doit guider vers des gardiens *hors* du périmètre de conflit potentiel.
- **Piège UX** : demander à un jeune parent débordé de désigner 3 personnes de confiance est une marche haute. → À transformer en geste de soin (« qui veillera sur les souvenirs de votre enfant ? »), pas en corvée cryptographique. C'est un point de design critique (et un retour possible sur l'archi — voir ARCHITECTURE.md §10).

---

## 6. Ce que le serveur voit / ne voit jamais — et les fuites résiduelles

### 6.1 Permissions en contexte ZK
Le serveur ne peut PAS vérifier les permissions *de contenu* (il ne le lit pas). L'accès au contenu est **cryptographique** : tu vois un souvenir ssi tu peux déballer sa clé.

Mais il reste une **autorisation serveur indispensable à l'étage des blobs et des clés** : qui peut récupérer quel blob, déballer quelle clé emballée, écrire dans quel coffre. Elle DOIT être serveur — une autorisation seulement côté client (« on cache le bouton ») laisse un client malveillant demander des ID en direct. Scénario : à la séparation, si le serveur continue de servir les blobs du coffre partagé au parent B retiré, il aspire les nouveaux souvenirs. → Révocation serveur + rotation SVK (§4.2).

### 6.2 Canal auxiliaire : la taille des blobs
La taille des blobs fuit par deux canaux : le **type approximatif** (4 Mo = photo, 30 Ko = note — métadonnée acceptée, §2.1) et, surtout, l'**empreinte exacte** (la taille à l'octet près permet de tester « cet utilisateur détient-il *ce* fichier précis ? », un vecteur de dé-anonymisation).

Politique `[FIGÉ]` :
- **Padding par paliers de tous les blobs** sur une échelle géométrique modérée (*pas* des puissances de 2), appliqué **côté client avant chiffrement/upload**. Objectif : tuer l'empreinte exacte pour un surcoût de stockage borné. (L'échelle exacte des paliers est `[À VALIDER PAR SPIKE]` — calibrer surcoût réel vs représentativité, cf. ARCHITECTURE.md §6.)
- **Plancher commun pour les petits blobs de contenu** (note, mesure, citation, profil enfant) : parmi les petits items, on ne distingue plus *quel* type.
- **Scrub des logs** vers `type d'événement + ID opaque` ; **jamais** de log de changement d'appartenance avec des noms.

Assumé, pas défendu : la **classe média (photo/audio) vs texte** reste inférable de la taille — on ne padde pas une note jusqu'à la taille d'une photo (surcoût prohibitif, §10). On défend l'empreinte exacte et le type-parmi-les-petits, pas l'existence d'un média.

### 6.3 Auth contournable et déni de service auto-infligé
Pas de chemin « skip » sur le déverrouillage biométrique. Auth serveur par passkeys. Anti-stuffing par **backoff exponentiel, pas verrouillage dur** : comme il n'existe aucune récupération opérateur, un verrouillage dur permettrait à un attaquant de bloquer volontairement un parent dehors — la sécurité se retournerait en DoS contre nos propres utilisateurs.

### 6.4 En transit / au repos
- En transit : TLS + **épinglage de certificat** dans l'app native (compte vraiment vu la menace « serveur réquisitionné servant un MITM »).
- Au repos : blobs déjà chiffrés E2E ; **chiffrer aussi la base de métadonnées et ses sauvegardes**.

---

## 7. Le théorème de récupération (à assumer, pas à contourner)

Authentification ≠ chiffrement. La 2FA prouve *qui tu es* au serveur ; elle ne porte aucune clé de déchiffrement. Les facteurs transitoires (SMS, TOTP, code mail) ne peuvent pas porter de clé stable ; la biométrie ne fait que déverrouiller une clé *déjà présente sur cet appareil*.

Conséquence : **« l'opérateur ne peut pas lire » et « l'opérateur me redonne accès si j'oublie tout » sont mutuellement exclusifs.** Multiplier les chemins de récupération multiplie les surfaces d'intrusion (SIM-swap sur le SMS, accès à la boîte mail…) : la sécurité réelle tombe au niveau du facteur le plus faible.

Notre choix : **synchro multi-appareils (la perte d'un appareil est un non-événement) + récupération sociale Shamir (le cas catastrophe).** Pas de séquestre opérateur. La perte simultanée de tous les appareils ET de la capacité à réunir 2 gardiens sur 3 entraîne une perte définitive — c'est le prix, assumé et explicité à l'utilisateur, de l'invariant §1.2.

---

## 8. Posture réglementaire et anti-abus

### 8.1 RGPD / CNIL
- **AIPD (analyse d'impact)** : de facto obligatoire ici (traitement systématique de données d'enfants, catégorie spéciale). À produire. Le ZK est notre meilleur argument : ce qu'on ne peut pas lire ne peut être ni détourné, ni fuité, ni réquisitionné côté contenu.
- **Minimisation comme principe directeur** : la donnée la plus irréprochable est celle qu'on ne collecte pas. Pas de vrai nom d'enfant requis (prénom/surnom/emoji), année plutôt que date exacte si la timeline le permet, compte parent pseudonyme autant que possible, paiement séparé du contenu (le prestataire qui voit la CB ne voit jamais le coffre), strip EXIF systématique à la capture (la géoloc = « cet enfant était à tel hôpital tel jour »), **profils enfants et appartenance à un enfant chiffrés** (le prénom et la date de naissance complète de chaque enfant sont conservés comme contenu chiffré ; le serveur ignore le nombre d'enfants, leurs noms, leurs dates de naissance et la répartition des souvenirs — filtrage 100 % local, cf. `DESIGN_INTEGRATION.md §2` et §2.1).
- **Marché et juridiction** : lancement sur le **marché français (donc UE)**. Autorité de contrôle : **CNIL**. RGPD applicable, AIPD attendue. **Hébergement recommandé en UE** : les blobs sont chiffrés E2E, mais la juridiction et les métadonnées, elles, ne le sont pas — l'hébergement UE compte vu la menace « État » (§2.4) et évite l'exposition au cadre extra-européen. La **structure juridique** exacte responsable de traitement reste à déterminer ; la juridiction, elle, est fixée.

### 8.2 Vérification d'âge (tension assumée avec la minimisation)
C'est le seul endroit où minimisation et protection de l'enfant tirent en sens inverse. Décision : **gate principal par le paiement** (un abonnement annuel payant suppose un moyen de paiement, donc un majeur, sans collecte d'ID supplémentaire) + auto-déclaration en complément. **Refus de la vérification d'identité tierce** (elle détruit l'anonymat et nous crée une base d'identités à protéger — l'inverse de l'irréprochable). Le mur payant fait déjà une partie du travail ; nous ne sommes pas un réseau social ouvert et gratuit.

### 8.3 Contexte CSAR / « Chat Control » et prévention d'abus
Un coffre E2E de photos d'enfants est précisément l'architecture au centre du débat réglementaire européen. État des lieux (à réactualiser, le dossier bouge) : la dérogation temporaire autorisant le scan volontaire (« Chat Control 1.0 ») a expiré début avril 2026 ; le règlement permanent (CSAR / « Chat Control 2.0 ») reste en négociation, l'obligation de scan côté client ayant pour l'instant été écartée au profit d'un régime d'**évaluation des risques + mesures d'atténuation raisonnables + vérification d'âge**. Notre service (hébergement de photos, partage entre co-parents) tombe dans le périmètre des obligations d'atténuation.

Conséquence directe et inconfortable à assumer : en ZK, **nous nous rendons délibérément incapables d'inspecter le moindre contenu** — donc de détecter un abus sur notre propre plateforme. Ce n'est pas une faille, c'est la conséquence logique exacte du E2E. Position écrite, à verser à l'AIPD :
- **Vérification d'âge** à l'inscription (§8.2).
- **Limitation du partage au strict cercle co-parental** : pas de partage public, pas de diffusion large ; le coffre partagé est borné à deux parents.
- **Mécanisme de signalement** utilisateur, non intrusif (ne casse pas le ZK).
- Documentation de *pourquoi* l'architecture est légitime et à qui elle s'adresse (familles, conservation privée longue durée), au titre de l'évaluation des risques attendue.

### 8.4 Cibles de conformité technique et engagement d'audit
- **OWASP MASVS** niveau L2 + résistance au reverse comme référentiel mobile nommé (checklist vérifiable, pas une intention vague).
- **Noyau crypto open-source + audit externe indépendant budgété.** L'irréprochabilité ne se décrète pas, elle se laisse vérifier : sans audit, « zero-knowledge » est une affirmation aussi invérifiable que celle de n'importe qui.

---

## 9. Survivabilité (une promesse à 15 ans)
Un « coffre-fort » est une promesse longue. Si la structure ferme, la promesse ne doit pas mourir avec elle : **formats ouverts, export garanti et automatique** côté client (l'export/album ne peut être généré que là où la clé existe, jamais côté serveur). Une conservation longue qui dépend de la survie d'un indépendant est *sincère*, pas *irréprochable* — la différence se comble par l'export ouvert.

---

## 10. Modèle éco (rappel des implications sécurité)
Abonnement annuel. Désabonnement → consultation seule **3 ans**, puis suppression définitive **par propriétaire** (§4.4) avec proposition de remise propre des données (export, voire album papier généré côté client — fonctionnalité ultérieure, mais l'export ouvert est prévu dès le départ pour tenir la survivabilité §9). Le stockage des blobs chiffrés de non-payeurs a un coût réel (le chiffré ne se déduplique ni ne se compresse) : c'est une ligne de P&L, pas un détail.
