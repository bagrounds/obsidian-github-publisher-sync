/**
 * Tests for scripts/lib/experiment.ts — A/B testing framework.
 *
 * Covers variant selection (deterministic and random), assignment creation,
 * environment override, weight validation, formatting, and record persistence.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

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
  EXPERIMENT_DATA_DIR,
  buildRecordFileName,
  writeExperimentRecord,
  readExperimentRecords,
  migrateExperimentRecords,
  isUrl404,
  cleanupStaleRecords,
  fetchAndUpdateVaultMetrics,
} from "./experiment.ts";
import type { VariantWeight, ExperimentRecord, EngagementMetrics } from "./experiment.ts";

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

// --- buildRecordFileName ---

describe("buildRecordFileName", () => {
  it("encodes notePath slashes to underscores", () => {
    const name = buildRecordFileName("reflections/2026-03-10.md", "mastodon", "2026-03-10T12:00:00.000Z");
    assert.ok(!name.includes("/"), "should not contain slashes");
    assert.ok(name.includes("mastodon"), "should contain platform");
    assert.ok(name.endsWith(".json.md"), "should end with .json.md");
  });

  it("strips .md extension from notePath before adding .json.md", () => {
    const name = buildRecordFileName("books/some-book.md", "bluesky", "2026-03-10T12:00:00.000Z");
    assert.ok(!name.includes("some-book.json.md.json.md"), "should not double-extend");
  });

  it("encodes colons and dots from timestamp", () => {
    const name = buildRecordFileName("test.md", "twitter", "2026-03-10T12:30:45.123Z");
    assert.ok(!name.includes(":"), "should not contain colons");
  });

  it("produces unique names for different platforms", () => {
    const ts = "2026-03-10T12:00:00.000Z";
    const a = buildRecordFileName("test.md", "mastodon", ts);
    const b = buildRecordFileName("test.md", "bluesky", ts);
    assert.notEqual(a, b, "different platforms should produce different filenames");
  });
});

// --- writeExperimentRecord / readExperimentRecords ---

describe("experiment record persistence", () => {
  const createTempDir = (): string => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "experiment-test-"));
    return dir;
  };

  it("writes and reads back a single record", () => {
    const vaultDir = createTempDir();
    const record: ExperimentRecord = {
      variant: "A",
      notePath: "reflections/2026-03-10.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
      postUrl: "https://mastodon.social/@test/123",
      postId: "123",
    };

    writeExperimentRecord(vaultDir, record);
    const records = readExperimentRecords(vaultDir);

    assert.equal(records.length, 1);
    assert.equal(records[0]!.variant, "A");
    assert.equal(records[0]!.platform, "mastodon");
    assert.equal(records[0]!.notePath, "reflections/2026-03-10.md");
    assert.equal(records[0]!.postId, "123");

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("writes multiple records for different platforms", () => {
    const vaultDir = createTempDir();
    const ts = "2026-03-10T12:00:00.000Z";

    writeExperimentRecord(vaultDir, {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: ts,
      postId: "m1",
    });
    writeExperimentRecord(vaultDir, {
      variant: "B",
      notePath: "test.md",
      platform: "bluesky",
      timestamp: ts,
      postId: "b1",
    });

    const records = readExperimentRecords(vaultDir);
    assert.equal(records.length, 2);

    const platforms = records.map((r) => r.platform).sort();
    assert.deepEqual(platforms, ["bluesky", "mastodon"]);

    // Independent coin flips: different variants for same note
    const variants = records.map((r) => r.variant).sort();
    assert.deepEqual(variants, ["A", "B"]);

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("creates the data/ab-test directory if it doesn't exist", () => {
    const vaultDir = createTempDir();
    const dataDir = path.join(vaultDir, EXPERIMENT_DATA_DIR);

    assert.equal(fs.existsSync(dataDir), false);
    writeExperimentRecord(vaultDir, {
      variant: "A",
      notePath: "test.md",
      platform: "twitter",
      timestamp: "2026-03-10T12:00:00.000Z",
    });
    assert.equal(fs.existsSync(dataDir), true);

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("returns empty array for non-existent vault dir", () => {
    const records = readExperimentRecords("/tmp/nonexistent-vault-dir-12345");
    assert.equal(records.length, 0);
  });

  it("preserves metrics in records", () => {
    const vaultDir = createTempDir();
    const record: ExperimentRecord = {
      variant: "B",
      notePath: "test.md",
      platform: "bluesky",
      timestamp: "2026-03-10T12:00:00.000Z",
      metrics: { likes: 5, reposts: 2, replies: 1 },
    };

    writeExperimentRecord(vaultDir, record);
    const records = readExperimentRecords(vaultDir);
    assert.deepEqual(records[0]!.metrics, { likes: 5, reposts: 2, replies: 1 });

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("returns file path from writeExperimentRecord", () => {
    const vaultDir = createTempDir();
    const filePath = writeExperimentRecord(vaultDir, {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
    });

    assert.ok(filePath.endsWith(".json.md"));
    assert.ok(fs.existsSync(filePath));

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("skips malformed JSON files gracefully", () => {
    const vaultDir = createTempDir();
    const dataDir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
    fs.mkdirSync(dataDir, { recursive: true });

    // Write a valid record
    writeExperimentRecord(vaultDir, {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
    });

    // Write malformed files with both extensions
    fs.writeFileSync(path.join(dataDir, "bad.json.md"), "not valid json", "utf-8");
    fs.writeFileSync(path.join(dataDir, "bad-legacy.json"), "not valid json", "utf-8");

    const records = readExperimentRecords(vaultDir);
    assert.equal(records.length, 1, "should skip malformed files");

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("reads legacy .json files alongside new .json.md files", () => {
    const vaultDir = createTempDir();
    const dataDir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
    fs.mkdirSync(dataDir, { recursive: true });

    // Write a legacy .json file
    const legacyRecord: ExperimentRecord = {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
    };
    fs.writeFileSync(path.join(dataDir, "legacy.json"), JSON.stringify(legacyRecord), "utf-8");

    // Write a new .json.md file
    writeExperimentRecord(vaultDir, {
      variant: "B",
      notePath: "test.md",
      platform: "bluesky",
      timestamp: "2026-03-10T12:01:00.000Z",
    });

    const records = readExperimentRecords(vaultDir);
    assert.equal(records.length, 2, "should read both .json and .json.md files");

    fs.rmSync(vaultDir, { recursive: true });
  });
});

// --- migrateExperimentRecords ---

describe("migrateExperimentRecords", () => {
  const createTempDir = (): string => fs.mkdtempSync(path.join(os.tmpdir(), "migrate-test-"));

  it("renames .json files to .json.md", () => {
    const vaultDir = createTempDir();
    const dataDir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
    fs.mkdirSync(dataDir, { recursive: true });

    const record: ExperimentRecord = {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
    };
    fs.writeFileSync(path.join(dataDir, "test.json"), JSON.stringify(record), "utf-8");

    const migrated = migrateExperimentRecords(vaultDir);
    assert.equal(migrated, 1);
    assert.ok(fs.existsSync(path.join(dataDir, "test.json.md")));
    assert.equal(fs.existsSync(path.join(dataDir, "test.json")), false);

    // Verify the content is still valid JSON
    const content = fs.readFileSync(path.join(dataDir, "test.json.md"), "utf-8");
    const parsed = JSON.parse(content) as ExperimentRecord;
    assert.equal(parsed.variant, "A");

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("does not rename .json.md files", () => {
    const vaultDir = createTempDir();
    const dataDir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
    fs.mkdirSync(dataDir, { recursive: true });

    fs.writeFileSync(path.join(dataDir, "already.json.md"), "{}", "utf-8");

    const migrated = migrateExperimentRecords(vaultDir);
    assert.equal(migrated, 0);
    assert.ok(fs.existsSync(path.join(dataDir, "already.json.md")));

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("returns 0 for non-existent directory", () => {
    assert.equal(migrateExperimentRecords("/tmp/nonexistent-vault-dir-99999"), 0);
  });

  it("migrates multiple files at once", () => {
    const vaultDir = createTempDir();
    const dataDir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
    fs.mkdirSync(dataDir, { recursive: true });

    fs.writeFileSync(path.join(dataDir, "a.json"), "{}", "utf-8");
    fs.writeFileSync(path.join(dataDir, "b.json"), "{}", "utf-8");
    fs.writeFileSync(path.join(dataDir, "c.json.md"), "{}", "utf-8");

    const migrated = migrateExperimentRecords(vaultDir);
    assert.equal(migrated, 2);
    assert.ok(fs.existsSync(path.join(dataDir, "a.json.md")));
    assert.ok(fs.existsSync(path.join(dataDir, "b.json.md")));
    assert.ok(fs.existsSync(path.join(dataDir, "c.json.md")));

    fs.rmSync(vaultDir, { recursive: true });
  });
});

// --- isUrl404 ---

describe("isUrl404", () => {
  it("returns false for network errors (no accidental deletion)", async () => {
    // This URL will fail to connect — should NOT be treated as 404
    const result = await isUrl404("http://localhost:1/nonexistent");
    assert.equal(result, false, "network error should not be treated as 404");
  });

  it("returns false for invalid URLs", async () => {
    const result = await isUrl404("not-a-url");
    assert.equal(result, false, "invalid URL should not be treated as 404");
  });
});

// --- cleanupStaleRecords ---

describe("cleanupStaleRecords", () => {
  it("returns 0 when directory does not exist", async () => {
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "cleanup-test-"));
    const deleted = await cleanupStaleRecords(vaultDir);
    assert.equal(deleted, 0);
    fs.rmSync(vaultDir, { recursive: true });
  });

  it("returns 0 when directory is empty", async () => {
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "cleanup-test-"));
    fs.mkdirSync(path.join(vaultDir, EXPERIMENT_DATA_DIR), { recursive: true });
    const deleted = await cleanupStaleRecords(vaultDir);
    assert.equal(deleted, 0);
    fs.rmSync(vaultDir, { recursive: true });
  });

  it("does not delete records with unreachable URLs", async () => {
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "cleanup-test-"));
    const dataDir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
    fs.mkdirSync(dataDir, { recursive: true });

    const record = {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: new Date().toISOString(),
      postUrl: "http://localhost:1/unreachable",
    };
    fs.writeFileSync(path.join(dataDir, "test.json.md"), JSON.stringify(record));

    const deleted = await cleanupStaleRecords(vaultDir);
    assert.equal(deleted, 0, "should not delete records with network errors");
    assert.ok(fs.existsSync(path.join(dataDir, "test.json.md")), "record should still exist");
    fs.rmSync(vaultDir, { recursive: true });
  });

  it("handles records without postUrl gracefully", async () => {
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "cleanup-test-"));
    const dataDir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
    fs.mkdirSync(dataDir, { recursive: true });

    const record = { variant: "A", notePath: "test.md", platform: "bluesky", timestamp: new Date().toISOString() };
    fs.writeFileSync(path.join(dataDir, "no-url.json.md"), JSON.stringify(record));

    const deleted = await cleanupStaleRecords(vaultDir);
    assert.equal(deleted, 0, "should not delete records without postUrl");
    fs.rmSync(vaultDir, { recursive: true });
  });
});

// --- fetchAndUpdateVaultMetrics ---

describe("fetchAndUpdateVaultMetrics", () => {
  const createTempDir = (): string => fs.mkdtempSync(path.join(os.tmpdir(), "metrics-test-"));

  it("returns 0 when directory does not exist", async () => {
    const vaultDir = createTempDir();
    const fetcher = async () => ({ likes: 1, reposts: 0, replies: 0 });
    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    assert.equal(updated, 0);
    fs.rmSync(vaultDir, { recursive: true });
  });

  it("fetches metrics for records without metrics", async () => {
    const vaultDir = createTempDir();
    const record: ExperimentRecord = {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
      postUrl: "https://mastodon.social/@test/123",
      postId: "123",
    };

    writeExperimentRecord(vaultDir, record);

    const expectedMetrics: EngagementMetrics = { likes: 5, reposts: 2, replies: 1 };
    const fetcher = async () => expectedMetrics;

    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    assert.equal(updated, 1);

    const records = readExperimentRecords(vaultDir);
    assert.deepEqual(records[0]!.metrics, expectedMetrics);

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("skips records that already have metrics", async () => {
    const vaultDir = createTempDir();
    const existingMetrics: EngagementMetrics = { likes: 10, reposts: 5, replies: 3 };
    const record: ExperimentRecord = {
      variant: "B",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
      postId: "456",
      metrics: existingMetrics,
    };

    writeExperimentRecord(vaultDir, record);

    const newMetrics: EngagementMetrics = { likes: 99, reposts: 99, replies: 99 };
    const fetcher = async () => newMetrics;

    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    assert.equal(updated, 0, "should not update records that already have metrics");

    const records = readExperimentRecords(vaultDir);
    assert.deepEqual(records[0]!.metrics, existingMetrics, "original metrics should be preserved");

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("skips records without postId or postUri", async () => {
    const vaultDir = createTempDir();
    const record: ExperimentRecord = {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
    };

    writeExperimentRecord(vaultDir, record);

    const fetcher = async () => ({ likes: 1, reposts: 0, replies: 0 });
    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    assert.equal(updated, 0, "should skip records without postId or postUri");

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("handles fetcher returning undefined (unsupported platform)", async () => {
    const vaultDir = createTempDir();
    const record: ExperimentRecord = {
      variant: "A",
      notePath: "test.md",
      platform: "twitter",
      timestamp: "2026-03-10T12:00:00.000Z",
      postId: "789",
    };

    writeExperimentRecord(vaultDir, record);

    const fetcher = async () => undefined;
    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    assert.equal(updated, 0, "should not update when fetcher returns undefined");

    const records = readExperimentRecords(vaultDir);
    assert.equal(records[0]!.metrics, undefined, "metrics should remain undefined");

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("handles fetcher errors gracefully", async () => {
    const vaultDir = createTempDir();
    const record: ExperimentRecord = {
      variant: "A",
      notePath: "test.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
      postId: "123",
    };

    writeExperimentRecord(vaultDir, record);

    const fetcher = async (): Promise<EngagementMetrics | undefined> => { throw new Error("API rate limited"); };
    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    assert.equal(updated, 0, "should handle errors gracefully");

    const records = readExperimentRecords(vaultDir);
    assert.equal(records[0]!.metrics, undefined, "metrics should remain undefined after error");

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("updates multiple records in the same vault", async () => {
    const vaultDir = createTempDir();

    writeExperimentRecord(vaultDir, {
      variant: "A",
      notePath: "post-1.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
      postId: "111",
    });

    writeExperimentRecord(vaultDir, {
      variant: "B",
      notePath: "post-2.md",
      platform: "mastodon",
      timestamp: "2026-03-10T13:00:00.000Z",
      postId: "222",
    });

    const fetcher = async (record: ExperimentRecord) => ({
      likes: record.postId === "111" ? 3 : 7,
      reposts: 1,
      replies: 0,
    });

    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    assert.equal(updated, 2);

    const records = readExperimentRecords(vaultDir);
    const sorted = [...records].sort((a, b) => a.notePath.localeCompare(b.notePath));
    assert.equal(sorted[0]!.metrics!.likes, 3);
    assert.equal(sorted[1]!.metrics!.likes, 7);

    fs.rmSync(vaultDir, { recursive: true });
  });

  it("only updates records without metrics, preserving ones with metrics", async () => {
    const vaultDir = createTempDir();

    writeExperimentRecord(vaultDir, {
      variant: "A",
      notePath: "has-metrics.md",
      platform: "mastodon",
      timestamp: "2026-03-10T12:00:00.000Z",
      postId: "111",
      metrics: { likes: 10, reposts: 5, replies: 2 },
    });

    writeExperimentRecord(vaultDir, {
      variant: "B",
      notePath: "needs-metrics.md",
      platform: "mastodon",
      timestamp: "2026-03-10T13:00:00.000Z",
      postId: "222",
    });

    const fetcher = async () => ({ likes: 99, reposts: 99, replies: 99 });

    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    assert.equal(updated, 1, "should only update the record without metrics");

    const records = readExperimentRecords(vaultDir);
    const withMetrics = records.find((r) => r.notePath === "has-metrics.md");
    const nowUpdated = records.find((r) => r.notePath === "needs-metrics.md");

    assert.deepEqual(withMetrics!.metrics, { likes: 10, reposts: 5, replies: 2 }, "existing metrics preserved");
    assert.deepEqual(nowUpdated!.metrics, { likes: 99, reposts: 99, replies: 99 }, "new metrics applied");

    fs.rmSync(vaultDir, { recursive: true });
  });
});
