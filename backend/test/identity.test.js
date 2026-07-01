import { test } from "node:test";
import assert from "node:assert/strict";
import { Backend } from "../src/backend.js";

// The identity bundle (SECURITY.md §3) lets a second trusted device of the SAME
// user adopt the vault key from the user's passphrase. The server must store it
// as opaque ciphertext, gate it per vault, and never accept cleartext.

const bundle = { salt_b64: "c2FsdA==", wrapped_mik: "bWlr", wrapped_vk: "dms=" };

test("owner can store then fetch the identity bundle (round-trip, opaque)", () => {
  const b = new Backend();
  const put = b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "tok-A", body: bundle });
  assert.equal(put.status, 200);

  const got = b.handle({ method: "GET", path: "/vaults/vault-A/identity", token: "tok-A" });
  assert.equal(got.status, 200);
  assert.deepEqual(got.body, bundle);
});

test("a token cannot read another vault's identity bundle", () => {
  const b = new Backend();
  b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "tok-A", body: bundle });
  // B owns vault-B, not vault-A.
  assert.equal(b.handle({ method: "GET", path: "/vaults/vault-A/identity", token: "tok-B" }).status, 403);
});

test("a token cannot write another vault's identity bundle", () => {
  const b = new Backend();
  assert.equal(
    b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "tok-B", body: bundle }).status,
    403,
  );
});

test("unauthenticated identity access is rejected", () => {
  const b = new Backend();
  assert.equal(b.handle({ method: "GET", path: "/vaults/vault-A/identity", token: "nope" }).status, 401);
  assert.equal(b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "", body: bundle }).status, 401);
});

test("missing identity field is rejected", () => {
  const b = new Backend();
  const r = b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "tok-A",
    body: { salt_b64: "x", wrapped_mik: "y" } });
  assert.equal(r.status, 400);
});

test("a fresh vault has no identity bundle yet (404)", () => {
  const b = new Backend();
  assert.equal(b.handle({ method: "GET", path: "/vaults/vault-A/identity", token: "tok-A" }).status, 404);
});

test("the identity endpoint refuses cleartext / special-category fields", () => {
  const b = new Backend();
  // Belt-and-suspenders: a content field smuggled alongside the bundle is refused.
  for (const bad of [{ ...bundle, title: "Léa" }, { ...bundle, civil_date: "2024-01-01" }, { ...bundle, child: "Noé" }]) {
    const r = b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "tok-A", body: bad });
    assert.equal(r.status, 400, `expected refusal for ${JSON.stringify(Object.keys(bad))}`);
  }
});

test("an unknown field on the identity endpoint is rejected", () => {
  const b = new Backend();
  const r = b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "tok-A",
    body: { ...bundle, extra: "nope" } });
  assert.equal(r.status, 400);
});

test("re-enrolling (password change) overwrites the owner's bundle", () => {
  const b = new Backend();
  b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "tok-A", body: bundle });
  const next = { salt_b64: "bmV3c2FsdA==", wrapped_mik: "bmV3bWlr", wrapped_vk: "bmV3dms=" };
  assert.equal(b.handle({ method: "PUT", path: "/vaults/vault-A/identity", token: "tok-A", body: next }).status, 200);
  assert.deepEqual(b.handle({ method: "GET", path: "/vaults/vault-A/identity", token: "tok-A" }).body, next);
});
