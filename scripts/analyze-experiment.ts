/**
 * A/B test experiment analysis CLI.
 *
 * Fetches engagement metrics from Mastodon and Bluesky for posts
 * that participated in the A/B test, then computes statistical
 * analysis to determine if a variant is outperforming.
 *
 * Usage:
 *   npx tsx scripts/analyze-experiment.ts --data experiment-log.json
 *   npx tsx scripts/analyze-experiment.ts --help
 *
 * The experiment log is a JSON file with an array of experiment records:
 * [
 *   {
 *     "variant": "A",
 *     "notePath": "reflections/2026-03-10.md",
 *     "platform": "mastodon",
 *     "postUrl": "https://mastodon.social/@user/123",
 *     "postId": "123",
 *     "timestamp": "2026-03-10T17:00:00Z"
 *   },
 *   ...
 * ]
 *
 * @module analyze-experiment
 */

import fs from "node:fs";

import type { VariantId } from "./lib/experiment.ts";
import { isVariantId } from "./lib/experiment.ts";
import {
  totalEngagement,
  analyzeExperiment,
  formatExperimentSummary,
} from "./lib/analytics.ts";
import type { EngagementMetrics } from "./lib/experiment.ts";

// --- Experiment Log Types ---

interface ExperimentRecord {
  readonly variant: VariantId;
  readonly notePath: string;
  readonly platform: "mastodon" | "bluesky";
  readonly postUrl: string;
  readonly postId: string;
  readonly timestamp: string;
  readonly metrics?: EngagementMetrics;
}

// --- CLI Argument Parsing ---

const parseAnalysisArgs = (): { dataFile: string } => {
  const args = process.argv.slice(2);
  let dataFile = "experiment-log.json";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--data" && args[i + 1]) {
      dataFile = args[i + 1] as string;
      i++;
    }
    if (args[i] === "--help") {
      console.log(`
Usage: npx tsx scripts/analyze-experiment.ts [options]

Options:
  --data <file>    Path to experiment log JSON file (default: experiment-log.json)
  --help           Show this help message

The experiment log should be a JSON array of records with:
  variant, notePath, platform, postUrl, postId, timestamp, metrics?
`);
      process.exit(0);
    }
  }

  return { dataFile };
};

// --- Analysis ---

/**
 * Load and validate experiment records from a JSON file.
 */
const loadExperimentLog = (filePath: string): readonly ExperimentRecord[] => {
  if (!fs.existsSync(filePath)) {
    console.error(`❌ Experiment log not found: ${filePath}`);
    console.log(`\nTo start collecting data, create a JSON file with experiment records.`);
    console.log(`The pipeline logs variant assignments — collect these into a JSON array.`);
    process.exit(1);
  }

  const raw = JSON.parse(fs.readFileSync(filePath, "utf-8")) as unknown[];

  return raw.filter((record): record is ExperimentRecord => {
    const r = record as Record<string, unknown>;
    return (
      typeof r.variant === "string" &&
      isVariantId(r.variant) &&
      typeof r.platform === "string" &&
      typeof r.postUrl === "string"
    );
  });
};

/**
 * Group experiment records by variant and compute engagement totals.
 */
const groupByVariant = (
  records: readonly ExperimentRecord[],
): { a: readonly number[]; b: readonly number[] } => {
  const a: number[] = [];
  const b: number[] = [];

  for (const record of records) {
    if (record.metrics) {
      const engagement = totalEngagement(record.metrics);
      if (record.variant === "A") a.push(engagement);
      else b.push(engagement);
    }
  }

  return { a, b };
};

/**
 * Print per-record detail report.
 */
const printDetailReport = (records: readonly ExperimentRecord[]): void => {
  console.log(`\n📋 Experiment Records (${records.length} total)\n`);

  for (const record of records) {
    const metrics = record.metrics
      ? `❤️ ${record.metrics.likes} | 🔁 ${record.metrics.reposts} | 💬 ${record.metrics.replies}`
      : "⏳ No metrics yet";
    console.log(
      `  [${record.variant}] ${record.platform} | ${record.notePath} | ${metrics}`,
    );
  }
};

// --- Main ---

const main = (): void => {
  const { dataFile } = parseAnalysisArgs();
  const records = loadExperimentLog(dataFile);

  console.log(`📂 Loaded ${records.length} experiment records from ${dataFile}`);

  printDetailReport(records);

  const recordsWithMetrics = records.filter((r) => r.metrics !== undefined);
  if (recordsWithMetrics.length < 4) {
    console.log(`\n⚠️  Not enough data for statistical analysis (need at least 2 per variant).`);
    console.log(`   Currently have ${recordsWithMetrics.length} records with metrics.`);
    return;
  }

  const { a, b } = groupByVariant(recordsWithMetrics);

  if (a.length < 2 || b.length < 2) {
    console.log(`\n⚠️  Need at least 2 observations per variant for analysis.`);
    console.log(`   Variant A: ${a.length}, Variant B: ${b.length}`);
    return;
  }

  const summary = analyzeExperiment(a, b);
  console.log(`\n${formatExperimentSummary(summary)}`);
};

// Entry point guard
const isMainModule = process.argv[1]?.endsWith("analyze-experiment.ts");
if (isMainModule) {
  main();
}

export { loadExperimentLog, groupByVariant, type ExperimentRecord };
