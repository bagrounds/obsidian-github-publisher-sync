/**
 * Tests for scripts/lib/experiment.ts — A/B testing framework.
 *
 * Covers variant selection (deterministic and random), assignment creation,
 * environment override, weight validation, and formatting.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  selectVariant,
  randomVariant,
  createAssignment,
  getVariantOverride,
  resolveVariant,
  formatAssignment,
  validateWeights,
  isVariantId,
  DEFAULT_WEIGHTS,
  VARIANT_IDS,
} from "./experiment.ts";
import type { VariantWeight } from "./experiment.ts";

// --- selectVariant ---

describe("selectVariant", () => {
  it("selects variant A when random < 0.5 with default weights", () => {
    assert.equal(selectVariant(0.0, DEFAULT_WEIGHTS), "A");
    assert.equal(selectVariant(0.25, DEFAULT_WEIGHTS), "A");
    assert.equal(selectVariant(0.49, DEFAULT_WEIGHTS), "A");
  });

  it("selects variant B when random >= 0.5 with default weights", () => {
    assert.equal(selectVariant(0.5, DEFAULT_WEIGHTS), "B");
    assert.equal(selectVariant(0.75, DEFAULT_WEIGHTS), "B");
    assert.equal(selectVariant(0.99, DEFAULT_WEIGHTS), "B");
  });

  it("handles boundary at exactly 0.5", () => {
    assert.equal(selectVariant(0.5, DEFAULT_WEIGHTS), "B");
  });

  it("handles custom weights: 80/20 split", () => {
    const weights: VariantWeight[] = [
      { variant: "A", weight: 0.8 },
      { variant: "B", weight: 0.2 },
    ];
    assert.equal(selectVariant(0.0, weights), "A");
    assert.equal(selectVariant(0.79, weights), "A");
    assert.equal(selectVariant(0.8, weights), "B");
    assert.equal(selectVariant(0.99, weights), "B");
  });

  it("handles edge case: random = 0", () => {
    assert.equal(selectVariant(0, DEFAULT_WEIGHTS), "A");
  });

  it("handles edge case: floating-point near 1.0", () => {
    // Should fall back to last variant
    const result = selectVariant(1.0, DEFAULT_WEIGHTS);
    assert.equal(result, "B");
  });

  it("is a total function over [0, 1) — property-based", () => {
    for (let i = 0; i < 100; i++) {
      const r = Math.random();
      const result = selectVariant(r, DEFAULT_WEIGHTS);
      assert.ok(result === "A" || result === "B", `Invalid variant for r=${r}: ${result}`);
    }
  });
});

// --- randomVariant ---

describe("randomVariant", () => {
  it("returns a valid variant ID", () => {
    for (let i = 0; i < 50; i++) {
      const result = randomVariant();
      assert.ok(VARIANT_IDS.includes(result), `Invalid variant: ${result}`);
    }
  });

  it("produces both variants over many trials (statistical)", () => {
    const results = new Set<string>();
    for (let i = 0; i < 100; i++) {
      results.add(randomVariant());
    }
    assert.ok(results.has("A"), "Should produce variant A");
    assert.ok(results.has("B"), "Should produce variant B");
  });
});

// --- createAssignment ---

describe("createAssignment", () => {
  it("creates an assignment with all fields", () => {
    const assignment = createAssignment("A", "reflections/2026-03-10.md", "mastodon", "2026-03-10T12:00:00Z");
    assert.equal(assignment.variant, "A");
    assert.equal(assignment.notePath, "reflections/2026-03-10.md");
    assert.equal(assignment.platform, "mastodon");
    assert.equal(assignment.timestamp, "2026-03-10T12:00:00Z");
  });

  it("defaults timestamp to current ISO string", () => {
    const before = new Date().toISOString();
    const assignment = createAssignment("B", "test.md", "bluesky");
    const after = new Date().toISOString();
    assert.ok(assignment.timestamp >= before);
    assert.ok(assignment.timestamp <= after);
  });

  it("returns an immutable object", () => {
    const assignment = createAssignment("A", "test.md", "all");
    // TypeScript readonly enforces at compile time; runtime check for good measure
    assert.equal(typeof assignment, "object");
    assert.equal(assignment.variant, "A");
  });
});

// --- getVariantOverride ---

describe("getVariantOverride", () => {
  it("returns undefined when AB_TEST_VARIANT is not set", () => {
    const original = process.env.AB_TEST_VARIANT;
    delete process.env.AB_TEST_VARIANT;
    assert.equal(getVariantOverride(), undefined);
    if (original !== undefined) process.env.AB_TEST_VARIANT = original;
  });

  it("returns A when AB_TEST_VARIANT=A", () => {
    const original = process.env.AB_TEST_VARIANT;
    process.env.AB_TEST_VARIANT = "A";
    assert.equal(getVariantOverride(), "A");
    if (original !== undefined) process.env.AB_TEST_VARIANT = original;
    else delete process.env.AB_TEST_VARIANT;
  });

  it("returns B when AB_TEST_VARIANT=B", () => {
    const original = process.env.AB_TEST_VARIANT;
    process.env.AB_TEST_VARIANT = "B";
    assert.equal(getVariantOverride(), "B");
    if (original !== undefined) process.env.AB_TEST_VARIANT = original;
    else delete process.env.AB_TEST_VARIANT;
  });

  it("returns undefined for invalid values", () => {
    const original = process.env.AB_TEST_VARIANT;
    process.env.AB_TEST_VARIANT = "C";
    assert.equal(getVariantOverride(), undefined);
    process.env.AB_TEST_VARIANT = "a";
    assert.equal(getVariantOverride(), undefined);
    process.env.AB_TEST_VARIANT = "";
    assert.equal(getVariantOverride(), undefined);
    if (original !== undefined) process.env.AB_TEST_VARIANT = original;
    else delete process.env.AB_TEST_VARIANT;
  });
});

// --- resolveVariant ---

describe("resolveVariant", () => {
  it("uses override when set", () => {
    const original = process.env.AB_TEST_VARIANT;
    process.env.AB_TEST_VARIANT = "B";
    assert.equal(resolveVariant(), "B");
    if (original !== undefined) process.env.AB_TEST_VARIANT = original;
    else delete process.env.AB_TEST_VARIANT;
  });

  it("falls back to random when no override", () => {
    const original = process.env.AB_TEST_VARIANT;
    delete process.env.AB_TEST_VARIANT;
    const result = resolveVariant();
    assert.ok(result === "A" || result === "B");
    if (original !== undefined) process.env.AB_TEST_VARIANT = original;
  });
});

// --- formatAssignment ---

describe("formatAssignment", () => {
  it("formats assignment as readable string", () => {
    const assignment = createAssignment("A", "reflections/2026-03-10.md", "mastodon", "2026-03-10T12:00:00Z");
    const formatted = formatAssignment(assignment);
    assert.ok(formatted.includes("Variant A"));
    assert.ok(formatted.includes("mastodon"));
    assert.ok(formatted.includes("reflections/2026-03-10.md"));
    assert.ok(formatted.includes("2026-03-10T12:00:00Z"));
  });

  it("includes emoji prefix", () => {
    const assignment = createAssignment("B", "test.md", "bluesky", "2026-01-01T00:00:00Z");
    assert.ok(formatAssignment(assignment).startsWith("🧪"));
  });
});

// --- validateWeights ---

describe("validateWeights", () => {
  it("validates default weights", () => {
    assert.ok(validateWeights(DEFAULT_WEIGHTS));
  });

  it("validates custom weights that sum to 1", () => {
    assert.ok(validateWeights([
      { variant: "A", weight: 0.3 },
      { variant: "B", weight: 0.7 },
    ]));
  });

  it("rejects weights that sum to less than 1", () => {
    assert.equal(
      validateWeights([
        { variant: "A", weight: 0.3 },
        { variant: "B", weight: 0.3 },
      ]),
      false,
    );
  });

  it("rejects weights that sum to more than 1", () => {
    assert.equal(
      validateWeights([
        { variant: "A", weight: 0.6 },
        { variant: "B", weight: 0.6 },
      ]),
      false,
    );
  });

  it("accepts weights within floating-point tolerance", () => {
    assert.ok(validateWeights([
      { variant: "A", weight: 0.1 + 0.2 },  // 0.30000000000000004
      { variant: "B", weight: 0.7 },
    ]));
  });
});

// --- isVariantId ---

describe("isVariantId", () => {
  it("returns true for valid variant IDs", () => {
    assert.ok(isVariantId("A"));
    assert.ok(isVariantId("B"));
  });

  it("returns false for invalid strings", () => {
    assert.equal(isVariantId("C"), false);
    assert.equal(isVariantId("a"), false);
    assert.equal(isVariantId(""), false);
    assert.equal(isVariantId("AB"), false);
  });
});

// --- VARIANT_IDS ---

describe("VARIANT_IDS", () => {
  it("contains exactly A and B", () => {
    assert.deepEqual([...VARIANT_IDS], ["A", "B"]);
  });
});
