import test, { describe } from "node:test";
import assert from "node:assert";
import {
  getStaticAssetHash,
  hashedAssetPath,
  __resetStaticAssetHashCacheForTests,
} from "./staticAssetHash";

describe("staticAssetHash", () => {
  test("returns a 12-char hex hash for an existing JS asset", () => {
    __resetStaticAssetHashCacheForTests();
    const hash = getStaticAssetHash("word-meter.js");
    assert.ok(hash, "expected a hash for word-meter.js");
    assert.match(hash!, /^[0-9a-f]{12}$/);
  });

  test("returns the same hash on repeated calls (deterministic)", () => {
    __resetStaticAssetHashCacheForTests();
    const first = getStaticAssetHash("word-meter.js");
    const second = getStaticAssetHash("word-meter.js");
    assert.strictEqual(first, second);
  });

  test("returns null for non-JS asset paths", () => {
    __resetStaticAssetHashCacheForTests();
    assert.strictEqual(getStaticAssetHash("favicon.ico"), null);
  });

  test("returns null for non-existent assets", () => {
    __resetStaticAssetHashCacheForTests();
    assert.strictEqual(getStaticAssetHash("does-not-exist.js"), null);
  });

  test("hashedAssetPath injects the hash before the extension", () => {
    __resetStaticAssetHashCacheForTests();
    const hashed = hashedAssetPath("word-meter.js");
    assert.match(hashed, /^word-meter\.[0-9a-f]{12}\.js$/);
  });

  test("hashedAssetPath leaves un-hashable assets unchanged", () => {
    __resetStaticAssetHashCacheForTests();
    assert.strictEqual(hashedAssetPath("favicon.ico"), "favicon.ico");
    assert.strictEqual(
      hashedAssetPath("does-not-exist.js"),
      "does-not-exist.js",
    );
  });
});
