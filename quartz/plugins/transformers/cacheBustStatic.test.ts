import test, { describe } from "node:test";
import assert from "node:assert";
import { rewriteStaticScriptSrc } from "./cacheBustStatic";
import { __resetStaticAssetHashCacheForTests } from "../../util/staticAssetHash";

describe("CacheBustStaticAssets — rewriteStaticScriptSrc", () => {
  test("rewrites a /static/<name>.js URL to include the content hash", () => {
    __resetStaticAssetHashCacheForTests();
    const rewritten = rewriteStaticScriptSrc("/static/word-meter.js");
    assert.match(rewritten ?? "", /^\/static\/word-meter\.[0-9a-f]{12}\.js$/);
  });

  test("preserves existing query strings on the rewritten URL", () => {
    __resetStaticAssetHashCacheForTests();
    const rewritten = rewriteStaticScriptSrc("/static/word-meter.js?cb=1");
    assert.match(
      rewritten ?? "",
      /^\/static\/word-meter\.[0-9a-f]{12}\.js\?cb=1$/,
    );
  });

  test("returns null for non-/static URLs (external scripts, etc.)", () => {
    __resetStaticAssetHashCacheForTests();
    assert.strictEqual(
      rewriteStaticScriptSrc("https://example.com/x.js"),
      null,
    );
    assert.strictEqual(rewriteStaticScriptSrc("/other/word-meter.js"), null);
    assert.strictEqual(rewriteStaticScriptSrc(""), null);
  });

  test("returns null for non-.js extensions", () => {
    __resetStaticAssetHashCacheForTests();
    assert.strictEqual(rewriteStaticScriptSrc("/static/word-meter.css"), null);
  });

  test("returns null when the underlying asset cannot be hashed", () => {
    __resetStaticAssetHashCacheForTests();
    assert.strictEqual(
      rewriteStaticScriptSrc("/static/does-not-exist.js"),
      null,
    );
  });

  test("returns null when src is not a string", () => {
    __resetStaticAssetHashCacheForTests();
    assert.strictEqual(rewriteStaticScriptSrc(undefined), null);
    assert.strictEqual(rewriteStaticScriptSrc(null), null);
    assert.strictEqual(rewriteStaticScriptSrc(42), null);
  });
});
