/**
 * A/B test experiment analysis CLI.
 *
 * Reads experiment records from the vault's data/ab-test directory
 * (written by the posting pipeline), then computes statistical
 * analysis to determine if a variant is outperforming.
 *
 * Usage:
 *   npx tsx scripts/analyze-experiment.ts --vault /path/to/vault
 *   npx tsx scripts/analyze-experiment.ts --data experiment-log.json
 *   npx tsx scripts/analyze-experiment.ts --help
 *
 * @module analyze-experiment
 */

import fs from "node:fs";

import {
  readExperimentRecords,
  isVariantId,
} from "./lib/experiment.ts";
import type { ExperimentRecord } from "./lib/experiment.ts";
import {
  totalEngagement,
  analyzeExperiment,
  formatExperimentSummary,
} from "./lib/analytics.ts";

// --- CLI Argument Parsing ---

const parseAnalysisArgs = (): { vaultDir?: string; dataFile?: string } => {
  const args = process.argv.slice(2);
  let vaultDir: string | undefined;
  let dataFile: string | undefined;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--vault" && args[i + 1]) {
      vaultDir = args[i + 1] as string;
      i++;
    }
    if (args[i] === "--data" && args[i + 1]) {
      dataFile = args[i + 1] as string;
      i++;
    }
    if (args[i] === "--help") {
      console.log(`
Usage: npx tsx scripts/analyze-experiment.ts [options]

Options:
  --vault <dir>    Path to Obsidian vault (reads from data/ab-test/)
  --data <file>    Path to experiment log JSON file (legacy, array of records)
  --help           Show this help message

Reads experiment records from the vault's data/ab-test/ directory.
Each record is a JSON file written by the posting pipeline.
`);
      process.exit(0);
    }
  }

  return { vaultDir, dataFile };
};

// --- Analysis ---

/**
 * Load experiment records from vault directory or legacy JSON file.
 */
const loadRecords = (vaultDir?: string, dataFile?: string): readonly ExperimentRecord[] => {
  if (vaultDir) {
    const records = readExperimentRecords(vaultDir);
    console.log(`📂 Loaded ${records.length} experiment records from vault`);
    return records;
  }

  if (dataFile) {
    if (!fs.existsSync(dataFile)) {
      console.error(`❌ Experiment log not found: ${dataFile}`);
      process.exit(1);
    }
    const raw = JSON.parse(fs.readFileSync(dataFile, "utf-8")) as unknown[];
    const records = raw.filter((record): record is ExperimentRecord => {
      const r = record as Record<string, unknown>;
      return typeof r.variant === "string" && isVariantId(r.variant);
    });
    console.log(`📂 Loaded ${records.length} experiment records from ${dataFile}`);
    return records;
  }

  console.error(`❌ Specify --vault or --data`);
  process.exit(1);
};

/**
 * Group experiment records by variant and compute engagement totals.
 */
export const groupByVariant = (
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

/**
 * Run analysis and print results. Exported for pipeline integration.
 */
export const runAnalysis = (records: readonly ExperimentRecord[]): void => {
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

// --- Main ---

const main = (): void => {
  const { vaultDir, dataFile } = parseAnalysisArgs();
  const records = loadRecords(vaultDir, dataFile);
  runAnalysis(records);
};

// Entry point guard
const isMainModule = process.argv[1]?.endsWith("analyze-experiment.ts");
if (isMainModule) {
  main();
}
