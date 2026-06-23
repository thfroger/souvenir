# backend — the deliberately dumb store

An encrypted-blob + opaque-metadata store (`ARCHITECTURE.md §1`, `§3.1`). It does
**no** content processing, **no** indexing, **no** per-request crypto, and can
never see plaintext: an entry row carries only a wrapped key + a blob hash. This
is the skeleton (in-memory JS, no deps); a real deployment is Postgres + object
storage, but the **contract and the invariants** are what matter here.

## Run

```sh
cd backend
node --test      # invariant (TESTING.md §2) + authorization (§6) suites
node src/server.js   # run the HTTP server (PORT=8787)
```

No dependencies — plain Node ESM, so CI is just `node --test` (blocking job).

## What the tests prove

- **No endpoint returns cleartext** — only opaque rows + ciphertext blobs.
- **No endpoint accepts content without a wrapped key** — content / special-category
  fields (title, civil date, tag, child, measure…) are refused; strict allowlist.
- **Nothing content-y is stored server-side** — rows carry only the §3.1 fields.
- **Logs are content-free** — event type + opaque ids only (`SECURITY.md §6.2`):
  never a wrapped key, never blob bytes, never content.
- **No secret / private key / backdoor** in the source (`SECURITY.md §1.7`).
- **Authorization at the blob-and-key tier** (`§6.1`): no cross-account reads, no
  fetching a blob you don't reference, no membership forge; content-addressed
  blobs; idempotent entry creation.

## Not here yet

Persistence (Postgres + object storage), the commit janitor for orphan blobs
(`ARCHITECTURE.md §5`), and the co-parent / shared-vault authorization (V2).
