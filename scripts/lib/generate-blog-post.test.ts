import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { generateSlug } from "../generate-blog-post.ts";

describe("generateSlug", () => {
  it("generates slug from dated title", () => {
    assert.equal(generateSlug("2026-03-12 | 🤖 Fully Automated Blogging 🤖"), "fully-automated-blogging");
  });

  it("handles title without date prefix", () => {
    assert.equal(generateSlug("My Cool Blog Post"), "my-cool-blog-post");
  });

  it("collapses multiple hyphens", () => {
    assert.equal(generateSlug("A --- B --- C"), "a-b-c");
  });

  it("throws for empty slug", () => {
    assert.throws(() => generateSlug("2026-03-12 | 🤖🤖🤖"), /Failed to generate slug/);
  });
});
