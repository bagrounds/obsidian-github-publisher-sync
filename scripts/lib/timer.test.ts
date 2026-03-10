/**
 * Tests for scripts/lib/timer.ts — Pipeline timing instrumentation.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { PipelineTimer } from "../lib/timer.ts";

describe("PipelineTimer", () => {
  it("records and reports phase durations", () => {
    const timer = new PipelineTimer();
    timer.start("test-phase");
    timer.end("test-phase");
    // Should not throw
    timer.printSummary();
  });

  it("time() wraps async functions and returns result", async () => {
    const timer = new PipelineTimer();
    const result = await timer.time("async-phase", async () => 42);
    assert.equal(result, 42);
  });

  it("time() propagates errors", async () => {
    const timer = new PipelineTimer();
    await assert.rejects(
      () => timer.time("failing-phase", async () => { throw new Error("boom"); }),
      { message: "boom" },
    );
  });

  it("handles multiple phases", () => {
    const timer = new PipelineTimer();
    timer.start("phase-1");
    timer.end("phase-1");
    timer.start("phase-2");
    timer.end("phase-2");
    timer.printSummary();
  });

  it("handles unclosed phases gracefully", () => {
    const timer = new PipelineTimer();
    timer.start("unclosed");
    // printSummary should handle unclosed phases without error
    timer.printSummary();
  });
});
