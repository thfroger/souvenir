import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { Backend } from "../src/backend.js";

// TESTING.md §4 — the orphan-blob janitor (ARCHITECTURE.md §5): a blob with no
// committed metadata is collected after N hours; a committed blob never is.

function putBlob(b, text) {
  const bytes = Buffer.from(text, "utf8");
  const hash = createHash("sha256").update(bytes).digest("hex");
  b.handle({ method: "PUT", path: `/blobs/${hash}`, token: "tok-A", body: { data_b64: bytes.toString("base64") } });
  return hash;
}

function entry(b, hash, { commit = false, id = "e-" + hash.slice(0, 6) } = {}) {
  b.handle({ method: "POST", path: "/vaults/vault-A/entries", token: "tok-A",
    body: { entry_id: id, wrapped_key: "k", blob_hash: hash } });
  if (commit) b.handle({ method: "POST", path: `/vaults/vault-A/entries/${id}/commit`, token: "tok-A" });
}

function backdate(b, hash, hours) {
  b.blobs.get(hash).uploadedAt = Date.now() - hours * 3600 * 1000;
}

test("an orphan blob (no metadata) older than N hours is collected", () => {
  const b = new Backend();
  const hash = putBlob(b, "orphan");
  backdate(b, hash, 48);
  assert.deepEqual(b.collectOrphans({ ttlHours: 24 }), [hash]);
  assert.equal(b.blobs.has(hash), false);
});

test("a committed blob is never collected, even when old", () => {
  const b = new Backend();
  const hash = putBlob(b, "kept");
  entry(b, hash, { commit: true });
  backdate(b, hash, 1000);
  assert.deepEqual(b.collectOrphans({ ttlHours: 24 }), []);
  assert.equal(b.blobs.has(hash), true);
});

test("a recent orphan is spared (grace period)", () => {
  const b = new Backend();
  const hash = putBlob(b, "fresh"); // uploadedAt ~ now
  assert.deepEqual(b.collectOrphans({ ttlHours: 24 }), []);
  assert.equal(b.blobs.has(hash), true);
});

test("a blob with only a PENDING (uncommitted) entry is collected after N hours", () => {
  const b = new Backend();
  const hash = putBlob(b, "pending");
  entry(b, hash, { commit: false }); // metadata exists but not committed
  backdate(b, hash, 48);
  assert.deepEqual(b.collectOrphans({ ttlHours: 24 }), [hash]);
  assert.equal(b.blobs.has(hash), false);
});

test("committing in time protects a previously-pending blob", () => {
  const b = new Backend();
  const hash = putBlob(b, "rescued");
  entry(b, hash, { commit: false });
  backdate(b, hash, 48);
  b.handle({ method: "POST", path: `/vaults/vault-A/entries/e-${hash.slice(0, 6)}/commit`, token: "tok-A" });
  assert.deepEqual(b.collectOrphans({ ttlHours: 24 }), []);
  assert.equal(b.blobs.has(hash), true);
});
