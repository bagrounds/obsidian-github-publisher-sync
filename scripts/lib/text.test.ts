/**
 * Tests for scripts/lib/text.ts — Pure text processing functions.
 *
 * Tests cover grapheme counting, truncation, tweet length calculation,
 * and the progressive post fitting algorithm.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  countGraphemes,
  truncateToGraphemeLimit,
  calculateTweetLength,
  validateTweetLength,
  fitPostToLimit,
} from "../lib/text.ts";

describe("countGraphemes", () => {
  it("counts ASCII characters", () => {
    assert.equal(countGraphemes("hello"), 5);
  });

  it("counts emoji as single graphemes", () => {
    assert.equal(countGraphemes("👨‍💻"), 1);
  });

  it("counts flag emoji as single grapheme", () => {
    assert.equal(countGraphemes("🇺🇸"), 1);
  });

  it("counts mixed text and emoji", () => {
    assert.equal(countGraphemes("hi 👋"), 4);
  });

  it("returns 0 for empty string", () => {
    assert.equal(countGraphemes(""), 0);
  });

  it("counts family emoji as single grapheme", () => {
    assert.equal(countGraphemes("👨‍👩‍👧‍👦"), 1);
  });

  it("counts accented characters correctly", () => {
    assert.equal(countGraphemes("café"), 4);
  });
});

describe("truncateToGraphemeLimit", () => {
  it("returns text unchanged if within limit", () => {
    assert.equal(truncateToGraphemeLimit("hello", 10), "hello");
  });

  it("returns text unchanged if exactly at limit", () => {
    assert.equal(truncateToGraphemeLimit("hello", 5), "hello");
  });

  it("truncates and adds ellipsis", () => {
    assert.equal(truncateToGraphemeLimit("hello world", 6), "hello…");
  });

  it("handles emoji truncation correctly", () => {
    const result = truncateToGraphemeLimit("👨‍💻🎉🚀✨", 3);
    assert.equal(countGraphemes(result), 3);
    assert.ok(result.endsWith("…"));
  });

  it("handles limit of 1", () => {
    assert.equal(truncateToGraphemeLimit("hello", 1), "…");
  });
});

describe("calculateTweetLength", () => {
  it("counts plain text normally", () => {
    assert.equal(calculateTweetLength("hello world"), 11);
  });

  it("counts URLs as 23 characters", () => {
    const text = "Check out https://bagrounds.org/reflections/2026-03-08";
    const expected = "Check out ".length + 23;
    assert.equal(calculateTweetLength(text), expected);
  });

  it("handles multiple URLs", () => {
    const text = "Visit https://example.com and https://other.com";
    const expected = "Visit ".length + 23 + " and ".length + 23;
    assert.equal(calculateTweetLength(text), expected);
  });

  it("handles text without URLs", () => {
    assert.equal(calculateTweetLength("no urls here"), 12);
  });

  it("returns 0 for empty string", () => {
    assert.equal(calculateTweetLength(""), 0);
  });
});

describe("validateTweetLength", () => {
  it("validates short text", () => {
    const result = validateTweetLength("hello");
    assert.equal(result.valid, true);
    assert.equal(result.length, 5);
  });

  it("validates text at exactly 280 characters", () => {
    const text = "x".repeat(280);
    const result = validateTweetLength(text);
    assert.equal(result.valid, true);
    assert.equal(result.length, 280);
  });

  it("rejects text over 280 characters", () => {
    const text = "x".repeat(281);
    const result = validateTweetLength(text);
    assert.equal(result.valid, false);
    assert.equal(result.length, 281);
  });
});

describe("fitPostToLimit", () => {
  it("returns text unchanged if within limit", () => {
    const text = "Short post\nhttps://example.com";
    assert.equal(fitPostToLimit(text, 300), text);
  });

  it("removes topic tags from right to left", () => {
    const text = "Title Line\n\n📚 Tag1 | 🤖 Tag2 | 🧠 Tag3\nhttps://example.com";
    const result = fitPostToLimit(text, 60);
    assert.ok(result.includes("https://example.com"));
    assert.ok(countGraphemes(result) <= 60);
  });

  it("preserves the URL line", () => {
    const text = "Long title here\n\n📚 Tag1 | 🤖 Tag2 | 🧠 Tag3 | ✨ Tag4\nhttps://bagrounds.org/reflections/2026-03-10";
    const result = fitPostToLimit(text, 80);
    assert.ok(result.includes("https://bagrounds.org/reflections/2026-03-10"));
  });

  it("handles text with no URL line", () => {
    const text = "A very long post without any URL that exceeds the limit";
    const result = fitPostToLimit(text, 20);
    assert.ok(countGraphemes(result) <= 20);
    assert.ok(result.endsWith("…"));
  });

  it("removes entire topic line when tags aren't enough", () => {
    const text = "Long Title Line Here\n\n📚 VeryLongTag1\nhttps://example.com";
    const result = fitPostToLimit(text, 50);
    assert.ok(result.includes("https://example.com"));
    assert.ok(countGraphemes(result) <= 50);
  });

  it("truncates content as last resort", () => {
    const text = "This is a very long content line that goes on and on\nhttps://example.com";
    const result = fitPostToLimit(text, 40);
    assert.ok(result.includes("https://example.com"));
    assert.ok(countGraphemes(result) <= 40);
  });

  it("handles empty text", () => {
    assert.equal(fitPostToLimit("", 300), "");
  });
});
