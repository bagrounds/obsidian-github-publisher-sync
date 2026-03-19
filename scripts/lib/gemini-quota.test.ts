/**
 * Tests for scripts/lib/gemini-quota.ts — Gemini quota reporting.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  type GeminiModelInfo,
  type QuotaLimit,
  type UsageDataPoint,
  type QuotaEntry,
  safeInt,
  generativeModels,
  freeTierLimits,
  buildFreeTierSummary,
  buildQuotaReport,
  formatQuotaReport,
  formatQuotaEntry,
  toQuotaJson,
} from "./gemini-quota.ts";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const flashModel: GeminiModelInfo = {
  name: "models/gemini-2.0-flash",
  displayName: "Gemini 2.0 Flash",
  description: "Fast and versatile",
  inputTokenLimit: 1_048_576,
  outputTokenLimit: 8_192,
  supportedGenerationMethods: ["generateContent", "countTokens"],
  temperature: 1,
  maxTemperature: 2,
  topP: 0.95,
  topK: 40,
};

const embeddingModel: GeminiModelInfo = {
  name: "models/text-embedding-004",
  displayName: "Text Embedding 004",
  description: "Embedding model",
  inputTokenLimit: 2_048,
  outputTokenLimit: 0,
  supportedGenerationMethods: ["embedContent"],
};

const liteModel: GeminiModelInfo = {
  name: "models/gemini-2.0-flash-lite",
  displayName: "Gemini 2.0 Flash-Lite",
  description: "Lightweight model",
  inputTokenLimit: 1_048_576,
  outputTokenLimit: 8_192,
  supportedGenerationMethods: ["generateContent"],
};

const allModels = [flashModel, embeddingModel, liteModel] as const;

const freeTierRequestLimit: QuotaLimit = {
  metric: "generativelanguage.googleapis.com/generate_content_free_tier_requests_per_day_per_project_per_model",
  displayName: "Number of requests made to a specific model, in the free tier.",
  unit: "1/d/{project}/{model}",
  effectiveLimit: 1500,
  defaultLimit: 1500,
};

const freeTierRpmLimit: QuotaLimit = {
  metric: "generativelanguage.googleapis.com/generate_content_free_tier_requests_per_minute_per_project_per_model",
  displayName: "Number of requests made to a specific model, in the free tier.",
  unit: "1/min/{project}/{model}",
  effectiveLimit: 15,
  defaultLimit: 15,
};

const paidTierLimit: QuotaLimit = {
  metric: "generativelanguage.googleapis.com/generate_content_requests_per_model_paid_tier",
  displayName: "Generate content requests per model (paid tier)",
  unit: "1/min/{project}/{model}",
  effectiveLimit: 360,
  defaultLimit: 360,
};

const zeroEffectiveLimit: QuotaLimit = {
  metric: "generativelanguage.googleapis.com/generate_content_free_tier_tokens",
  displayName: "Generate content free tier input token count",
  unit: "1/min/{project}/{model}",
  effectiveLimit: 0,
  defaultLimit: 0,
};

const allLimits = [freeTierRequestLimit, freeTierRpmLimit, paidTierLimit, zeroEffectiveLimit] as const;

const sampleUsage: UsageDataPoint = {
  quotaMetric: "generativelanguage.googleapis.com/generate_content_free_tier_requests_per_day_per_project_per_model",
  metricType: "serviceruntime.googleapis.com/quota/allocation/usage",
  value: 34,
  timestamp: "2026-03-19T20:00:00Z",
};

const sampleRpmUsage: UsageDataPoint = {
  quotaMetric: "generativelanguage.googleapis.com/generate_content_free_tier_requests_per_minute_per_project_per_model",
  metricType: "serviceruntime.googleapis.com/quota/rate/net_usage",
  value: 2,
  timestamp: "2026-03-19T20:01:00Z",
};

// ---------------------------------------------------------------------------
// safeInt
// ---------------------------------------------------------------------------

describe("safeInt", () => {
  it("converts valid numbers", () => {
    assert.equal(safeInt(42, 0), 42);
    assert.equal(safeInt("100", 0), 100);
  });

  it("returns fallback for NaN", () => {
    assert.equal(safeInt("not-a-number", 0), 0);
    assert.equal(safeInt(undefined, 99), 99);
  });

  it("returns fallback for Infinity", () => {
    assert.equal(safeInt(Infinity, 0), 0);
    assert.equal(safeInt(-Infinity, 0), 0);
  });
});

// ---------------------------------------------------------------------------
// generativeModels
// ---------------------------------------------------------------------------

describe("generativeModels", () => {
  it("returns only models supporting generateContent", () => {
    const result = generativeModels(allModels);
    assert.equal(result.length, 2);
    assert.ok(result.every((m) => m.supportedGenerationMethods.includes("generateContent")));
  });

  it("excludes embedding-only models", () => {
    const result = generativeModels(allModels);
    assert.ok(!result.some((m) => m.name === embeddingModel.name));
  });

  it("returns empty array for empty input", () => {
    assert.deepEqual(generativeModels([]), []);
  });

  it("returns empty array when no models support generation", () => {
    assert.deepEqual(generativeModels([embeddingModel]), []);
  });
});

// ---------------------------------------------------------------------------
// freeTierLimits
// ---------------------------------------------------------------------------

describe("freeTierLimits", () => {
  it("includes limits with 'free tier' in display name and positive effective limit", () => {
    const result = freeTierLimits(allLimits);
    assert.ok(result.every((q) => q.displayName.toLowerCase().includes("free tier")));
    assert.ok(result.every((q) => q.effectiveLimit > 0));
  });

  it("excludes paid tier limits", () => {
    const result = freeTierLimits(allLimits);
    assert.ok(!result.some((q) => q.displayName.includes("paid tier")));
  });

  it("excludes limits with zero effective limit", () => {
    const result = freeTierLimits(allLimits);
    assert.ok(!result.some((q) => q.effectiveLimit === 0));
  });

  it("returns correct count from mixed input", () => {
    const result = freeTierLimits(allLimits);
    assert.equal(result.length, 2);
  });

  it("returns empty for empty input", () => {
    assert.deepEqual(freeTierLimits([]), []);
  });
});

// ---------------------------------------------------------------------------
// buildFreeTierSummary
// ---------------------------------------------------------------------------

describe("buildFreeTierSummary", () => {
  it("matches usage to limits by quota metric name", () => {
    const summary = buildFreeTierSummary([freeTierRequestLimit], [sampleUsage]);
    assert.equal(summary.length, 1);
    assert.equal(summary[0]?.used, 34);
    assert.equal(summary[0]?.limit, 1500);
    assert.equal(summary[0]?.remaining, 1466);
  });

  it("reports null used/remaining when no usage data matches", () => {
    const summary = buildFreeTierSummary([freeTierRequestLimit], []);
    assert.equal(summary.length, 1);
    assert.equal(summary[0]?.used, null);
    assert.equal(summary[0]?.remaining, null);
    assert.equal(summary[0]?.limit, 1500);
  });

  it("caps remaining at zero when usage exceeds limit", () => {
    const overUsage: UsageDataPoint = { ...sampleUsage, value: 2000 };
    const summary = buildFreeTierSummary([freeTierRequestLimit], [overUsage]);
    assert.equal(summary[0]?.used, 2000);
    assert.equal(summary[0]?.remaining, 0);
  });

  it("handles multiple limits with mixed usage", () => {
    const summary = buildFreeTierSummary(
      [freeTierRequestLimit, freeTierRpmLimit],
      [sampleUsage],
    );
    assert.equal(summary.length, 2);
    const daily = summary.find((s) => s.unit.includes("/d/"));
    const perMin = summary.find((s) => s.unit.includes("/min/"));
    assert.equal(daily?.used, 34);
    assert.equal(perMin?.used, null);
  });

  it("uses latest usage data point when multiple exist for same metric", () => {
    const olderPoint: UsageDataPoint = { ...sampleUsage, value: 10, timestamp: "2026-03-19T19:00:00Z" };
    const newerPoint: UsageDataPoint = { ...sampleUsage, value: 34, timestamp: "2026-03-19T20:00:00Z" };
    const summary = buildFreeTierSummary([freeTierRequestLimit], [olderPoint, newerPoint]);
    assert.equal(summary[0]?.used, 34);
  });

  it("only includes free tier limits (excludes paid)", () => {
    const summary = buildFreeTierSummary(allLimits, []);
    assert.ok(!summary.some((s) => s.displayName.includes("paid tier")));
    assert.equal(summary.length, 2);
  });

  it("returns empty for empty limits", () => {
    assert.deepEqual(buildFreeTierSummary([], [sampleUsage]), []);
  });
});

// ---------------------------------------------------------------------------
// buildQuotaReport
// ---------------------------------------------------------------------------

describe("buildQuotaReport", () => {
  it("includes label and models", () => {
    const report = buildQuotaReport(allModels, "before");
    assert.equal(report.label, "before");
    assert.equal(report.models.length, 3);
  });

  it("includes ISO timestamp", () => {
    const report = buildQuotaReport([], "test");
    assert.match(report.timestamp, /^\d{4}-\d{2}-\d{2}T/);
  });

  it("defaults to empty quota limits, usage, and summary", () => {
    const report = buildQuotaReport([], "test");
    assert.deepEqual(report.quotaLimits, []);
    assert.deepEqual(report.usage, []);
    assert.deepEqual(report.freeTierSummary, []);
  });

  it("builds free tier summary from limits and usage", () => {
    const report = buildQuotaReport([], "test", [freeTierRequestLimit], [sampleUsage]);
    assert.equal(report.freeTierSummary.length, 1);
    assert.equal(report.freeTierSummary[0]?.used, 34);
    assert.equal(report.freeTierSummary[0]?.remaining, 1466);
  });
});

// ---------------------------------------------------------------------------
// formatQuotaEntry
// ---------------------------------------------------------------------------

describe("formatQuotaEntry", () => {
  it("shows used / limit when usage is available", () => {
    const entry: QuotaEntry = {
      name: "test",
      displayName: "Requests per day (free tier)",
      unit: "1/d/{project}/{model}",
      limit: 500,
      used: 34,
      remaining: 466,
    };
    const line = formatQuotaEntry(entry);
    assert.ok(line.includes("34 / 500"));
    assert.ok(line.includes("Requests per day"));
  });

  it("shows ? / limit when usage is unknown", () => {
    const entry: QuotaEntry = {
      name: "test",
      displayName: "Requests per minute (free tier)",
      unit: "1/min/{project}/{model}",
      limit: 15,
      used: null,
      remaining: null,
    };
    const line = formatQuotaEntry(entry);
    assert.ok(line.includes("? / 15"));
  });
});

// ---------------------------------------------------------------------------
// formatQuotaReport
// ---------------------------------------------------------------------------

describe("formatQuotaReport", () => {
  it("includes label in header", () => {
    const report = buildQuotaReport(allModels, "before workflow");
    const output = formatQuotaReport(report);
    assert.ok(output.includes("before workflow"));
  });

  it("includes model names", () => {
    const report = buildQuotaReport(allModels, "test");
    const output = formatQuotaReport(report);
    assert.ok(output.includes("models/gemini-2.0-flash"));
    assert.ok(output.includes("models/text-embedding-004"));
  });

  it("includes token limit info", () => {
    const report = buildQuotaReport([flashModel], "test");
    const output = formatQuotaReport(report);
    assert.ok(output.includes("1,048,576"));
    assert.ok(output.includes("8,192"));
  });

  it("shows summary with correct counts", () => {
    const report = buildQuotaReport(allModels, "test");
    const output = formatQuotaReport(report);
    assert.ok(output.includes("3 models"));
    assert.ok(output.includes("2 generative"));
  });

  it("handles empty model list", () => {
    const report = buildQuotaReport([], "empty");
    const output = formatQuotaReport(report);
    assert.ok(output.includes("0 models"));
    assert.ok(output.includes("0 generative"));
  });

  it("includes free tier section when limits present", () => {
    const report = buildQuotaReport([], "test", [freeTierRequestLimit], [sampleUsage]);
    const output = formatQuotaReport(report);
    assert.ok(output.includes("Free Tier Quota"));
    assert.ok(output.includes("34 / 1500"));
  });

  it("shows usage data points count", () => {
    const report = buildQuotaReport([], "test", [freeTierRequestLimit], [sampleUsage]);
    const output = formatQuotaReport(report);
    assert.ok(output.includes("1 usage data point"));
  });

  it("notes when no monitoring data available", () => {
    const report = buildQuotaReport([], "test", [freeTierRequestLimit], []);
    const output = formatQuotaReport(report);
    assert.ok(output.includes("no data points"));
  });
});

// ---------------------------------------------------------------------------
// toQuotaJson
// ---------------------------------------------------------------------------

describe("toQuotaJson", () => {
  it("includes label and timestamp", () => {
    const report = buildQuotaReport([], "test label");
    const json = toQuotaJson(report);
    assert.equal(json.label, "test label");
    assert.match(json.timestamp, /^\d{4}-\d{2}-\d{2}T/);
  });

  it("includes free tier quotas with used/limit/remaining", () => {
    const report = buildQuotaReport([], "test", [freeTierRequestLimit], [sampleUsage]);
    const json = toQuotaJson(report);
    assert.equal(json.freeTierQuotas.length, 1);
    assert.equal(json.freeTierQuotas[0]?.used, 34);
    assert.equal(json.freeTierQuotas[0]?.limit, 1500);
    assert.equal(json.freeTierQuotas[0]?.remaining, 1466);
  });

  it("includes only generative models in compact form", () => {
    const report = buildQuotaReport(allModels, "test");
    const json = toQuotaJson(report);
    assert.equal(json.generativeModels.length, 2);
    assert.ok(json.generativeModels.every((m) => "inputTokenLimit" in m));
    assert.ok(!json.generativeModels.some((m) => "temperature" in m));
  });

  it("includes raw quota limits and usage for advanced consumption", () => {
    const report = buildQuotaReport([], "test", allLimits, [sampleUsage]);
    const json = toQuotaJson(report);
    assert.equal(json.allQuotaLimits.length, 4);
    assert.equal(json.usageDataPoints.length, 1);
  });
});
