/**
 * Tests for scripts/lib/retry.ts — Retry utility.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { withRetry, TRANSIENT_HTTP_CODES, isTransientError, extractHttpCode } from "../lib/retry.ts";

describe("TRANSIENT_HTTP_CODES", () => {
  it("includes 429 (rate limit)", () => {
    assert.ok(TRANSIENT_HTTP_CODES.has(429));
  });

  it("includes 502, 503, 504 (server errors)", () => {
    assert.ok(TRANSIENT_HTTP_CODES.has(502));
    assert.ok(TRANSIENT_HTTP_CODES.has(503));
    assert.ok(TRANSIENT_HTTP_CODES.has(504));
  });

  it("does not include 400 or 401", () => {
    assert.ok(!TRANSIENT_HTTP_CODES.has(400));
    assert.ok(!TRANSIENT_HTTP_CODES.has(401));
  });
});

describe("extractHttpCode", () => {
  it("extracts code from error-like object", () => {
    assert.equal(extractHttpCode({ code: 503 }), 503);
  });

  it("returns undefined for plain Error", () => {
    assert.equal(extractHttpCode(new Error("test")), undefined);
  });

  it("returns undefined for non-object", () => {
    assert.equal(extractHttpCode("string error"), undefined);
    assert.equal(extractHttpCode(null), undefined);
    assert.equal(extractHttpCode(undefined), undefined);
  });
});

describe("isTransientError", () => {
  it("returns true for transient HTTP codes", () => {
    assert.equal(isTransientError({ code: 503 }), true);
    assert.equal(isTransientError({ code: 429 }), true);
  });

  it("returns false for non-transient codes", () => {
    assert.equal(isTransientError({ code: 400 }), false);
    assert.equal(isTransientError({ code: 401 }), false);
  });

  it("returns false when no code present", () => {
    assert.equal(isTransientError(new Error("test")), false);
  });
});

describe("withRetry", () => {
  it("returns result on first success", async () => {
    const result = await withRetry(async () => 42);
    assert.equal(result, 42);
  });

  it("retries on transient error and succeeds", async () => {
    let attempt = 0;
    const result = await withRetry(
      async () => {
        attempt++;
        if (attempt === 1) throw Object.assign(new Error("503"), { code: 503 });
        return "success";
      },
      { maxRetries: 2, baseDelayMs: 1 },
    );
    assert.equal(result, "success");
    assert.equal(attempt, 2);
  });

  it("throws immediately on non-transient error", async () => {
    await assert.rejects(
      () => withRetry(async () => { throw new Error("bad request"); }, { maxRetries: 3 }),
      { message: "bad request" },
    );
  });

  it("calls onRetry callback", async () => {
    const retries: number[] = [];
    let attempt = 0;
    await withRetry(
      async () => {
        attempt++;
        if (attempt <= 2) throw Object.assign(new Error("503"), { code: 503 });
        return "ok";
      },
      {
        maxRetries: 3,
        baseDelayMs: 1,
        onRetry: (_err, attemptNum) => retries.push(attemptNum),
      },
    );
    assert.deepEqual(retries, [1, 2]);
  });

  it("exhausts retries and throws", async () => {
    await assert.rejects(
      () => withRetry(
        async () => { throw Object.assign(new Error("503"), { code: 503 }); },
        { maxRetries: 2, baseDelayMs: 1 },
      ),
      { message: "503" },
    );
  });
});
