import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createSign } from "node:crypto";
import { Backend } from "../src/backend.js";

// Passkey-equivalent auth (SECURITY.md §2.2 / §6.3): a device registers a P-256
// public key and proves possession by signing a server challenge. No shared
// secret is stored; a successful verify mints a session token.

// A test "device": a P-256 keypair that exports its public key in X9.63 form
// (as Apple's CryptoKit does) and signs challenges with ECDSA-SHA256 (DER).
function makeDevice() {
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = publicKey.export({ format: "jwk" });
  const x = Buffer.from(jwk.x, "base64url");
  const y = Buffer.from(jwk.y, "base64url");
  const x963 = Buffer.concat([Buffer.from([0x04]), x, y]).toString("base64");
  return {
    x963,
    sign: (challengeB64) =>
      createSign("SHA256").update(Buffer.from(challengeB64, "base64")).sign(privateKey).toString("base64"),
  };
}

function register(b, dev, { id = "dev-1", vault = "vault-A" } = {}) {
  return b.handle({ method: "POST", path: "/auth/register", body: { credential_id: id, public_key: dev.x963, vault } });
}
function challenge(b) {
  return b.handle({ method: "POST", path: "/auth/challenge" }).body.challenge;
}

test("register → challenge → signed verify mints a working session token", () => {
  const b = new Backend();
  const dev = makeDevice();
  assert.equal(register(b, dev).status, 200);

  const c = challenge(b);
  const r = b.handle({ method: "POST", path: "/auth/verify",
    body: { credential_id: "dev-1", challenge: c, signature: dev.sign(c) } });
  assert.equal(r.status, 200);
  assert.equal(r.body.vault, "vault-A");

  // The minted token authorizes its vault (no static token needed).
  const token = r.body.token;
  const created = b.handle({ method: "POST", path: "/vaults/vault-A/entries", token,
    body: { entry_id: "e1", wrapped_key: "k", blob_hash: "h" } });
  assert.equal(created.status, 201);
});

test("a bad signature is rejected", () => {
  const b = new Backend();
  const dev = makeDevice();
  register(b, dev);
  const c = challenge(b);
  const r = b.handle({ method: "POST", path: "/auth/verify",
    body: { credential_id: "dev-1", challenge: c, signature: Buffer.from("nope").toString("base64") } });
  assert.equal(r.status, 401);
});

test("another device's signature cannot impersonate a credential", () => {
  const b = new Backend();
  const dev = makeDevice();
  const attacker = makeDevice();
  register(b, dev);
  const c = challenge(b);
  const r = b.handle({ method: "POST", path: "/auth/verify",
    body: { credential_id: "dev-1", challenge: c, signature: attacker.sign(c) } });
  assert.equal(r.status, 401);
});

test("a challenge is single-use (no replay)", () => {
  const b = new Backend();
  const dev = makeDevice();
  register(b, dev);
  const c = challenge(b);
  const sig = dev.sign(c);
  assert.equal(b.handle({ method: "POST", path: "/auth/verify", body: { credential_id: "dev-1", challenge: c, signature: sig } }).status, 200);
  assert.equal(b.handle({ method: "POST", path: "/auth/verify", body: { credential_id: "dev-1", challenge: c, signature: sig } }).status, 401);
});

test("an expired challenge is rejected", () => {
  const b = new Backend();
  const dev = makeDevice();
  register(b, dev);
  const c = challenge(b);
  b.challenges.set(c, Date.now() - 1); // force expiry
  const r = b.handle({ method: "POST", path: "/auth/verify",
    body: { credential_id: "dev-1", challenge: c, signature: dev.sign(c) } });
  assert.equal(r.status, 401);
});

test("an unknown credential is rejected", () => {
  const b = new Backend();
  const c = challenge(b);
  const r = b.handle({ method: "POST", path: "/auth/verify",
    body: { credential_id: "ghost", challenge: c, signature: "x" } });
  assert.equal(r.status, 401);
});
