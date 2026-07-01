import { test } from "node:test";
import assert from "node:assert/strict";
import { Backend } from "../src/backend.js";

// The social-recovery bundle (SECURITY.md §5): MIK-under-RK + VK-under-MIK. The
// RK's Shamir shares go to guardians out-of-band and never reach the server; the
// server stores only opaque ciphertext, gated per vault.

const bundle = { wrapped_mik_rk: "bWlrLXVuZGVyLXJr", wrapped_vk: "dmstdW5kZXItbWlr" };

test("owner can store then fetch the recovery bundle (round-trip, opaque)", () => {
  const b = new Backend();
  assert.equal(b.handle({ method: "PUT", path: "/vaults/vault-A/recovery", token: "tok-A", body: bundle }).status, 200);
  const got = b.handle({ method: "GET", path: "/vaults/vault-A/recovery", token: "tok-A" });
  assert.equal(got.status, 200);
  assert.deepEqual(got.body, bundle);
});

test("a token cannot read or write another vault's recovery bundle", () => {
  const b = new Backend();
  b.handle({ method: "PUT", path: "/vaults/vault-A/recovery", token: "tok-A", body: bundle });
  assert.equal(b.handle({ method: "GET", path: "/vaults/vault-A/recovery", token: "tok-B" }).status, 403);
  assert.equal(b.handle({ method: "PUT", path: "/vaults/vault-A/recovery", token: "tok-B", body: bundle }).status, 403);
});

test("unauthenticated recovery access is rejected", () => {
  const b = new Backend();
  assert.equal(b.handle({ method: "GET", path: "/vaults/vault-A/recovery", token: "nope" }).status, 401);
  assert.equal(b.handle({ method: "PUT", path: "/vaults/vault-A/recovery", token: "", body: bundle }).status, 401);
});

test("a fresh vault has no recovery bundle yet (404)", () => {
  const b = new Backend();
  assert.equal(b.handle({ method: "GET", path: "/vaults/vault-A/recovery", token: "tok-A" }).status, 404);
});

test("missing recovery field is rejected", () => {
  const b = new Backend();
  assert.equal(
    b.handle({ method: "PUT", path: "/vaults/vault-A/recovery", token: "tok-A", body: { wrapped_vk: "x" } }).status,
    400,
  );
});

test("the recovery endpoint refuses cleartext / a share / unknown fields", () => {
  const b = new Backend();
  // A raw Shamir share must never be sent to the server, nor any content field.
  for (const bad of [{ ...bundle, share: "abc" }, { ...bundle, child: "Léa" }, { ...bundle, extra: "x" }]) {
    assert.equal(
      b.handle({ method: "PUT", path: "/vaults/vault-A/recovery", token: "tok-A", body: bad }).status,
      400,
      `expected refusal for ${JSON.stringify(Object.keys(bad))}`,
    );
  }
});

test("re-arming recovery (new guardians / rotated RK) overwrites the bundle", () => {
  const b = new Backend();
  b.handle({ method: "PUT", path: "/vaults/vault-A/recovery", token: "tok-A", body: bundle });
  const next = { wrapped_mik_rk: "bmV3", wrapped_vk: "bmV3dms=" };
  assert.equal(b.handle({ method: "PUT", path: "/vaults/vault-A/recovery", token: "tok-A", body: next }).status, 200);
  assert.deepEqual(b.handle({ method: "GET", path: "/vaults/vault-A/recovery", token: "tok-A" }).body, next);
});
