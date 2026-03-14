/**
 * Tests for scripts/lib/gemini.ts — AI text generation and rate limit handling.
 *
 * Covers:
 * - parseRetryDelay: extracting retry delays from various error formats
 * - isRateLimitError: detecting 429 / RESOURCE_EXHAUSTED errors
 * - buildGeminiPrompt: backward-compat shim
 * - dual-model architecture verification
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { parseRetryDelay, isRateLimitError, buildGeminiPrompt } from "./gemini.ts";
import type { ReflectionData } from "./types.ts";

// --- parseRetryDelay ---

describe("parseRetryDelay", () => {
  it("parses retryDelay from error message with seconds", () => {
    const error = new Error('retryDelay: "14s"');
    assert.equal(parseRetryDelay(error), 14_000);
  });

  it("parses retryDelay from JSON-like message", () => {
    const error = new Error('{"retryDelay":"30s"}');
    assert.equal(parseRetryDelay(error), 30_000);
  });

  it("parses retryDelay from error details array", () => {
    const error = {
      message: "RESOURCE_EXHAUSTED",
      errorDetails: [
        { "@type": "type.googleapis.com/google.rpc.RetryInfo", retryDelay: "20s" },
      ],
    };
    assert.equal(parseRetryDelay(error), 20_000);
  });

  it("parses Retry-After header", () => {
    const error = {
      message: "rate limited",
      headers: { "retry-after": "10" },
    };
    assert.equal(parseRetryDelay(error), 10_000);
  });

  it("returns null for error without retry info", () => {
    assert.equal(parseRetryDelay(new Error("generic error")), null);
  });

  it("returns null for null input", () => {
    assert.equal(parseRetryDelay(null), null);
  });

  it("returns null for undefined input", () => {
    assert.equal(parseRetryDelay(undefined), null);
  });

  it("returns null for non-object input", () => {
    assert.equal(parseRetryDelay("string error"), null);
    assert.equal(parseRetryDelay(42), null);
  });

  it("prefers message-embedded delay over headers", () => {
    const error = {
      message: 'retryDelay "5s"',
      headers: { "retry-after": "30" },
    };
    assert.equal(parseRetryDelay(error), 5_000);
  });

  it("falls back to errorDetails when message has no delay", () => {
    const error = {
      message: "quota exceeded",
      errorDetails: [
        { retryDelay: "8s" },
      ],
    };
    assert.equal(parseRetryDelay(error), 8_000);
  });
});

// --- isRateLimitError ---

describe("isRateLimitError", () => {
  it("detects status 429", () => {
    assert.ok(isRateLimitError({ status: 429, message: "" }));
  });

  it("detects RESOURCE_EXHAUSTED in message", () => {
    assert.ok(isRateLimitError(new Error("RESOURCE_EXHAUSTED: You exceeded your quota")));
  });

  it("detects 429 in message", () => {
    assert.ok(isRateLimitError(new Error("[429 Too Many Requests]")));
  });

  it("detects quota in message", () => {
    assert.ok(isRateLimitError(new Error("You exceeded your current quota")));
  });

  it("returns false for generic errors", () => {
    assert.equal(isRateLimitError(new Error("network timeout")), false);
  });

  it("returns false for null", () => {
    assert.equal(isRateLimitError(null), false);
  });

  it("returns false for undefined", () => {
    assert.equal(isRateLimitError(undefined), false);
  });

  it("returns false for non-object", () => {
    assert.equal(isRateLimitError("error string"), false);
    assert.equal(isRateLimitError(42), false);
  });
});

// --- buildGeminiPrompt (backward compat) ---

describe("buildGeminiPrompt", () => {
  const reflection: ReflectionData = {
    date: "2026-03-10",
    title: "Test Title",
    url: "https://example.com/test",
    body: "Some content about testing.",
    filePath: "reflections/2026-03-10.md",
    hasTweetSection: false,
    hasBlueskySection: false,
    hasMastodonSection: false,
  };

  it("returns a PromptPair with system and user", () => {
    const prompt = buildGeminiPrompt(reflection);
    assert.ok(prompt.system.length > 0);
    assert.ok(prompt.user.length > 0);
  });

  it("builds the tags prompt (backward compat)", () => {
    const prompt = buildGeminiPrompt(reflection);
    assert.ok(prompt.system.includes("topic tags") || prompt.system.includes("social media"));
  });
});

// --- Dual-model architecture ---

describe("dual-model architecture", () => {
  it("DEFAULT_QUESTION_MODEL is different from DEFAULT_GEMINI_MODEL", async () => {
    const { DEFAULT_GEMINI_MODEL, DEFAULT_QUESTION_MODEL } = await import("./types.ts");
    assert.notEqual(DEFAULT_GEMINI_MODEL, DEFAULT_QUESTION_MODEL);
    assert.equal(DEFAULT_GEMINI_MODEL, "gemma-3-27b-it");
    assert.equal(DEFAULT_QUESTION_MODEL, "gemini-3.1-flash-lite-preview");
  });

  it("GeminiConfig includes questionModel field", async () => {
    const { validateEnvironment } = await import("./env.ts");
    const saved = {
      GEMINI_API_KEY: process.env.GEMINI_API_KEY,
      OBSIDIAN_AUTH_TOKEN: process.env.OBSIDIAN_AUTH_TOKEN,
      OBSIDIAN_VAULT_NAME: process.env.OBSIDIAN_VAULT_NAME,
    };
    process.env.GEMINI_API_KEY = "test-key";
    process.env.OBSIDIAN_AUTH_TOKEN = "test-token";
    process.env.OBSIDIAN_VAULT_NAME = "test-vault";

    try {
      const env = validateEnvironment();
      assert.ok("questionModel" in env.gemini, "GeminiConfig should have questionModel");
      assert.equal(typeof env.gemini.questionModel, "string");
    } finally {
      for (const [k, v] of Object.entries(saved)) {
        if (v === undefined) delete process.env[k];
        else process.env[k] = v;
      }
    }
  });
});
