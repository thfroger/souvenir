import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { Backend } from "../src/backend.js";

// TESTING.md §6 — server-side authorization at the blob-and-key tier
// (SECURITY.md §6.1): client-only "hide the button" is never enough.

function putBlob(b, token, text) {
  const bytes = Buffer.from(text, "utf8");
  const hash = createHash("sha256").update(bytes).digest("hex");
  b.handle({ method: "PUT", path: `/blobs/${hash}`, token, body: { data_b64: bytes.toString("base64") } });
  return hash;
}

test("a token cannot read another vault's entries", () => {
  const b = new Backend();
  const hash = putBlob(b, "tok-A", "cipher-A");
  b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A",
    body: { entry_id: "a1", wrapped_key: "k", blob_hash: hash } });

  // B owns vault-B, not vault-A.
  const r = b.handle({ method: "GET", path: "/vaults/vault-A/entries", token: "tok-B", query: {} });
  assert.equal(r.status, 403);
});

test("a token cannot fetch a blob it does not reference (cross-account)", () => {
  const b = new Backend();
  const hash = putBlob(b, "tok-A", "cipher-A");
  b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A",
    body: { entry_id: "a1", wrapped_key: "k", blob_hash: hash } });

  // Even knowing the hash, B (vault-B) cannot pull A's blob.
  assert.equal(b.handle({ method: "GET", path: `/blobs/${hash}`, token: "tok-B" }).status, 403);
  // A can.
  assert.equal(b.handle({ method: "GET", path: `/blobs/${hash}`, token: "tok-A" }).status, 200);
});

test("writing to a vault you don't own is rejected (no membership forge)", () => {
  const b = new Backend();
  const r = b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-B",
    body: { entry_id: "x", wrapped_key: "k", blob_hash: "h" } });
  assert.equal(r.status, 403);
});

test("unauthenticated requests are rejected", () => {
  const b = new Backend();
  assert.equal(b.handle({ method: "GET", path: "/vaults/vault-A/entries", token: "nope", query: {} }).status, 403);
  assert.equal(b.handle({ method: "PUT", path: "/blobs/deadbeef", token: "", body: { data_b64: "" } }).status, 401);
});

test("blobs are content-addressed — a mismatched hash is rejected", () => {
  const b = new Backend();
  const bytes = Buffer.from("cipher", "utf8");
  const r = b.handle({ method: "PUT", path: "/blobs/not-the-real-hash", token: "tok-A",
    body: { data_b64: bytes.toString("base64") } });
  assert.equal(r.status, 400);
});

test("idempotent entry creation — same UUID does not duplicate", () => {
  const b = new Backend();
  const body = { entry_id: "dup", wrapped_key: "k", blob_hash: "h" };
  const r1 = b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A", body });
  const r2 = b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A", body });
  assert.equal(r1.status, 201);
  assert.equal(r2.status, 200);
  assert.equal(b.entries.filter((e) => e.entry_id === "dup").length, 1);
});
