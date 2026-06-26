import { createServer } from "node:http";
import { Backend } from "./backend.js";

// Thin HTTP wrapper around the dumb Backend. The logic and the invariants live
// in backend.js / the tests; this just maps HTTP to handle().
const backend = new Backend();

const server = createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  const token = (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
  const query = Object.fromEntries(url.searchParams);

  let raw = "";
  req.on("data", (c) => (raw += c));
  req.on("end", () => {
    let body;
    if (raw) {
      try { body = JSON.parse(raw); } catch { res.writeHead(400).end('{"error":"bad_json"}'); return; }
    }
    const { status, body: out } = backend.handle({ method: req.method, path: url.pathname, query, token, body });
    // Dev access log: method, path, status only — no body, no query, no headers.
    // Paths carry opaque ids/hashes, never cleartext or special-category content
    // (keeps the "aucun contenu dans les logs" invariant — TESTING.md §2).
    console.log(`${req.method} ${url.pathname} -> ${status}`);
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify(out));
  });
});

const port = process.env.PORT ?? 8787;
server.listen(port, () => console.log(`souvenir dumb backend on :${port}`));
