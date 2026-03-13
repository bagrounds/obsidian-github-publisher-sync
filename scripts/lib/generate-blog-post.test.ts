import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { generateSlug } from "../generate-blog-post.ts";

describe("generateSlug", () => {
  it("generates slug from title", () => {
    assert.equal(generateSlug("Fully Automated Blogging"), "fully-automated-blogging");
  });

  it("strips emoji from title", () => {
    assert.equal(generateSlug("🤖 My Cool Blog Post 🤖"), "my-cool-blog-post");
  });

  it("collapses multiple hyphens", () => {
    assert.equal(generateSlug("A --- B --- C"), "a-b-c");
  });

  it("throws for empty slug", () => {
    assert.throws(() => generateSlug("🤖🤖🤖"), /Failed to generate slug/);
  });
});
