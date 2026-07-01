import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, resolve, extname, basename } from "node:path";

// Static dependency / SDK audit (STORE_COMPLIANCE.md §8 rows C3/C4/C5, N2–N6).
// The zero-knowledge and no-tracking posture must be enforceable, not just
// asserted in a form: no analytics, crash, ads, tracking, ML/vision or speech
// SDK may enter the codebase without also amending the compliance doc. This runs
// in the blocking `invariants` CI job.
//
// It scans ONLY source / project / manifest files — never the .md corpus and
// never this test — so the denylist tokens can be named here and in
// STORE_COMPLIANCE.md without tripping the audit.

const REPO = resolve(import.meta.dirname, "..", "..");
const SCAN_ROOTS = ["ios", "android"];
const SCAN_EXT = new Set([".swift", ".kt", ".java", ".gradle", ".xml", ".plist", ".pbxproj", ".resolved", ".entitlements"]);
const SKIP_DIRS = new Set(["node_modules", ".git", ".build", "DerivedData", "build", ".swiftpm", "Pods"]);
const SELF = basename(import.meta.filename);

// Precise tokens only — unambiguous SDK names, import statements or symbols, so a
// prose word (e.g. "adjust", "segment") never causes a false positive.
const FORBIDDEN = [
  // analytics / product telemetry (N5)
  /\bFirebaseAnalytics\b/, /\bGoogleAnalytics\b/, /\bAmplitude\b/, /\bMixpanel\b/,
  /\bcom\.segment\b/, /\bDatadog\b/, /\bHeapAnalytics\b/,
  // crash reporting (N6)
  /\bCrashlytics\b/, /\bimport Sentry\b/, /\bSentrySDK\b/, /\bBugsnag\b/,
  // advertising / attribution (N3)
  /\bGoogleMobileAds\b/, /\bAdMob\b/, /\bAppLovin\b/, /\bIronSource\b/,
  /\bAppsFlyer\b/, /\bAdjustSdk\b/, /\bFBSDK/, /\bFacebookAds\b/,
  // tracking identifiers (N3)
  /\bATTrackingManager\b/, /\bASIdentifierManager\b/, /\badvertisingIdentifier\b/,
  /\bcom\.google\.android\.gms\.permission\.AD_ID\b/,
  // ML / computer vision over content (N2)
  /\bimport Vision\b/, /\bimport CoreML\b/, /\bVNDetect\w+/, /\bVNGenerateImageFeaturePrint\b/,
  // speech / transcription (N4)
  /\bimport Speech\b/, /\bSFSpeechRecognizer\b/, /\bWhisper\b/,
];

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (name !== SELF && (SCAN_EXT.has(extname(name)) || name.endsWith(".pbxproj"))) out.push(p);
  }
  return out;
}

const files = SCAN_ROOTS.flatMap((r) => walk(join(REPO, r)));

test("audit scans a non-empty set of source/project files", () => {
  assert.ok(files.length > 0, "expected to find iOS/Android source or project files to audit");
});

test("no analytics / crash / ads / tracking / ML / speech SDK is present", () => {
  const hits = [];
  for (const f of files) {
    const text = readFileSync(f, "utf8");
    for (const rx of FORBIDDEN) {
      const m = text.match(rx);
      if (m) hits.push(`${f.replace(REPO + "/", "")}: ${m[0]}`);
    }
  }
  assert.deepEqual(hits, [], `forbidden SDK/identifier(s) found — add the data row to STORE_COMPLIANCE.md §2/§8 first:\n${hits.join("\n")}`);
});

// Static guard for EXIF stripping (C9 / N1). Not a runtime EXIF test (that needs
// an iOS test target) — it pins that the strip function exists and is on the
// photo ingest path, so the pipeline can't silently start uploading raw images.
test("every image ingest strips EXIF client-side", () => {
  const store = join(REPO, "ios", "Souvenir", "MemoryStore.swift");
  assert.ok(existsSync(store), "MemoryStore.swift not found");
  const src = readFileSync(store, "utf8");
  assert.match(src, /func stripExifJPEG\b/, "stripExifJPEG must exist");
  // addPhoto is the only entry point taking raw image bytes; it must strip first.
  assert.match(src, /ImageTools\.stripExifJPEG\(imageData\)/,
    "addPhoto must route imageData through stripExifJPEG before sealing");
});
