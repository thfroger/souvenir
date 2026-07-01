# STORE_COMPLIANCE.md — souvenir

> **Status: DRAFT — Verification Protocol §9 run 2026-07-02; STATUS column filled; still unratified.**
> Canonical language: English (same rule as SECURITY.md). A frozen French archive MAY be produced after ratification, never before.
>
> **Instruction to the agent (Claude Code):** this document was drafted *outside* the repository, from the project's constitutional decisions. Before treating anything here as ratified you MUST run the Verification Protocol in §9. Every cross-reference written as `SECURITY.md §x` / `TESTING.md §x` / `ARCHITECTURE.md §x` is a **candidate reference**: resolve it against the actual live documents, fix the section number if it drifted, and flag any reference that resolves to nothing. Every row of the coherence table (§8) carries a `STATUS` field you must fill: `VERIFIED`, `TODO`, `BROKEN`, or `N/A (no code yet)`.

> **Verification log — 2026-07-02 (§9 run).** References all resolve (no broken `§`). Dependency audit clean: the only third-party dependency is swift-sodium; no analytics/crash/ads/ML/speech SDK; Android not yet coded. Owner decisions taken this pass: **(1) no account email in V1** — identity is device-bound (passkey-equivalent) + vault (D1 rewritten below); **(2) no telemetry in V1** (analytics + crash reporting: none → N5/N6 hold); **(3)** remaining §7 business/legal items left explicitly *to be decided* (IP retention, trader address, price, break-even). Material findings: **C8/D4 — padding is `[FIGÉ]` in SECURITY §6.2 but NOT implemented in code**, so "mitigated by padding" over-claims today; **N2/C3 — no explicit ML/perceptual-hashing prohibition exists in SECURITY.md** (amendment proposed in §10); **N1/C9 — EXIF stripping is specified in SECURITY §8.1 (not a §1 invariant) and implemented (`ImageTools.stripExifJPEG`) but had no test** (a static guard is now in CI; a runtime test needs an iOS test target). See §8 for per-row STATUS and §10 for proposed amendments.

---

## 0. Purpose and precedence

This document is the single source of truth for everything souvenir declares to Apple (App Store Connect) and Google (Play Console), and for the French/EU legal obligations attached to distributing the app.

Its founding principle is **triple coherence**:

1. what the code actually does (enforced by SECURITY.md invariants and TESTING.md CI blockers),
2. what we declare in Apple Privacy Nutrition Labels / Google Data Safety,
3. what we declare for encryption export compliance (Apple) and French cryptology regulation (ANSSI).

If any two of the three diverge, the release is blocked. Divergence is a CI-visible failure, not a review-time discovery.

**Precedence:** SECURITY.md invariants win over this document. This document wins over any store form filled by hand. If a store questionnaire forces an answer that contradicts SECURITY.md, the resolution is architectural (change the code or change the invariant through the amendment process), never declarative (lie on the form).

**Non-negotiable agent constraints (extends CLAUDE.md):**
- The agent MUST NOT answer any store questionnaire, plist key, or manifest attribute from memory or convention. Every answer derives from a row in §8.
- The agent MUST NOT add any SDK, analytics, crash reporter, or third-party dependency without adding the corresponding row(s) to §2 and §8 in the same commit. A dependency that collects data without a declaration row is a `BROKEN` state.
- "Zero-knowledge" is a claim about **content**, never about **metadata**. The agent MUST NOT declare "no data collected" anywhere. See §2.

---

## 1. Compliance posture summary

| Domain | Posture | Source |
|---|---|---|
| Content confidentiality | Zero-knowledge E2E: XChaCha20-Poly1305, Argon2id, libsodium; three-tier key hierarchy (DEK → VK → MIK); Shamir 2-of-3 social recovery | SECURITY.md §1 (invariants), key hierarchy section |
| Data subject specifics | Photos/voice notes of minors; child assignment encrypted server-side; child-as-future-adult posture | SECURITY.md (regulatory posture: GDPR, DPIA, CSAR context) |
| Platform | Native SwiftUI (iOS) + Kotlin/Jetpack Compose (Android); no cross-platform crypto layer | ARCHITECTURE.md |
| Monetization | Annual subscription 9.90 €/year; unsubscribe → 3-year read-only, then owner-driven permanent deletion | SECURITY.md §10 (business model) |
| Audit commitment | OWASP MASVS L2 + resiliency; open-source crypto core; budgeted independent external audit | SECURITY.md §8.4 |
| Supervisory authority | CNIL; EU hosting recommended | SECURITY.md (regulatory posture) |

---

## 2. Declared data inventory (single source of truth)

This inventory feeds §3 (Apple) and §4 (Google) mechanically. Nothing may appear in a store form that does not appear here first.

**Critical framing:** souvenir's server never has access to memory *content* (photos, voice notes, texts, child identity semantics). It necessarily has access to *operational* data. The honest declaration is therefore "data collected, encrypted in transit, content not readable by operator" — never "no data collected".

### 2.1 Data the server necessarily holds

| # | Data | Purpose | Linked to identity? | Content-readable by operator? | Retention |
|---|---|---|---|---|---|
| D1 | Device credential: a P-256 **public** key + credential id, bound to a vault (passkey-equivalent auth) — **no account email in V1** | **Authentication only** — never key recovery (SECURITY.md §7) | Yes (identifies the device/vault) | Yes, but it is a *public* key, not a secret | Life of vault | 
| D2 | Subscription state / store transaction identifiers | Billing, entitlement | Yes | Yes | Life of account + accounting legal retention |
| D3 | Encrypted blobs (memories) | Storage/sync | Yes (account-linked) | **No** (ciphertext only, invariant-protected) | Life of account + 3y read-only + deletion (SECURITY.md §4.4) |
| D4 | Sync metadata: blob count, sizes, timestamps, version vectors | Sync correctness, conflict resolution | Yes | Partially (sizes/timing are metadata leakage — mitigated by padding, see SECURITY.md padding decision) | Operational |
| D5 | Child assignment record (encrypted server-side) | Vault organization | Yes (account-linked) | **No** (encrypted) | Life of account |
| D6 | IP addresses / connection logs | Security, abuse prevention, legal obligation | Yes | Yes | Short rotation — **DECISION NEEDED: define exact retention (proposal: 12 months max, LCEN-compatible)** |
| D7 | Device/app version identifiers sent on sync | Compatibility, security patching | Yes | Yes | Operational |

### 2.2 Data explicitly NOT collected (negative declarations — must stay true)

| # | Not collected | Guarded by |
|---|---|---|
| N1 | Photo content, EXIF after client-side stripping, thumbnails in clear | SECURITY.md invariant — **agent: identify which invariant number and whether EXIF stripping is actually specified; if not specified, this is a gap to raise** |
| N2 | Face vectors, perceptual hashes, ML-derived features of any kind | Constitutional differentiation vs FamilyAlbum precedent — **agent: verify an invariant or explicit prohibition exists in SECURITY.md; if absent, propose amendment** |
| N3 | Advertising identifiers (IDFA / AD_ID) | No ads business model. Android: verify no transitive SDK injects `com.google.android.gms.permission.AD_ID`; if any does, add `tools:node="remove"` in manifest |
| N4 | Voice transcriptions | Whisper explicitly removed from scope — record/playback only |
| N5 | Analytics / behavioral tracking | **DECIDED 2026-07-02: none in V1** (no analytics SDK; dependency audit enforces this in CI). Usage Data / App activity declared Not collected. If ever added, amend §2.1/§3/§4/§8 in the same commit. |
| N6 | Crash reports containing user content | **DECIDED 2026-07-02: none in V1** (no crash-reporter SDK). Diagnostics declared Not collected (§3.1, §4.1). Revisit ⇒ amend §2.1/§3/§4/§8 in the same commit. |
| N7 | Account email / password (V1) | **Accountless in V1** (owner decision 2026-07-02): identity is a device-bound P-256 keypair (passkey-equivalent, SECURITY.md §6.3) + vault, plus passphrase/Shamir for key recovery. No email is held for auth or key recovery (the latter would violate §7). Email may reappear ONLY if store billing later requires a contact — never as a recovery path. If added, amend §2.1/§3.1/§4.1/§8 in the same commit. |

---

## 3. Apple — App Store Connect declarations (draft answers)

### 3.1 Privacy Nutrition Labels

Derived from §2. Category mapping:

| Apple category | Answer | Source rows |
|---|---|---|
| Contact Info → Email Address | **Not collected in V1** (accountless — N7). Revisit only if store billing later requires a contact. | N7 |
| User Content → Photos or Videos / Audio Data | **Collected** (stored as ciphertext), linked to identity (account), used for App Functionality. Not used for tracking. **Do not omit this category**: Apple's definition of "collected" includes transmitted-and-stored data even if E2E-encrypted. The nuance goes in the privacy policy, not in an omission. | D3 |
| Identifiers → User ID | **Collected**, linked, App Functionality — the device credential (public key/credential id) bound to the vault, and store transaction ids | D1, D2, D7 |
| Purchases → Purchase History | **Collected**, linked, App Functionality | D2 |
| Usage Data | **Not collected** (no analytics) — conditional on §7.1 decision | N5 |
| Diagnostics | **Not collected** — conditional on §7.2 decision | N6 |
| Tracking (ATT sense) | **No tracking.** No ATT prompt needed. | N3 |

### 3.2 Export compliance (encryption)

- App uses non-exempt-by-default encryption (libsodium, XChaCha20-Poly1305, Argon2id) → `ITSAppUsesNonExemptEncryption = YES` in Info.plist, then claim the **mass-market / data-protection exemption** in the App Store Connect questionnaire (encryption used to protect user data, not as a standalone crypto product, standard algorithms).
- Consequence: eligible for exemption from French export authorization *for the app itself*, but a **self-classification report** may be required annually (US BIS regime applies because distribution goes through Apple/US infrastructure). **Agent task: this is a legal-verification TODO, not something to resolve in code. Surface it in the project TODO with a hard deadline before first TestFlight external build** (TestFlight external distribution already triggers export compliance).

### 3.3 Review-critical items (frequent rejection causes for this app profile)

| Item | Requirement | Status |
|---|---|---|
| R1 | Subscription terms visible pre-purchase: price, duration, renewal, cancellation path (Guideline 3.1.2) | TODO |
| R2 | Privacy policy URL publicly reachable, consistent with §3.1 | TODO |
| R3 | Account deletion available **in-app** (Guideline 5.1.1(v)) — must be reconciled with the 3-year read-only model: deletion must be actionable, the read-only grace is an *offer*, not an obstacle | TODO — **architectural check needed against SECURITY.md §4.4** |
| R4 | Reviewer demo account with pre-activated subscription entitlement | TODO |
| R5 | `NSPhotoLibraryUsageDescription`, `NSMicrophoneUsageDescription`, `NSFaceIDUsageDescription` (if biometric unlock) accurate and specific | TODO |
| R6 | Kids Category: **do NOT opt in.** souvenir is a parents' tool, not a children's app. Opting in triggers a far stricter regime with no benefit. | Constitutional |

---

## 4. Google Play — Data Safety and Console declarations (draft answers)

### 4.1 Data Safety form

| Play category | Answer | Source rows |
|---|---|---|
| Personal info → Email | **Not collected in V1** (accountless — N7) | N7 |
| Photos and videos / Audio | Collected, required, App functionality, encrypted in transit **and end-to-end (operator cannot read)** — Play's form allows declaring E2E; use it, it is a differentiator | D3 |
| App activity | Not collected — conditional on §7.1 | N5 |
| App info and performance (crash logs) | Not collected — conditional on §7.2 | N6 |
| Device or other IDs | Collected (device identifiers for sync), App functionality | D7 |
| Data deletion | User-initiated deletion supported (in-app + documented path) | SECURITY.md §4.4 |

### 4.2 Console specifics

| Item | Requirement | Status |
|---|---|---|
| G1 | Closed-testing gate: 12 testers / 14 days for new personal accounts — plan recruitment now | TODO |
| G2 | Play Billing mandatory for the subscription; no external payment link in-app (EU alternative-billing evolutions to be re-checked at submission time, not assumed) | TODO |
| G3 | Content rating questionnaire: adult-targeted tool (parents). Do **not** declare child-targeted → avoids Families Policy regime | Constitutional |
| G4 | `AD_ID` permission audit (see N3) | TODO |
| G5 | Keystore custody procedure documented (loss = permanent loss of the package name) — belongs in survivability posture, SECURITY.md §9 | TODO |
| G6 | Login credentials for review (App access section), same entitlement approach as R4 | TODO |

---

## 5. French / EU obligations outside the stores

| Item | Obligation | Status |
|---|---|---|
| F1 | **ANSSI cryptology declaration**: supplying a means of cryptology beyond pure authentication in France requires (at minimum) a declaration to ANSSI (régime déclaratif, art. 29–31 LCEN / décret 2007-663). Standard algorithms via libsodium almost certainly fall under the declarative regime, not authorization — but the declaration itself must be filed. **Legal TODO with deadline before public release.** | TODO |
| F2 | DSA **trader status**: public postal address, email, phone on both store listings. Decide: commercial domiciliation vs personal address. | DECISION NEEDED |
| F3 | Privacy policy (FR + EN), hosted, versioned in-repo, generated from §2 — never from a template service | TODO |
| F4 | DPIA: photos of minors + large-scale storage plausibly triggers a DPIA; SECURITY.md already references it — verify a DPIA document actually exists or is scheduled | Agent: VERIFY |
| F5 | Legal entity + VAT posture: stores act as merchant of record for IAP; invoicing target is Apple/Google | Informational |

---

## 6. IAP architecture constraints (feeds ARCHITECTURE.md)

- StoreKit 2 (iOS) / Play Billing (Android); entitlement state is server-verified (App Store Server API / Play Developer API), never trusted from the client alone.
- Entitlement lapse → transition to read-only mode is a **client-enforced state with server-enforced write refusal**; the 3-year clock and final deletion are server-side lifecycle events (SECURITY.md §4.4, §10).
- The business model spreadsheet MUST run on the 15% commission hypothesis (Small Business Program / Play equivalent), not the Stripe/PWA hypothesis from the early market study. **Agent: verify which hypothesis the current break-even model encodes; flag if it still assumes Stripe net revenue.**

---

## 7. Open decisions blocking declaration freeze

| # | Decision | Default if undecided |
|---|---|---|
| 7.1 | Analytics: none / privacy-preserving self-hosted / none in V1 | **None in V1** (declarations above assume this) |
| 7.2 | Crash reporting: none / OS-native only / third-party | **None or OS-native in V1** (declarations above assume this) |
| 7.3 | IP/log retention duration (D6) | Proposal: 12 months, documented |
| 7.4 | Trader address (F2) | Commercial domiciliation |
| 7.5 | EXIF stripping client-side: specified as invariant or not (N1) | Must become explicit — raise as SECURITY.md amendment if absent |

---

## 8. Coherence mapping table (the mechanical heart of this document)

> Agent: fill `STATUS` per row. `VERIFIED` requires pointing to the exact file/section/test. `N/A (no code yet)` is acceptable only for rows whose enforcement point is code.

| # | Declaration (store-facing) | Enforced by (SECURITY.md) | Proven by (TESTING.md) | Enforcement point in code | STATUS |
|---|---|---|---|---|---|
| C1 | Content not readable by operator (ciphertext-only server) | §1 invariants (esp. §1.4 special category) | invariants job (`TESTING §2`) + crypto (`§1`) | `MemoryStore.add` seals before upload; backend allowlist + `FORBIDDEN_FIELDS` | **VERIFIED** (backend/test invariants + crypto-core suite; server stores opaque blobs only) |
| C2 | Keys never leave device unwrapped | §3 key hierarchy (DEK→VK→MIK, MIK under {passphrase,RK,device}) | crypto round-trip tests (`§1`), incl. enrollment + social-recovery | `crypto-core` `KeyWrap`; only wrapped keys uploaded (`wrapped_key`, `wrapped_mik`, `wrapped_vk`, `wrapped_mik_rk`) | **VERIFIED** (shares never sent — backend refuses a `share` field) |
| C3 | No face vectors / perceptual hashing (N2) | **Prohibition MISSING in SECURITY.md** (only a value-drift caution, ARCHITECTURE §9) — amendment proposed §10 | static dependency audit (`backend/test/dependency_audit.test.js`) | no ML/Vision/CoreML SDK | **BROKEN** (holds *de facto* — audit clean — but not specified as an invariant) |
| C4 | No advertising identifiers (N3) | Business model §10 (no ads) | dependency audit (ATT / AD_ID / ad SDKs) | no ATT, no ad SDK; Android not built | **PARTIAL** (enforced for iOS by the audit; Android manifest check pending an Android app) |
| C5 | No transcription (N4) | Scope decision (Whisper removed) | dependency audit (`import Speech` / `SFSpeechRecognizer`) | `AudioRecorder` = record/playback only | **VERIFIED** (audit clean) |
| C6 | In-app account deletion (R3) | §4.4 deletion by owner | lifecycle test — absent | deletion flow — absent | **N/A (no code yet)** — plus: accountless (N7) reframes R3 as *delete the vault/device identity* |
| C7 | 3-year read-only then deletion (§10) | §4.4 / §10 | server lifecycle test — absent | entitlement state machine — absent (no IAP) | **N/A (no code yet)** |
| C8 | Metadata leakage mitigated (D4) | §6.2 padding-by-tiers `[FIGÉ]` | blob-size property test — absent | **padding layer ABSENT in code** | **BROKEN** — the decision is frozen but unimplemented; D4's "mitigated by padding" over-claims today |
| C9 | EXIF stripped client-side (N1) | §8.1 minimisation (a practice, **not** a §1 invariant — elevating it is decision 7.5) | static guard in `dependency_audit.test.js`; runtime test needs an iOS test target | `ImageTools.stripExifJPEG`, called on every image ingest (`MemoryStore.addPhoto`) | **PARTIAL** (coded + static-guarded; no runtime EXIF test yet) |
| C10 | Privacy policy ⇔ §2 inventory identical | this document | doc cross-consistency script — absent | privacy policy — absent | **N/A (no code yet)** |
| C11 | Export compliance answer ⇔ actual crypto usage | §1 invariants + this §3.2 | manual legal review gate | `ITSAppUsesNonExemptEncryption` — **absent** from Info.plist | **TODO** (add plist key + questionnaire before first external TestFlight) |
| C12 | Data Safety E2E claim ⇔ C1 | §1 invariants | same as C1 | same as C1 | **VERIFIED** (as a principle; the store *declaration* is TODO) |

---

## 9. Verification Protocol (run this first, Claude Code)

1. **Reference resolution pass:** resolve every `§` reference in this document against the live CLAUDE.md, SECURITY.md, ARCHITECTURE.md, TESTING.md, DESIGN_INTEGRATION.md. Output a diff table: reference as written → actual section → FIX/OK/MISSING. (Same method as the existing cross-consistency script — extend it to include STORE_COMPLIANCE.md.)
2. **Gap audit:** for N1 (EXIF) and N2 (no ML features), report whether an explicit invariant or prohibition exists. If not, draft the amendment proposal but do NOT ratify it — ratification is the owner's decision.
3. **Business model audit:** open the break-even spreadsheet/model and report which revenue hypothesis it encodes (store 15% vs Stripe). Report the corrected break-even subscriber count under 9.90 € × 15% commission if it differs.
4. **Dependency audit (if any code exists):** list every dependency in the iOS and Android projects; map each against §2; report any dependency with data collection behavior lacking a §2 row.
5. **Status fill:** complete the STATUS column of §8 and the Status columns of §3.3, §4.2, §5.
6. **Report:** produce a single summary — what is VERIFIED, what is TODO, what is BROKEN, what requires an owner decision (§7) — and stop. Do not implement fixes without explicit instruction.

---

## 10. Proposed amendments (drafts — NOT ratified)

Surfaced by the §9 run. These are **proposals for the owner to ratify**; the agent did not edit `SECURITY.md` (that is ratification). Each maps to a `BROKEN`/`PARTIAL` row above.

### 10.1 New SECURITY.md invariant — no ML-/vision-derived features (closes N2 / C3)
> **Proposed §1 invariant (draft):** *"No machine-learning or computer-vision feature is ever computed over user content, on device or server: no face vectors, no perceptual/similarity hashes, no auto-tagging, no content classification. Any such feature would create a derived index of children's data and is refused by construction (see the value-drift trap, ARCHITECTURE.md §9)."*
> Rationale: today this holds only *de facto* (dependency audit is clean) and as a design caution, not as a load-bearing invariant. Enforcement point already in CI: `backend/test/dependency_audit.test.js` (blocks ML/Vision/CoreML SDKs). Ratifying makes C3 `VERIFIED`.

### 10.2 Elevate EXIF stripping to an invariant + runtime test (closes decision 7.5 / C9)
> EXIF/GPS stripping is currently a **minimisation practice in §8.1**, not a §1 invariant, and the code (`ImageTools.stripExifJPEG`) had **no test**. A static guard is now in CI. **Proposed:** (a) add a §1 invariant *"no image leaves the device carrying EXIF/GPS metadata; stripping happens client-side before encryption"*; (b) add a **runtime** test that feeds a known EXIF/GPS-tagged JPEG through the strip and asserts the output carries no such tags — this needs a **new iOS unit-test target** wired into the `ios-app` CI job (owner go-ahead needed, small infra change).

### 10.3 Padding: implement it or stop declaring it (closes C8 / D4)
> `SECURITY §6.2` freezes (`[FIGÉ]`) client-side padding-by-tiers of all blobs before encryption, but **no padding exists in code** (blobs upload at their true size ± AEAD overhead). Two coherent resolutions — **not the agent's call**:
> - **Implement** the padding layer (the exact tier scale is `[À VALIDER PAR SPIKE]`, ARCHITECTURE.md §6), then D4 "mitigated by padding" becomes true and C8 can be `VERIFIED`; **or**
> - until then, **weaken D4's declaration** to "sizes are metadata leakage, mitigation (padding) planned but not yet shipped" so the store forms never over-claim.
> This is a **SECURITY-relevant gap** (a frozen decision the code does not yet honour), not merely a store-form nuance.

---

*Drafted 2026-07-02 outside the repository. Not ratified. Subject to the amendment and precedence rules of CLAUDE.md. §9 verification run + STATUS fill + §10 proposals added 2026-07-02 (agent), unratified.*
