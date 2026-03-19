/**
 * Tests for scripts/lib/gemini-quota.ts — Gemini quota reporting.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  type GeminiModelInfo,
  generativeModels,
  buildQuotaReport,
  formatQuotaReport,
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
    assert.ok(output.includes("3 total models"));
    assert.ok(output.includes("2 generative"));
  });

  it("separates generative from non-generative models", () => {
    const report = buildQuotaReport(allModels, "test");
    const output = formatQuotaReport(report);
    assert.ok(output.includes("Content-generation models (2)"));
    assert.ok(output.includes("Other models (1)"));
  });

  it("handles empty model list", () => {
    const report = buildQuotaReport([], "empty");
    const output = formatQuotaReport(report);
    assert.ok(output.includes("0 total models"));
    assert.ok(output.includes("0 generative"));
  });
});
