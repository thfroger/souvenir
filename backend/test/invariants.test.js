import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { Backend } from "../src/backend.js";

// TESTING.md §2 — invariant suite. These are the audit proof: they make
// SECURITY.md §1 mechanically verifiable. An invariant that is not tested drifts.

const ALLOWED_ROW_FIELDS = new Set([
  "entry_id", "vault_id", "seq", "committed", "wrapped_key", "blob_hash", "created_at",
]);
const CONTENT_MARKERS = ["premiers pas", "papa", "78 cm", "Léa", "maladie"];

// A realistic opaque payload the client would send: ciphertext bytes + a wrapped
// key. The server must treat both as opaque and never see any plaintext.
function opaqueBlob() {
  const bytes = Buffer.from("OPAQUE-CIPHERTEXT-9f3a" + Math.random(), "utf8");
  const hash = createHash("sha256").update(bytes).digest("hex");
  return { bytes, hash, data_b64: bytes.toString("base64") };
}

function seedEntry(b, { token = "tok-A", vault = "vault-A", wrapped_key = "V1JBUFBFRA==" } = {}) {
  const blob = opaqueBlob();
  b.handle({ method: "PUT", path: `/blobs/${blob.hash}`, token, body: { data_b64: blob.data_b64 } });
  const r = b.handle({
    method: "POST", path: `/vaults/${vault}/entries`, token,
    body: { entry_id: "11111111-1111-1111-1111-111111111111", wrapped_key, blob_hash: blob.hash },
  });
  return { blob, r };
}

test("no endpoint returns cleartext — only opaque rows + ciphertext blobs", () => {
  const b = new Backend();
  const { blob, r } = seedEntry(b);
  assert.equal(r.status, 201);
  // Created row carries only the §3.1 opaque fields.
  for (const k of Object.keys(r.body)) assert.ok(ALLOWED_ROW_FIELDS.has(k), `unexpected field ${k}`);

  b.handle({ method: "POST", path: `/vaults/vault-A/entries/${r.body.entry_id}/commit`, token: "tok-A" });
  const delta = b.handle({ method: "GET", path: "/vaults/vault-A/entries", token: "tok-A", query: {} });
  for (const row of delta.body.entries) {
    for (const k of Object.keys(row)) assert.ok(ALLOWED_ROW_FIELDS.has(k), `unexpected field ${k}`);
  }

  // The blob comes back byte-identical to what we uploaded (opaque), nothing more.
  const got = b.handle({ method: "GET", path: `/blobs/${blob.hash}`, token: "tok-A" });
  assert.equal(got.body.data_b64, blob.data_b64);

  // No response anywhere leaks a content marker.
  const everything = JSON.stringify([r.body, delta.body, got.body]);
  for (const m of CONTENT_MARKERS) assert.ok(!everything.includes(m), `leaked marker ${m}`);
});

test("no endpoint accepts content without a wrapped key", () => {
  const b = new Backend();
  const base = { entry_id: "e1", blob_hash: "abc" };
  // Missing wrapped_key.
  assert.equal(b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A", body: base }).status, 400);
  // A content/special-category field is refused outright.
  assert.equal(b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A",
    body: { ...base, wrapped_key: "k", title: "premiers pas" } }).status, 400);
  assert.equal(b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A",
    body: { ...base, wrapped_key: "k", civil_date: "2026-06-23", tag: "maladie" } }).status, 400);
  // Any unknown field is refused (strict allowlist).
  assert.equal(b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A",
    body: { ...base, wrapped_key: "k", foo: 1 } }).status, 400);
});

test("no civil date / tag / content is ever stored server-side", () => {
  const b = new Backend();
  seedEntry(b);
  for (const row of b.entries) {
    for (const k of Object.keys(row)) assert.ok(ALLOWED_ROW_FIELDS.has(k), `stored field ${k} not opaque`);
  }
});

test("no log contains vault content, wrapped keys, or blob bytes", () => {
  const b = new Backend();
  const { blob } = seedEntry(b, { wrapped_key: "SUPER-WRAPPED-KEY" });
  b.handle({ method: "GET", path: "/vaults/vault-A/entries", token: "tok-A", query: {} });
  b.handle({ method: "GET", path: `/blobs/${blob.hash}`, token: "tok-A" });

  const logs = JSON.stringify(b.logs);
  assert.ok(!logs.includes("SUPER-WRAPPED-KEY"), "wrapped key leaked into logs");
  assert.ok(!logs.includes(blob.data_b64), "blob bytes leaked into logs");
  for (const m of CONTENT_MARKERS) assert.ok(!logs.includes(m), `content marker ${m} in logs`);
  // Logs carry only an event type + opaque ids (SECURITY.md §6.2).
  const allowed = new Set(["event", "hash", "entry_id", "vault_id", "seq", "since", "count"]);
  for (const e of b.logs) for (const k of Object.keys(e)) assert.ok(allowed.has(k), `log field ${k} not allowed`);
});

test("no secret / private key / backdoor embedded in the backend source (SECURITY §1.7)", () => {
  const srcDir = join(dirname(fileURLToPath(import.meta.url)), "..", "src");
  const banned = [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, /\bAKIA[0-9A-Z]{16}\b/, /\bbackdoor\b/i, /secret\s*[:=]\s*["'][^"']+["']/i];
  for (const f of readdirSync(srcDir)) {
    const text = readFileSync(join(srcDir, f), "utf8");
    for (const re of banned) assert.ok(!re.test(text), `${f} matches banned pattern ${re}`);
  }
});
