import { createHash, createPublicKey, verify, randomBytes } from "node:crypto";

// The deliberately dumb backend (ARCHITECTURE.md §1, §3.1): an encrypted-blob
// store + opaque metadata rows. It performs NO content processing, NO indexing,
// NO per-request crypto. It can never see plaintext: the only fields it accepts
// for an entry are opaque (a wrapped key + a blob hash). Authorization lives at
// the blob-and-key tier (SECURITY.md §6.1), never client-side only.

// The only metadata an entry row may carry (ARCHITECTURE.md §3.1). Anything else
// — a title, note, civil date, tag, child, measure… — is content and is refused.
const ENTRY_INPUT_FIELDS = new Set(["entry_id", "wrapped_key", "blob_hash"]);

// The identity bundle that lets a second trusted device of the SAME user adopt
// the vault key (SECURITY.md §3). All opaque: the MIK wrapped under a
// passphrase-derived key (Argon2id), the VK wrapped under the MIK, plus the
// non-secret KDF salt. The server never sees the passphrase, the MIK or the VK
// in clear — only ciphertext + a salt.
const IDENTITY_INPUT_FIELDS = new Set(["salt_b64", "wrapped_mik", "wrapped_vk"]);

// The social-recovery bundle (SECURITY.md §5): the MIK wrapped under a Recovery
// Key that is itself Shamir 2-of-3-split across the user's guardians (the shares
// never touch the server), plus the VK wrapped under the MIK so recovery is
// self-contained. All opaque ciphertext — the server holds no share, no key.
const RECOVERY_INPUT_FIELDS = new Set(["wrapped_mik_rk", "wrapped_vk"]);

// Belt-and-suspenders denylist of content / special-category field names that
// must never reach the server (SECURITY.md §1.4, §6.2).
const FORBIDDEN_FIELDS = new Set([
  "title", "note", "text", "content", "plaintext", "caption",
  "date", "civil_date", "civilDate", "timezone",
  "tag", "tags", "child", "child_name", "childName", "name",
  "measure", "milestone", "quote", "transcript",
]);

export class Backend {
  constructor() {
    this.blobs = new Map(); // hash -> { bytes: Buffer (opaque ciphertext), uploadedAt: ms }
    this.entries = []; // opaque metadata rows
    this.seqByVault = new Map(); // vault_id -> monotonic seq
    this.identities = new Map(); // vault_id -> { salt_b64, wrapped_mik, wrapped_vk } (opaque)
    this.recoveries = new Map(); // vault_id -> { wrapped_mik_rk, wrapped_vk } (opaque, §5)
    this.logs = []; // content-free structured logs (SECURITY.md §6.2)

    // Auth (passkey-equivalent): a device registers a P-256 public key bound to a
    // vault, then proves possession by signing a server challenge. A successful
    // verify mints a short-lived session token. No shared secret is ever stored.
    this.credentials = new Map(); // credentialID -> { keyObject, vault }
    this.challenges = new Map();  // challenge(b64) -> expiresAt(ms), single-use
    this.sessions = new Map();    // sessionToken -> vault

    // Dev/test convenience: pre-seeded sessions so the storage/authorization
    // tests don't each re-run the auth handshake. The app uses the real flow.
    this.sessions.set("tok-A", "vault-A");
    this.sessions.set("tok-B", "vault-B");
  }

  // Logs carry only an event type + opaque ids — never a wrapped key, never
  // blob bytes, never any content (SECURITY.md §6.2).
  log(event, fields = {}) {
    this.logs.push({ event, ...fields });
  }

  owns(token, vaultId) {
    return this.sessions.get(token) === vaultId;
  }

  handle({ method, path, query = {}, token, body } = {}) {
    const parts = path.split("/").filter(Boolean);

    // POST /auth/register — bind a device P-256 public key to a vault.
    if (method === "POST" && parts[0] === "auth" && parts[1] === "register") {
      const { credential_id, public_key, vault } = body ?? {};
      if (!credential_id || !public_key || !vault) return { status: 400, body: { error: "missing_fields" } };
      let keyObject;
      try { keyObject = this.publicKeyFromX963(public_key); } catch { return { status: 400, body: { error: "bad_public_key" } }; }
      // Skeleton: first registrant claims the vault; a real system gates new
      // devices (existing-device approval / vault proof). Re-registering the same
      // credential is idempotent.
      this.credentials.set(credential_id, { keyObject, vault });
      this.log("auth.register", { credential_id, vault });
      return { status: 200, body: { ok: true } };
    }

    // POST /auth/challenge — issue a single-use, short-lived challenge.
    if (method === "POST" && parts[0] === "auth" && parts[1] === "challenge") {
      const challenge = randomBytes(32).toString("base64");
      this.challenges.set(challenge, Date.now() + 120_000);
      this.log("auth.challenge", {});
      return { status: 200, body: { challenge } };
    }

    // POST /auth/verify — verify a signed challenge → mint a session token.
    if (method === "POST" && parts[0] === "auth" && parts[1] === "verify") {
      const { credential_id, challenge, signature } = body ?? {};
      const cred = this.credentials.get(credential_id);
      const expiresAt = this.challenges.get(challenge);
      if (!cred || expiresAt === undefined) return { status: 401, body: { error: "unknown_credential_or_challenge" } };
      this.challenges.delete(challenge); // single-use, even on failure → no replay
      if (Date.now() > expiresAt) return { status: 401, body: { error: "challenge_expired" } };
      let ok = false;
      try {
        ok = verify("sha256", Buffer.from(challenge, "base64"),
          { key: cred.keyObject, dsaEncoding: "der" }, Buffer.from(signature ?? "", "base64"));
      } catch { ok = false; }
      if (!ok) return { status: 401, body: { error: "bad_signature" } };
      const session = randomBytes(24).toString("base64");
      this.sessions.set(session, cred.vault);
      this.log("auth.verify", { credential_id, vault: cred.vault });
      return { status: 200, body: { token: session, vault: cred.vault } };
    }

    // PUT /blobs/:hash  — store an opaque, content-addressed encrypted blob.
    if (method === "PUT" && parts[0] === "blobs" && parts.length === 2) {
      if (!this.sessions.has(token)) return { status: 401, body: { error: "unauthenticated" } };
      const hash = parts[1];
      const bytes = Buffer.from(body?.data_b64 ?? "", "base64");
      const actual = createHash("sha256").update(bytes).digest("hex");
      if (actual !== hash) return { status: 400, body: { error: "hash_mismatch" } };
      this.blobs.set(hash, { bytes, uploadedAt: Date.now() });
      this.log("blob.put", { hash });
      return { status: 200, body: { hash } };
    }

    // GET /blobs/:hash — fetch an opaque blob; allowed only if the caller owns a
    // vault that references it (SECURITY.md §6.1).
    if (method === "GET" && parts[0] === "blobs" && parts.length === 2) {
      if (!this.sessions.has(token)) return { status: 401, body: { error: "unauthenticated" } };
      const hash = parts[1];
      const referenced = this.entries.some(
        (e) => e.blob_hash === hash && this.owns(token, e.vault_id),
      );
      if (!referenced) return { status: 403, body: { error: "forbidden" } };
      const rec = this.blobs.get(hash);
      if (!rec) return { status: 404, body: { error: "not_found" } };
      this.log("blob.get", { hash });
      return { status: 200, body: { data_b64: rec.bytes.toString("base64") } };
    }

    // POST /vaults/:vaultId/entries — create a pending opaque metadata row.
    if (method === "POST" && parts[0] === "vaults" && parts[2] === "entries" && parts.length === 3) {
      const vaultId = parts[1];
      if (!this.sessions.has(token)) return { status: 401, body: { error: "unauthenticated" } };
      if (!this.owns(token, vaultId)) return { status: 403, body: { error: "forbidden" } };

      const keys = Object.keys(body ?? {});
      // Refuse anything that is not opaque metadata — no path for cleartext in.
      if (keys.some((k) => FORBIDDEN_FIELDS.has(k))) return { status: 400, body: { error: "content_refused" } };
      if (keys.some((k) => !ENTRY_INPUT_FIELDS.has(k))) return { status: 400, body: { error: "unknown_field" } };
      if (!body?.entry_id || !body?.wrapped_key || !body?.blob_hash) {
        return { status: 400, body: { error: "missing_wrapped_key_or_blob" } };
      }

      // Idempotent on the client UUID (ARCHITECTURE.md §5).
      const existing = this.entries.find((e) => e.entry_id === body.entry_id);
      if (existing) return { status: 200, body: this.rowView(existing) };

      const seq = (this.seqByVault.get(vaultId) ?? 0) + 1;
      this.seqByVault.set(vaultId, seq);
      const row = {
        entry_id: body.entry_id,
        vault_id: vaultId,
        seq,
        committed: false,
        wrapped_key: body.wrapped_key,
        blob_hash: body.blob_hash,
        created_at: new Date().toISOString(),
      };
      this.entries.push(row);
      this.log("entry.create", { entry_id: row.entry_id, vault_id: vaultId, seq });
      return { status: 201, body: this.rowView(row) };
    }

    // POST /vaults/:vaultId/entries/:entryId/commit — mark readable after the
    // client's re-decryption self-check (ARCHITECTURE.md §5).
    if (method === "POST" && parts[0] === "vaults" && parts[2] === "entries" && parts[4] === "commit") {
      const vaultId = parts[1];
      if (!this.owns(token, vaultId)) return { status: 403, body: { error: "forbidden" } };
      const row = this.entries.find((e) => e.entry_id === parts[3] && e.vault_id === vaultId);
      if (!row) return { status: 404, body: { error: "not_found" } };
      row.committed = true;
      this.log("entry.commit", { entry_id: row.entry_id, vault_id: vaultId });
      return { status: 200, body: this.rowView(row) };
    }

    // GET /vaults/:vaultId/entries?since=seq — delta sync of opaque rows.
    if (method === "GET" && parts[0] === "vaults" && parts[2] === "entries" && parts.length === 3) {
      const vaultId = parts[1];
      if (!this.owns(token, vaultId)) return { status: 403, body: { error: "forbidden" } };
      const since = Number(query.since ?? 0);
      const rows = this.entries
        .filter((e) => e.vault_id === vaultId && e.seq > since)
        .sort((a, b) => a.seq - b.seq)
        .map((e) => this.rowView(e));
      this.log("entry.delta", { vault_id: vaultId, since, count: rows.length });
      return { status: 200, body: { entries: rows } };
    }

    // PUT /vaults/:vaultId/identity — store the opaque identity bundle that lets
    // another trusted device of the same user adopt the vault key (SECURITY.md §3).
    // Only the vault owner may write it; the server only ever sees ciphertext + a
    // non-secret salt, never the passphrase, the MIK or the VK in clear.
    if (method === "PUT" && parts[0] === "vaults" && parts[2] === "identity" && parts.length === 3) {
      const vaultId = parts[1];
      if (!this.sessions.has(token)) return { status: 401, body: { error: "unauthenticated" } };
      if (!this.owns(token, vaultId)) return { status: 403, body: { error: "forbidden" } };
      const keys = Object.keys(body ?? {});
      if (keys.some((k) => FORBIDDEN_FIELDS.has(k))) return { status: 400, body: { error: "content_refused" } };
      if (keys.some((k) => !IDENTITY_INPUT_FIELDS.has(k))) return { status: 400, body: { error: "unknown_field" } };
      if (!body?.salt_b64 || !body?.wrapped_mik || !body?.wrapped_vk) {
        return { status: 400, body: { error: "missing_identity_fields" } };
      }
      this.identities.set(vaultId, {
        salt_b64: body.salt_b64, wrapped_mik: body.wrapped_mik, wrapped_vk: body.wrapped_vk,
      });
      this.log("identity.put", { vault_id: vaultId });
      return { status: 200, body: { ok: true } };
    }

    // GET /vaults/:vaultId/identity — fetch the opaque bundle so a second device
    // can derive the KEK from the user's passphrase and recover the vault key.
    if (method === "GET" && parts[0] === "vaults" && parts[2] === "identity" && parts.length === 3) {
      const vaultId = parts[1];
      if (!this.sessions.has(token)) return { status: 401, body: { error: "unauthenticated" } };
      if (!this.owns(token, vaultId)) return { status: 403, body: { error: "forbidden" } };
      const bundle = this.identities.get(vaultId);
      if (!bundle) return { status: 404, body: { error: "not_found" } };
      this.log("identity.get", { vault_id: vaultId });
      return { status: 200, body: bundle };
    }

    // PUT /vaults/:vaultId/recovery — store the opaque social-recovery bundle
    // (SECURITY.md §5). The Shamir shares of the RK go to guardians out-of-band and
    // never reach the server; only MIK-under-RK and VK-under-MIK are stored here.
    if (method === "PUT" && parts[0] === "vaults" && parts[2] === "recovery" && parts.length === 3) {
      const vaultId = parts[1];
      if (!this.sessions.has(token)) return { status: 401, body: { error: "unauthenticated" } };
      if (!this.owns(token, vaultId)) return { status: 403, body: { error: "forbidden" } };
      const keys = Object.keys(body ?? {});
      if (keys.some((k) => FORBIDDEN_FIELDS.has(k))) return { status: 400, body: { error: "content_refused" } };
      if (keys.some((k) => !RECOVERY_INPUT_FIELDS.has(k))) return { status: 400, body: { error: "unknown_field" } };
      if (!body?.wrapped_mik_rk || !body?.wrapped_vk) {
        return { status: 400, body: { error: "missing_recovery_fields" } };
      }
      this.recoveries.set(vaultId, { wrapped_mik_rk: body.wrapped_mik_rk, wrapped_vk: body.wrapped_vk });
      this.log("recovery.put", { vault_id: vaultId });
      return { status: 200, body: { ok: true } };
    }

    // GET /vaults/:vaultId/recovery — fetch the opaque bundle so a device holding
    // 2 reconstructed shares can rebuild the RK, unwrap the MIK, then the VK.
    if (method === "GET" && parts[0] === "vaults" && parts[2] === "recovery" && parts.length === 3) {
      const vaultId = parts[1];
      if (!this.sessions.has(token)) return { status: 401, body: { error: "unauthenticated" } };
      if (!this.owns(token, vaultId)) return { status: 403, body: { error: "forbidden" } };
      const bundle = this.recoveries.get(vaultId);
      if (!bundle) return { status: 404, body: { error: "not_found" } };
      this.log("recovery.get", { vault_id: vaultId });
      return { status: 200, body: bundle };
    }

    return { status: 404, body: { error: "no_route" } };
  }

  // Janitor (ARCHITECTURE.md §5): delete blobs that have no COMMITTED metadata
  // after N hours. This reclaims the orphans left when a blob uploads but its
  // metadata write fails/times out — without ever touching a committed blob.
  // Meant to run on a schedule (cron); `now` is injectable for tests.
  collectOrphans({ now = Date.now(), ttlHours = 24 } = {}) {
    const cutoff = now - ttlHours * 3600 * 1000;
    const removed = [];
    for (const [hash, rec] of this.blobs) {
      const committed = this.entries.some((e) => e.blob_hash === hash && e.committed);
      if (!committed && rec.uploadedAt < cutoff) {
        this.blobs.delete(hash);
        removed.push(hash);
      }
    }
    this.log("janitor.sweep", { removed: removed.length });
    return removed;
  }

  // P-256 public key from the X9.63 representation (0x04 || X || Y) that Apple's
  // SecKey / CryptoKit produces, as a verifiable key object.
  publicKeyFromX963(b64) {
    const raw = Buffer.from(b64, "base64");
    if (raw.length !== 65 || raw[0] !== 0x04) throw new Error("bad x963");
    return createPublicKey({
      key: { kty: "EC", crv: "P-256", x: raw.subarray(1, 33).toString("base64url"), y: raw.subarray(33, 65).toString("base64url") },
      format: "jwk",
    });
  }

  // The opaque projection returned to clients — exactly the §3.1 fields.
  rowView(e) {
    return {
      entry_id: e.entry_id,
      vault_id: e.vault_id,
      seq: e.seq,
      committed: e.committed,
      wrapped_key: e.wrapped_key,
      blob_hash: e.blob_hash,
      created_at: e.created_at,
    };
  }
}
