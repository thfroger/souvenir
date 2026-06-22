# SECURITY.md

> ⚠ **Generated translation — DO NOT hand-edit.** The canonical document is the French `SECURITY.md`; this English file is a translation maintained for international open-source contributors (the crypto core). On any divergence, `SECURITY.md` (French) governs. Regenerate this file from it after every change.
>
> Constitutional document. It describes *what must never be violated* and *why*.
> Any future feature that contradicts an invariant in §1 is refused or redesigned — not negotiated.
> Intended readers: you in 6 months, a contractor, an external auditor, the CNIL (French DPA).

---

## 1. Invariants (the load-bearing walls)

These properties override every product request, every UX convenience, every optimization.
If a feature requires breaking one, **the feature is the problem, not the invariant**.

1. **The server can never read the content of a memory.** It stores only encrypted blobs and wrapped keys that are unreadable without the user's master key, which the server does not hold.
2. **The operator has no content-recovery mechanism whatsoever.** There exists no path by which the publisher could restore access to the data of a user who has lost everything. (Direct consequence: see §7, the recovery theorem.)
3. **The master key (MIK) never exists in cleartext on the server, in logs, in telemetry, or in a backup.**
4. **No special-category data (health: the `maladie`/illness tag, etc.) ever leaves the device in cleartext, neither as content nor as metadata.** All filtering/search over such data is strictly local.
5. **The crypto core is an isolated, open-source module, frozen in the signed binary.** Never shipped via OTA (see ARCHITECTURE.md). It is what gets audited; it must not be able to change behind the user's back.
6. **A memory is never displayed, and its local original never deleted, until a re-decryption self-check confirms it is readable** (anti-silent-corruption, see ARCHITECTURE.md §5).
7. **No server secret, no test key, no backdoor is embedded in the client bundle.**

> Reference convention: these invariants are cited elsewhere as **§1.1 through §1.7** (e.g. §1.5 = the frozen crypto core, §1.6 = the self-check). They are list items within §1, not separate subsections.

An invariant test suite (see TESTING.md §2) makes these properties *mechanically verifiable* in CI. An invariant that is not tested is an invariant that will drift.

---

## 2. Threat model, by adversary

The method: for each adversary, we state explicitly **what we defend against** and **what we do not**. Claiming to cover everything would be security theater.

### 2.1 The operator (ourselves)
- **Defended:** end-to-end encryption (E2E). The server only ever sees ciphertext. A malicious employee, a database dump, a subpoena: nothing exploitable on the content side.
- **Not defended / accepted:** we do see technical metadata (account existence, blob volume, sync timestamps, blob sizes — see §6 side channel). We minimize but do not eliminate all of it.

### 2.2 External attackers (hackers)
- **Defended:** content is useless even on full server compromise. TLS + certificate pinning in the native app. Passkey-based auth. Anti-credential-stuffing via exponential backoff (no hard lockout — see §6.3).
- **Not defended:** compromise of the user's own unlocked device (malware on the parent's phone). Out of reach for any consumer app.

### 2.3 The relative / ex-partner
- **Defended:** dual-vault model (§4). On separation, removal of access to new memories **+ rotation of the shared-vault key**, so an ex who scraped blob IDs can decrypt nothing produced after the split.
- **Not defended / impossible by construction:** clawing back what has already been decrypted and seen. We do not "un-decrypt" the past. The cutoff applies to the future only.
- **Deliberately not defended:** we do NOT arbitrate legal custody. No divorce-ruling verification, no clawback decided by one parent against the other. See §4.3 for why this is a choice, not a gap.

### 2.4 The State
- **Defended:** mass requisition → we only hand over unreadable ciphertext. Targeted server requisition → certificate pinning and the frozen/auditable crypto code limit MITM and tampered code.
- **Not defended, and to be stated in writing:** a State that targets *this specific* child and compromises the parent's device wins. No consumer app protects against that. Native raises the wall (auditable signed binary vs. JS re-served every session); it does not make us untouchable.
- **Residual dependency:** App Store / Play Store are requisitionable US trust points that deliver the signed updates. Native shifts part of the risk from the server (which we control) to the store (which we do not). An accepted trade-off, not a total win.

---

## 3. Key hierarchy

Three tiers, via key wrapping. Never a single key derived from the password.

```
Wrapped IN PARALLEL by (each unwraps the SAME MIK):
  • password-derived key (Argon2id)
  • each trusted device's local key (Secure Enclave / Keystore, unlocked by biometrics)
  • Recovery Key (RK) ── Shamir 2-of-3 across guardians (see §5)
        │
        ▼
Master Identity Key (MIK)        ← synced across trusted devices,
        │                          NEVER in cleartext on the server
        ├── wraps ──▶ Personal-vault key ──▶ wraps data keys ──▶ encrypt each memory
        └── wraps ──▶ Shared-vault key (see §4)
```

- **Data key (DEK):** one per memory, disposable, `XChaCha20-Poly1305`. Encrypts the blob.
- **Vault key (VK):** wraps a vault's DEKs. Enables revoke/share at vault granularity.
- **Master key (MIK):** the user's only true secret. Wraps the VKs. The MIK itself is wrapped *in parallel* by several keys (password-derived, per-device local, recovery) — each is an independent way to unwrap the same MIK.
- **Recovery key (RK):** a dedicated high-entropy key whose *only* job is to wrap a copy of the MIK. It is the RK — **never the MIK directly** — that is Shamir-split across guardians (§5). On-purpose indirection: rotating a guardian, or reacting to a leaked share, means generating a new RK and re-wrapping the MIK, with **zero re-encryption of memories** (same structural benefit as a password change).
- **Password derivation:** `Argon2id`. Changing the password re-encrypts the MIK only, not the memories.
- **Library:** `libsodium` exclusively. Nothing homemade, nothing exotic. This is what the audit wants to see.

Structural benefits: changing the password = re-encrypting the MIK only; revoking a share = touching one VK; the server stores only opaque blobs + wrapped keys.

---

## 4. Co-parent model: dual vault

> **Scope:** the primary persona is solo (a single mother). The co-parent is an **optional layer planned for V2**, never a prerequisite. In **V1 the shared vault does not exist**: everything lives in the user's personal vault, and the threat surface excludes the shared vault (§2.3 concerns V2 only). The section below describes the target model once the co-parent is introduced.

### 4.1 Principle
The shared-vault key (SVK) is wrapped **twice**: once under parent A's MIK, once under parent B's MIK. Each parent holds, on their device, a copy of the SVK they can unwrap with *their own* key — without ever accessing the other's MIK.

- **Shared** memory → encrypted with the SVK → visible to both.
- **Private** memory → stays in its author's personal vault → invisible to the other, by cryptographic construction.

### 4.2 Separation
A trivial operation, no arbiter:
1. Stop wrapping **new** memories under the SVK.
2. Each keeps their copy of what was shared (it is physically on their device; we do not take it back).
3. **SVK rotation:** the shared-vault key is rotated both server-side (blob-access revocation) and cryptographically, to neutralize an ex who pre-collected IDs.
4. Each continues their own personal vault.

### 4.3 Why no custody arbitration (a choice, not a gap)
We have no reliable way to verify who the legal guardian is (read court rulings? arbitrate a contested custody?). The day we get it wrong, we hand a child's memories to a parent the other told us was dangerous. The dual-vault model avoids the courtroom entirely: no verification, no unilateral clawback (which would become a weapon in a contentious divorce), no publisher in the middle of a family conflict it cannot adjudicate.

### 4.4 Deletion by owner, never by vault
A co-parent who unsubscribes/deletes erases ONLY their copy. The other's copy survives. The "permanent deletion" of the business model (see §8) is always scoped to the owner.

---

## 5. Social recovery (Shamir 2-of-3)

It is the **Recovery Key (RK, §3)** — never the MIK directly — that is split via Shamir secret sharing: **3 shares entrusted to relatives, 2 suffice** to reconstruct. Recovery flow: gather 2 shares → reconstruct the RK → fetch the opaque `MIK-wrapped-under-RK` blob → unwrap → recover the MIK → re-enroll the device. No single person can do anything with one share.

**"The operator is never in the loop"** means the operator can neither trigger nor perform a recovery. Alone, it holds only the opaque `MIK-wrapped-under-RK` blob (consistent with the deliberately dumb backend, ARCHITECTURE.md §1) and has no RK; that blob is useless without 2 of 3 guardian shares. The operator is never one of the guardians. This is the only safety net compatible with invariant §1.2 (no operator recovery).

Combined with multi-device sync, it makes loss near-impossible: you must lose *all* your devices at once AND be unable to gather 2 of 3 guardians.

**Share delivery matters:** a share handed over in cleartext (SMS, email) is a leak. Shares are delivered out-of-band / encrypted — ideally the guardian runs the app and stores their share under their own key. The setup UX carries this (DESIGN_INTEGRATION.md §9).

**Two documented pitfalls:**
- **Family pitfall:** if a share guardian is the ex-partner things go wrong with, the safety net becomes a hole. → The setup UX must steer toward guardians *outside* the potential conflict perimeter.
- **UX pitfall:** asking an overwhelmed young parent to designate 3 trusted people is a high step. → Turn it into an act of care ("who will watch over your child's memories?"), not a cryptographic chore. This is a critical design point (and a possible feedback loop onto the architecture — see ARCHITECTURE.md §10).

---

## 6. What the server sees / never sees — and residual leaks

### 6.1 Permissions in a ZK context
The server CANNOT verify *content* permissions (it does not read content). Content access is **cryptographic**: you see a memory iff you can unwrap its key.

But a **server-side authorization at the blob-and-key tier remains indispensable**: who may fetch which blob, unwrap which wrapped key, write to which vault. It MUST be server-side — client-only authorization ("hide the button") lets a malicious client request IDs directly. Scenario: on separation, if the server keeps serving shared-vault blobs to the removed parent B, it siphons the new memories. → Server revocation + SVK rotation (§4.2).

### 6.2 Side channel: blob size
Blob size leaks through two channels: the **approximate type** (4 MB = photo, 30 KB = note — accepted metadata, §2.1) and, more importantly, the **exact fingerprint** (byte-exact size lets one test "does this user hold *this specific* file?", a deanonymization vector).

Policy `[FROZEN]`:
- **Tiered padding of all blobs** on a moderate geometric ladder (*not* powers of two), applied **client-side before encryption/upload**. Goal: kill the exact fingerprint for a bounded storage overhead. (The exact ladder is `[TO BE VALIDATED BY SPIKE]` — calibrate real overhead vs. representativeness, cf. ARCHITECTURE.md §6.)
- **Common floor for small content blobs** (note, measure, quote, child profile): among small items, *which* type is no longer distinguishable.
- **Scrub logs** down to `event type + opaque ID`; **never** log membership changes with names.

Accepted, not defended: the **media (photo/audio) vs text class** remains inferable from size — we do not pad a note up to a photo's size (prohibitive overhead, §10). We defend the exact fingerprint and type-among-small-items, not the existence of a media blob.

### 6.3 Bypassable auth and self-inflicted denial of service
No "skip" path on biometric unlock. Server auth via passkeys. Anti-stuffing via **exponential backoff, not hard lockout**: since there is no operator recovery, a hard lockout would let an attacker deliberately lock a parent out — security would turn into a DoS against our own users.

### 6.4 In transit / at rest
- In transit: TLS + **certificate pinning** in the native app (matters given the "requisitioned server serving a MITM" threat).
- At rest: blobs already E2E-encrypted; **also encrypt the metadata database and its backups**.

---

## 7. The recovery theorem (to be accepted, not circumvented)

Authentication ≠ encryption. 2FA proves *who you are* to the server; it carries no decryption key. Transient factors (SMS, TOTP, email code) cannot carry a stable key; biometrics merely unlock a key *already present on this device*.

Consequence: **"the operator cannot read" and "the operator restores my access if I forget everything" are mutually exclusive.** Multiplying recovery paths multiplies intrusion surfaces (SIM-swap on SMS, mailbox access…): real security drops to the level of the weakest factor.

Our choice: **multi-device sync (losing one device is a non-event) + Shamir social recovery (the catastrophe case).** No operator escrow. Simultaneous loss of all devices AND of the ability to gather 2 of 3 guardians means permanent loss — that is the accepted, user-disclosed price of invariant §1.2.

---

## 8. Regulatory and anti-abuse posture

### 8.1 GDPR / CNIL
- **DPIA (AIPD)**: de facto mandatory here (systematic processing of children's data, special category). To be produced. ZK is our best argument: what we cannot read can be neither misused, leaked, nor requisitioned on the content side.
- **Minimization as guiding principle**: the most irreproachable data is what you never collect. No real child name required (first name/nickname/emoji), year rather than exact date where the timeline allows, pseudonymous parent account as far as possible, payment separated from content (the provider that sees the card never sees the vault), systematic EXIF stripping at capture (geolocation = "this child was at this hospital on this day"), **encrypted child profiles and child-assignment** (each child's name and full birthdate are kept as encrypted content; the server knows neither the number of children, nor their names, nor their birthdates, nor how memories split across them — 100% local filtering, cf. `DESIGN_INTEGRATION.md §2` and §2.1).
- **Market and jurisdiction**: launch on the **French (hence EU) market**. Supervisory authority: **CNIL**. GDPR applies, DPIA expected. **EU hosting recommended**: blobs are E2E-encrypted, but jurisdiction and metadata are not — EU hosting matters given the "State" threat (§2.4) and avoids exposure to extra-EU legal frameworks. The exact **legal entity** acting as data controller is still to be determined; the jurisdiction is fixed.

### 8.2 Age verification (a tension knowingly accepted with minimization)
This is the one place where minimization and child protection pull in opposite directions. Decision: **primary gate via payment** (a paid annual subscription implies a payment method, hence an adult, with no extra ID collection) + self-declaration as a complement. **Third-party identity verification refused** (it destroys anonymity and creates an identity database we would have to protect — the opposite of irreproachable). The paywall already does part of the work; we are not an open, free social network.

### 8.3 CSAR / "Chat Control" context and abuse prevention
An E2E vault of children's photos is precisely the architecture at the center of the European regulatory debate. Status (to be refreshed, the file is moving): the temporary derogation allowing voluntary scanning ("Chat Control 1.0") expired in early April 2026; the permanent regulation (CSAR / "Chat Control 2.0") remains under negotiation, with mandatory client-side scanning dropped for now in favor of a regime of **risk assessment + reasonable mitigation measures + age verification**. Our service (photo hosting, sharing between co-parents) falls within the scope of the mitigation obligations.

Direct, uncomfortable consequence to own: under ZK, **we deliberately make ourselves incapable of inspecting any content** — hence of detecting abuse on our own platform. This is not a flaw; it is the exact logical consequence of E2E. Written position, to be filed with the DPIA:
- **Age verification** at signup (§8.2).
- **Sharing restricted to the strict co-parental circle**: no public sharing, no broad distribution; the shared vault is bounded to two parents.
- **User reporting mechanism**, non-intrusive (does not break ZK).
- Documentation of *why* the architecture is legitimate and whom it serves (families, long-term private preservation), as part of the expected risk assessment.

### 8.4 Technical compliance targets and audit commitment
- **OWASP MASVS** level L2 + reverse-engineering resistance as the named mobile standard (a verifiable checklist, not a vague intent).
- **Open-source crypto core + budgeted independent external audit.** Irreproachability is not declared, it is made verifiable: without an audit, "zero-knowledge" is an assertion as unverifiable as anyone else's.

---

## 9. Survivability (a 15-year promise)

A "vault" is a long promise. If the company shuts down, the promise must not die with it: **open formats, guaranteed and automatic export** client-side (export/album can only be generated where the key exists, never server-side). Long-term preservation that depends on a solo founder's survival is *sincere*, not *irreproachable* — open export closes the gap.

---

## 10. Business model (security implications recap)

Annual subscription. Unsubscribe → read-only access for **3 years**, then permanent deletion **by owner** (§4.4) with an offer to hand the data back cleanly (export, even a client-generated paper album — a later feature, but open export is planned from day one to uphold survivability §9). Storing the encrypted blobs of non-paying users has a real cost (ciphertext neither deduplicates nor compresses): it is a P&L line, not a detail.
