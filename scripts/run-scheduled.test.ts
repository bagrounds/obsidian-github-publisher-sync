import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { parseArgs } from "./run-scheduled.ts";

// ---------------------------------------------------------------------------
// parseArgs
// ---------------------------------------------------------------------------

describe("parseArgs", () => {
  it("returns undefined overrides with no flags", () => {
    const result = parseArgs(["node", "run-scheduled.ts"]);
    assert.equal(result.hourOverride, undefined);
    assert.equal(result.taskOverride, undefined);
  });

  it("parses --hour flag", () => {
    const result = parseArgs(["node", "run-scheduled.ts", "--hour", "15"]);
    assert.equal(result.hourOverride, 15);
    assert.equal(result.taskOverride, undefined);
  });

  it("parses --task flag", () => {
    const result = parseArgs([
      "node",
      "run-scheduled.ts",
      "--task",
      "social-posting",
    ]);
    assert.equal(result.hourOverride, undefined);
    assert.equal(result.taskOverride, "social-posting");
  });

  it("parses both flags together", () => {
    const result = parseArgs([
      "node",
      "run-scheduled.ts",
      "--task",
      "internal-linking",
      "--hour",
      "8",
    ]);
    assert.equal(result.hourOverride, 8);
    assert.equal(result.taskOverride, "internal-linking");
  });

  it("handles --hour 0 correctly", () => {
    const result = parseArgs(["node", "run-scheduled.ts", "--hour", "0"]);
    assert.equal(result.hourOverride, 0);
  });

  it("returns NaN for non-numeric --hour", () => {
    const result = parseArgs(["node", "run-scheduled.ts", "--hour", "abc"]);
    assert.ok(Number.isNaN(result.hourOverride));
  });
});
