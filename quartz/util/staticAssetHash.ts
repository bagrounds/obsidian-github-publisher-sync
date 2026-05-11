import { createHash } from "crypto";
import fs from "fs";
import path from "path";
import { QUARTZ, joinSegments } from "./path";

// Shared content-hash cache for files under `quartz/static/`.
//
// The Static emitter substitutes the `__WORD_METER_VERSION__` placeholder
// in JS files with a truncated SHA-256 of the source bytes and emits the
// substituted file at both its original path and a content-addressed path
// `<basename>.<hash>.<ext>`. The CacheBustStaticAssets transformer reuses
// these hashes to rewrite `<script src="/static/foo.js">` references in the
// rendered HTML, so the browser always fetches the latest build and can
// never serve a stale cached copy after a deploy.
//
// The same hash H is used in three places — embedded in the file as its
// self-reported version, used as the `.<H>.` segment in the emitted
// filename, and substituted into `<script src>` URLs in the rendered HTML.
// H is deterministic from the source bytes (placeholder included), so all
// three always agree.

const HASH_LENGTH_CHARS = 12;

const VERSION_PLACEHOLDER = "__WORD_METER_VERSION__";

interface CachedAsset {
  hash: string;
  bytes: Buffer;
}

const cache = new Map<string, CachedAsset>();

const computeHash = (bytes: Buffer): string =>
  createHash("sha256").update(bytes).digest("hex").slice(0, HASH_LENGTH_CHARS);

const substituteVersion = (source: Buffer, hash: string): Buffer => {
  const text = source.toString("utf8");
  if (!text.includes(VERSION_PLACEHOLDER)) return source;
  return Buffer.from(text.replaceAll(VERSION_PLACEHOLDER, hash), "utf8");
};

const loadAsset = (relativePath: string): CachedAsset => {
  const absolute = joinSegments(QUARTZ, "static", relativePath);
  const raw = fs.readFileSync(absolute);
  // Hash the source bytes (placeholder included). The same hash is then
  // substituted into the file, used in the emitted filename, and used in
  // the rewritten `<script src>` URL — so all three always agree.
  const hash = computeHash(raw);
  const bytes = substituteVersion(raw, hash);
  return { hash, bytes };
};

export const getStaticAssetHash = (relativePath: string): string | null => {
  const normalized = relativePath.replace(/^\/+/, "");
  if (!normalized.endsWith(".js")) return null;
  if (cache.has(normalized)) return cache.get(normalized)!.hash;
  try {
    const asset = loadAsset(normalized);
    cache.set(normalized, asset);
    return asset.hash;
  } catch (_err) {
    return null;
  }
};

export const getStaticAssetBytes = (relativePath: string): Buffer | null => {
  const normalized = relativePath.replace(/^\/+/, "");
  if (cache.has(normalized)) return cache.get(normalized)!.bytes;
  try {
    const asset = loadAsset(normalized);
    cache.set(normalized, asset);
    return asset.bytes;
  } catch (_err) {
    return null;
  }
};

// Returns the same path with `.<hash>` injected before the extension, e.g.
// `word-meter.js` → `word-meter.abc123def456.js`. Returns the original path
// unchanged when the asset cannot be hashed (non-existent or non-JS).
export const hashedAssetPath = (relativePath: string): string => {
  const hash = getStaticAssetHash(relativePath);
  if (!hash) return relativePath;
  const ext = path.extname(relativePath);
  const stem = relativePath.slice(0, relativePath.length - ext.length);
  return `${stem}.${hash}${ext}`;
};

// Test-only: clear the in-memory cache so tests that mutate static files
// can observe fresh hashes between cases.
export const __resetStaticAssetHashCacheForTests = () => cache.clear();
