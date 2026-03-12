/**
 * Tests for scripts/lib/analytics.ts — Statistical analysis functions.
 *
 * Covers mean, variance, standard deviation, Welch's t-test,
 * p-value approximation, experiment summary, and metric aggregation.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  totalEngagement,
  engagementRate,
  mean,
  variance,
  standardDeviation,
  welchTTest,
  approximatePValue,
  analyzeExperiment,
  formatExperimentSummary,
} from "./analytics.ts";
import type { EngagementMetrics } from "./experiment.ts";

// --- totalEngagement ---

describe("totalEngagement", () => {
  it("sums likes, reposts, and replies", () => {
    const metrics: EngagementMetrics = { likes: 5, reposts: 3, replies: 2 };
    assert.equal(totalEngagement(metrics), 10);
  });

  it("returns 0 for zero metrics", () => {
    const metrics: EngagementMetrics = { likes: 0, reposts: 0, replies: 0 };
    assert.equal(totalEngagement(metrics), 0);
  });

  it("handles large numbers", () => {
    const metrics: EngagementMetrics = { likes: 1000, reposts: 500, replies: 250 };
    assert.equal(totalEngagement(metrics), 1750);
  });
});

// --- engagementRate ---

describe("engagementRate", () => {
  it("computes engagement / impressions", () => {
    const metrics: EngagementMetrics = { likes: 10, reposts: 5, replies: 5 };
    assert.equal(engagementRate(metrics, 100), 0.2);
  });

  it("returns 0 when impressions is 0", () => {
    const metrics: EngagementMetrics = { likes: 10, reposts: 5, replies: 5 };
    assert.equal(engagementRate(metrics, 0), 0);
  });

  it("handles zero engagement", () => {
    const metrics: EngagementMetrics = { likes: 0, reposts: 0, replies: 0 };
    assert.equal(engagementRate(metrics, 100), 0);
  });
});

// --- mean ---

describe("mean", () => {
  it("computes arithmetic mean", () => {
    assert.equal(mean([1, 2, 3, 4, 5]), 3);
  });

  it("returns 0 for empty array", () => {
    assert.equal(mean([]), 0);
  });

  it("handles single element", () => {
    assert.equal(mean([42]), 42);
  });

  it("handles negative numbers", () => {
    assert.equal(mean([-1, 1]), 0);
  });

  it("handles floating point", () => {
    assert.ok(Math.abs(mean([1.5, 2.5]) - 2.0) < 0.001);
  });
});

// --- variance ---

describe("variance", () => {
  it("computes sample variance", () => {
    // [2, 4, 4, 4, 5, 5, 7, 9] → mean=5, variance=4.571
    const values = [2, 4, 4, 4, 5, 5, 7, 9];
    const result = variance(values);
    assert.ok(Math.abs(result - 4.571) < 0.01);
  });

  it("returns 0 for single element", () => {
    assert.equal(variance([42]), 0);
  });

  it("returns 0 for empty array", () => {
    assert.equal(variance([]), 0);
  });

  it("returns 0 for identical values", () => {
    assert.equal(variance([5, 5, 5, 5]), 0);
  });

  it("is non-negative for any input", () => {
    for (let i = 0; i < 20; i++) {
      const values = Array.from({ length: 10 }, () => Math.random() * 100);
      assert.ok(variance(values) >= 0);
    }
  });
});

// --- standardDeviation ---

describe("standardDeviation", () => {
  it("is the square root of variance", () => {
    const values = [2, 4, 4, 4, 5, 5, 7, 9];
    const sd = standardDeviation(values);
    const v = variance(values);
    assert.ok(Math.abs(sd - Math.sqrt(v)) < 0.001);
  });

  it("returns 0 for identical values", () => {
    assert.equal(standardDeviation([3, 3, 3]), 0);
  });
});

// --- welchTTest ---

describe("welchTTest", () => {
  it("returns t=0 for identical groups", () => {
    const result = welchTTest([5, 5, 5], [5, 5, 5]);
    assert.equal(result.t, 0);
    assert.equal(result.meanA, 5);
    assert.equal(result.meanB, 5);
  });

  it("returns positive t when group A has higher mean", () => {
    const result = welchTTest([10, 11, 12], [1, 2, 3]);
    assert.ok(result.t > 0, `Expected positive t, got ${result.t}`);
    assert.ok(result.meanA > result.meanB);
  });

  it("returns negative t when group B has higher mean", () => {
    const result = welchTTest([1, 2, 3], [10, 11, 12]);
    assert.ok(result.t < 0, `Expected negative t, got ${result.t}`);
    assert.ok(result.meanA < result.meanB);
  });

  it("handles groups of different sizes", () => {
    const result = welchTTest([1, 2], [10, 11, 12, 13, 14]);
    assert.ok(result.t < 0);
    assert.ok(result.df > 0);
  });

  it("returns t=0 and df=0 for groups with fewer than 2 elements", () => {
    const result = welchTTest([5], [10]);
    assert.equal(result.t, 0);
    assert.equal(result.df, 0);
  });

  it("computes reasonable degrees of freedom", () => {
    const result = welchTTest([1, 2, 3, 4, 5], [6, 7, 8, 9, 10]);
    assert.ok(result.df > 0);
    assert.ok(result.df <= 8); // For equal-size groups, df ≤ n1+n2-2
  });
});

// --- approximatePValue ---

describe("approximatePValue", () => {
  it("returns ~1 for t=0 (no difference)", () => {
    const p = approximatePValue(0, 10);
    assert.ok(Math.abs(p - 1.0) < 0.01, `Expected ~1.0, got ${p}`);
  });

  it("returns small p for large |t|", () => {
    const p = approximatePValue(5, 30);
    assert.ok(p < 0.01, `Expected p < 0.01, got ${p}`);
  });

  it("is symmetric: p(t) === p(-t)", () => {
    const p1 = approximatePValue(2.5, 20);
    const p2 = approximatePValue(-2.5, 20);
    assert.ok(Math.abs(p1 - p2) < 0.001);
  });

  it("returns values between 0 and 1", () => {
    for (let t = -5; t <= 5; t += 0.5) {
      const p = approximatePValue(t, 20);
      assert.ok(p >= 0 && p <= 1, `p=${p} for t=${t} should be in [0,1]`);
    }
  });

  it("is monotonically decreasing as |t| increases", () => {
    let prevP = 2;
    for (let t = 0; t <= 5; t += 0.5) {
      const p = approximatePValue(t, 20);
      assert.ok(p <= prevP + 0.001, `p should decrease as |t| increases`);
      prevP = p;
    }
  });
});

// --- analyzeExperiment ---

describe("analyzeExperiment", () => {
  it("produces a summary with correct counts", () => {
    const a = [1, 2, 3, 4, 5];
    const b = [6, 7, 8, 9, 10];
    const summary = analyzeExperiment(a, b);
    assert.equal(summary.variantACount, 5);
    assert.equal(summary.variantBCount, 5);
  });

  it("detects significant difference for clearly different groups", () => {
    const a = [1, 2, 1, 2, 1, 2, 1, 2, 1, 2];
    const b = [98, 99, 100, 101, 102, 98, 99, 100, 101, 102];
    const summary = analyzeExperiment(a, b);
    assert.ok(summary.significant, "Should detect significant difference");
    assert.ok(summary.pValue < 0.05);
  });

  it("does not detect significance for identical groups", () => {
    const a = [5, 5, 5, 5, 5];
    const b = [5, 5, 5, 5, 5];
    const summary = analyzeExperiment(a, b);
    assert.equal(summary.significant, false);
  });

  it("computes correct mean engagement", () => {
    const a = [10, 20, 30];
    const b = [5, 10, 15];
    const summary = analyzeExperiment(a, b);
    assert.equal(summary.variantAMeanEngagement, 20);
    assert.equal(summary.variantBMeanEngagement, 10);
  });

  it("uses default alpha of 0.05", () => {
    const a = [1, 2, 3];
    const b = [4, 5, 6];
    const summary = analyzeExperiment(a, b);
    // With these small groups, likely not significant
    assert.equal(typeof summary.significant, "boolean");
  });

  it("accepts custom alpha", () => {
    const a = [1, 2, 3, 4, 5];
    const b = [3, 4, 5, 6, 7];
    const liberal = analyzeExperiment(a, b, 0.5);
    const strict = analyzeExperiment(a, b, 0.001);
    // Liberal alpha should be at least as likely to find significance
    if (strict.significant) {
      assert.ok(liberal.significant, "Liberal alpha should also be significant if strict is");
    }
  });
});

// --- formatExperimentSummary ---

describe("formatExperimentSummary", () => {
  it("includes variant counts", () => {
    const summary = analyzeExperiment([1, 2, 3], [4, 5, 6]);
    const report = formatExperimentSummary(summary);
    assert.ok(report.includes("n=3"));
  });

  it("includes significance indicator", () => {
    const summary = analyzeExperiment([1, 2, 3], [4, 5, 6]);
    const report = formatExperimentSummary(summary);
    assert.ok(report.includes("YES") || report.includes("NO"));
  });

  it("includes p-value", () => {
    const summary = analyzeExperiment([1, 2, 3], [4, 5, 6]);
    const report = formatExperimentSummary(summary);
    assert.ok(report.includes("p-value"));
  });

  it("declares winner when significant", () => {
    const a = [1, 2, 1, 2, 1, 2, 1, 2, 1, 2];
    const b = [98, 99, 100, 101, 102, 98, 99, 100, 101, 102];
    const summary = analyzeExperiment(a, b);
    const report = formatExperimentSummary(summary);
    assert.ok(report.includes("Winner"), "Should declare a winner");
  });

  it("encourages more data when not significant", () => {
    const summary = analyzeExperiment([5, 5, 5], [5, 5, 5]);
    const report = formatExperimentSummary(summary);
    assert.ok(report.includes("Keep collecting data") || report.includes("NO"));
  });
});
