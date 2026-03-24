import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { isRetriableError, isQuotaError, generateSlug } from "./generate-blog-post.ts";

// ---------------------------------------------------------------------------
// isQuotaError
// ---------------------------------------------------------------------------

describe("isQuotaError", () => {
  it("detects 429 in error message", () => {
    assert.ok(isQuotaError({ message: "Error 429: RESOURCE_EXHAUSTED" }));
  });

  it("detects RESOURCE_EXHAUSTED", () => {
    assert.ok(isQuotaError({ message: "RESOURCE_EXHAUSTED" }));
  });

  it("detects quota keyword", () => {
    assert.ok(isQuotaError({ message: "API quota exceeded" }));
  });

  it("returns false for non-quota errors", () => {
    assert.ok(!isQuotaError({ message: "Internal server error" }));
  });

  it("returns false for null/undefined", () => {
    assert.ok(!isQuotaError(null));
    assert.ok(!isQuotaError(undefined));
  });

  it("returns false for non-objects", () => {
    assert.ok(!isQuotaError("string error"));
    assert.ok(!isQuotaError(42));
  });
});

// ---------------------------------------------------------------------------
// isRetriableError
// ---------------------------------------------------------------------------

describe("isRetriableError", () => {
  it("retries on 503 status", () => {
    assert.ok(isRetriableError({ status: 503, message: "Service Unavailable" }));
  });

  it("retries on 502 status", () => {
    assert.ok(isRetriableError({ status: 502, message: "Bad Gateway" }));
  });

  it("retries on 500 status", () => {
    assert.ok(isRetriableError({ status: 500, message: "Internal Server Error" }));
  });

  it("retries on 504 status", () => {
    assert.ok(isRetriableError({ status: 504, message: "Gateway Timeout" }));
  });

  it("retries on 429 (rate limit)", () => {
    assert.ok(isRetriableError({ status: 429, message: "Rate limited" }));
  });

  it("retries on UNAVAILABLE in message", () => {
    assert.ok(isRetriableError({ message: "UNAVAILABLE: service temporarily unavailable" }));
  });

  it("retries on INTERNAL in message", () => {
    assert.ok(isRetriableError({ message: "INTERNAL: unknown error" }));
  });

  it("retries on 503 in message without status field", () => {
    assert.ok(isRetriableError({ message: "Error 503: service unavailable" }));
  });

  it("does NOT retry on 400 Bad Request", () => {
    assert.ok(!isRetriableError({ status: 400, message: "Bad Request" }));
  });

  it("does NOT retry on 404 Not Found", () => {
    assert.ok(!isRetriableError({ status: 404, message: "Model not found" }));
  });

  it("does NOT retry on 403 Forbidden", () => {
    assert.ok(!isRetriableError({ status: 403, message: "Forbidden" }));
  });

  it("returns false for null/undefined", () => {
    assert.ok(!isRetriableError(null));
    assert.ok(!isRetriableError(undefined));
  });
});

// ---------------------------------------------------------------------------
// generateSlug (existing tests kept)
// ---------------------------------------------------------------------------

describe("generateSlug", () => {
  it("generates a slug from a title", () => {
    assert.equal(generateSlug("Hello World"), "hello-world");
  });

  it("strips emoji from title", () => {
    assert.equal(generateSlug("🚀 Launch Day"), "launch-day");
  });

  it("throws on empty slug", () => {
    assert.throws(() => generateSlug("🚀🎉"));
  });
});
