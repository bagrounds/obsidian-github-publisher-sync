/**
 * Tests for scripts/generate-blog-post.ts — Blog post generation utilities.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { generateSlug } from "../generate-blog-post.ts";

describe("generateSlug", () => {
  it("generates slug from dated title", () => {
    const slug = generateSlug("2026-03-12 | 🤖 Fully Automated Blogging 🤖");
    assert.equal(slug, "fully-automated-blogging");
  });

  it("handles title without date prefix", () => {
    const slug = generateSlug("My Cool Blog Post");
    assert.equal(slug, "my-cool-blog-post");
  });

  it("removes special characters", () => {
    const slug = generateSlug("What's the Deal with AI?");
    assert.equal(slug, "whats-the-deal-with-ai");
  });

  it("collapses multiple hyphens", () => {
    const slug = generateSlug("A --- B --- C");
    assert.equal(slug, "a-b-c");
  });

  it("handles emoji-only remaining text", () => {
    const slug = generateSlug("2026-03-12 | 🤖🤖🤖");
    assert.equal(slug, "untitled");
  });

  it("trims leading/trailing hyphens", () => {
    const slug = generateSlug("  --- Hello World ---  ");
    assert.equal(slug, "hello-world");
  });

  it("handles chickie-loo style title", () => {
    const slug = generateSlug("2026-03-12 | 🐔 The Rooster Problem — Love, Guilt, and Hard Choices 🐔");
    assert.equal(slug, "the-rooster-problem-love-guilt-and-hard-choices");
  });
});
