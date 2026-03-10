/**
 * Tests for scripts/lib/html.ts — Pure HTML and date formatting utilities.
 *
 * These tests verify referential transparency: same input → same output,
 * with no side effects or external dependencies.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { escapeHtml, textToHtml, formatDisplayDate, MONTH_NAMES } from "../lib/html.ts";

describe("escapeHtml", () => {
  it("escapes ampersand", () => {
    assert.equal(escapeHtml("a & b"), "a &amp; b");
  });

  it("escapes angle brackets", () => {
    assert.equal(escapeHtml("<script>"), "&lt;script&gt;");
  });

  it("escapes quotes", () => {
    assert.equal(escapeHtml(`"hello" & 'world'`), "&quot;hello&quot; &amp; &#39;world&#39;");
  });

  it("returns empty string unchanged", () => {
    assert.equal(escapeHtml(""), "");
  });

  it("returns safe text unchanged", () => {
    assert.equal(escapeHtml("hello world 123"), "hello world 123");
  });

  it("handles multiple special characters in sequence", () => {
    assert.equal(escapeHtml(`<>&"'`), "&lt;&gt;&amp;&quot;&#39;");
  });

  it("preserves emoji and unicode", () => {
    assert.equal(escapeHtml("🎉 hello 世界"), "🎉 hello 世界");
  });
});

describe("textToHtml", () => {
  it("escapes HTML and converts newlines to <br>", () => {
    assert.equal(textToHtml("line1\nline2"), "line1<br>line2");
  });

  it("escapes HTML special characters AND converts newlines", () => {
    assert.equal(textToHtml("<b>\n</b>"), "&lt;b&gt;<br>&lt;/b&gt;");
  });

  it("handles text with no newlines", () => {
    assert.equal(textToHtml("hello world"), "hello world");
  });

  it("handles multiple consecutive newlines", () => {
    assert.equal(textToHtml("a\n\nb"), "a<br><br>b");
  });
});

describe("formatDisplayDate", () => {
  it("formats a standard date", () => {
    assert.equal(formatDisplayDate("2026-03-10"), "March 10, 2026");
  });

  it("formats January 1st", () => {
    assert.equal(formatDisplayDate("2026-01-01"), "January 1, 2026");
  });

  it("formats December 31st", () => {
    assert.equal(formatDisplayDate("2025-12-31"), "December 31, 2025");
  });

  it("formats leap year date", () => {
    assert.equal(formatDisplayDate("2024-02-29"), "February 29, 2024");
  });
});

describe("MONTH_NAMES", () => {
  it("has 12 months", () => {
    assert.equal(MONTH_NAMES.length, 12);
  });

  it("starts with January", () => {
    assert.equal(MONTH_NAMES[0], "January");
  });

  it("ends with December", () => {
    assert.equal(MONTH_NAMES[11], "December");
  });
});
