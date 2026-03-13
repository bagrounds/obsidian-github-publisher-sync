/**
 * A/B testing experiment framework.
 *
 * Provides variant selection, assignment logging, and result tracking
 * for social media post prompt experiments.
 *
 * Design principles:
 * - Pure functions for deterministic variant selection (given a seed)
 * - Cryptographically random selection for production use
 * - Immutable experiment records as value objects
 * - Functorial mapping over experiment results
 *
 * @module experiment
 */

// --- Domain Types ---

/** Identifies a prompt variant in the experiment. */
export type VariantId = "A" | "B";

/** All valid variant identifiers. */
export const VARIANT_IDS: readonly VariantId[] = ["A", "B"] as const;

/** Probability weight for each variant (must sum to 1). */
export interface VariantWeight {
  readonly variant: VariantId;
  readonly weight: number;
}

/** Default: equal 50/50 split. */
export const DEFAULT_WEIGHTS: readonly VariantWeight[] = [
  { variant: "A", weight: 0.5 },
  { variant: "B", weight: 0.5 },
] as const;

/** Immutable record of a variant assignment for a single post on a single platform. */
export interface ExperimentAssignment {
  readonly variant: VariantId;
  readonly timestamp: string;
  readonly notePath: string;
  readonly platform: string;
}

/**
 * A persisted experiment record — an assignment enriched with post identifiers
 * so we can later fetch engagement metrics and run analysis.
 */
export interface ExperimentRecord {
  readonly variant: VariantId;
  readonly notePath: string;
  readonly platform: string;
  readonly timestamp: string;
  readonly postUrl?: string;
  readonly postId?: string;
  readonly postUri?: string;
  readonly metrics?: EngagementMetrics;
}

/** Engagement metrics fetched from a social platform. */
export interface EngagementMetrics {
  readonly likes: number;
  readonly reposts: number;
  readonly replies: number;
}

/** A complete experiment observation: assignment + outcome. */
export interface ExperimentObservation {
  readonly assignment: ExperimentAssignment;
  readonly metrics: EngagementMetrics;
  readonly postUrl: string;
}

// --- Variant Selection (Pure) ---

/**
 * Select a variant given a random value in [0, 1) and weight configuration.
 *
 * This is a pure function — the randomness is injected as a parameter,
 * making it deterministic and testable.
 *
 * Conceptually, this partitions [0, 1) into intervals proportional to
 * variant weights, then returns whichever interval contains the random value.
 *
 * @example
 * selectVariant(0.3, DEFAULT_WEIGHTS) // => "A" (0.3 < 0.5)
 * selectVariant(0.7, DEFAULT_WEIGHTS) // => "B" (0.7 >= 0.5)
 */
export const selectVariant = (
  random: number,
  weights: readonly VariantWeight[] = DEFAULT_WEIGHTS,
): VariantId => {
  let cumulative = 0;
  for (const { variant, weight } of weights) {
    cumulative += weight;
    if (random < cumulative) return variant;
  }
  // Fallback for floating-point edge cases (random === 1.0)
  return weights[weights.length - 1]!.variant;
};

/**
 * Randomly select a variant for production use.
 * Uses Math.random() — non-deterministic.
 */
export const randomVariant = (
  weights: readonly VariantWeight[] = DEFAULT_WEIGHTS,
): VariantId => selectVariant(Math.random(), weights);

// --- Assignment Construction ---

/**
 * Create an experiment assignment record.
 * Pure function — all inputs are explicit parameters.
 */
export const createAssignment = (
  variant: VariantId,
  notePath: string,
  platform: string,
  timestamp: string = new Date().toISOString(),
): ExperimentAssignment => ({
  variant,
  timestamp,
  notePath,
  platform,
});

// --- Variant Override (Environment) ---

/**
 * Check for an environment variable override of the variant selection.
 * Returns undefined if no override is set, allowing random selection to proceed.
 *
 * This enables manual testing: `AB_TEST_VARIANT=A npx tsx scripts/auto-post.ts`
 */
export const getVariantOverride = (): VariantId | undefined => {
  const override = process.env.AB_TEST_VARIANT;
  if (override === "A" || override === "B") return override;
  return undefined;
};

/**
 * Resolve the variant to use: override if set, otherwise random.
 */
export const resolveVariant = (
  weights: readonly VariantWeight[] = DEFAULT_WEIGHTS,
): VariantId => getVariantOverride() ?? randomVariant(weights);

// --- Logging ---

/**
 * Format an experiment assignment for logging.
 * Returns a human-readable string describing the assignment.
 */
export const formatAssignment = (assignment: ExperimentAssignment): string =>
  `🧪 Variant ${assignment.variant} | ${assignment.platform} | ${assignment.notePath} | ${assignment.timestamp}`;

// --- Validation ---

/**
 * Validate that variant weights sum to approximately 1.
 * Returns true if weights are valid.
 */
export const validateWeights = (
  weights: readonly VariantWeight[],
): boolean => {
  const sum = weights.reduce((acc, { weight }) => acc + weight, 0);
  return Math.abs(sum - 1.0) < 0.001;
};

/**
 * Check if a string is a valid VariantId.
 */
export const isVariantId = (value: string): value is VariantId =>
  value === "A" || value === "B";

// --- Experiment Log Persistence ---

import fs from "node:fs";
import path from "node:path";

/** Directory within the vault for experiment data. */
export const EXPERIMENT_DATA_DIR = "data/ab-test";

/**
 * Build the file path for an experiment record within the vault.
 * Each record gets its own file named by timestamp + platform.
 * Uses .json.md extension so Obsidian sync handles the files.
 */
export const buildRecordFileName = (
  notePath: string,
  platform: string,
  timestamp: string,
): string => {
  const safePath = notePath.replace(/[/\\]/g, "_").replace(/\.md$/, "");
  const safeTime = timestamp.replace(/[:.]/g, "-");
  return `${safeTime}_${platform}_${safePath}.json.md`;
};

/**
 * Write an experiment record to the vault's data directory.
 * Creates the directory if it doesn't exist.
 * This is called during the posting pipeline, BEFORE pushing the vault.
 */
export const writeExperimentRecord = (
  vaultDir: string,
  record: ExperimentRecord,
): string => {
  const dir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
  fs.mkdirSync(dir, { recursive: true });

  const fileName = buildRecordFileName(
    record.notePath,
    record.platform,
    record.timestamp,
  );
  const filePath = path.join(dir, fileName);
  fs.writeFileSync(filePath, JSON.stringify(record, null, 2), "utf-8");

  return filePath;
};

/**
 * Migrate existing .json experiment records to .json.md so Obsidian sync handles them.
 * Renames files in-place. Idempotent — skips files that already have .json.md extension.
 */
export const migrateExperimentRecords = (vaultDir: string): number => {
  const dir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
  if (!fs.existsSync(dir)) return 0;

  let migrated = 0;
  for (const f of fs.readdirSync(dir)) {
    if (f.endsWith(".json") && !f.endsWith(".json.md")) {
      const oldPath = path.join(dir, f);
      const newPath = path.join(dir, `${f}.md`);
      fs.renameSync(oldPath, newPath);
      migrated++;
    }
  }
  return migrated;
};

/**
 * Read all experiment records from the vault's data directory.
 * Reads both .json.md (current) and .json (legacy) files.
 * Returns an empty array if the directory doesn't exist.
 */
export const readExperimentRecords = (
  vaultDir: string,
): readonly ExperimentRecord[] => {
  const dir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
  if (!fs.existsSync(dir)) return [];

  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".json.md") || f.endsWith(".json"))
    .map((f) => {
      try {
        const content = fs.readFileSync(path.join(dir, f), "utf-8");
        return JSON.parse(content) as ExperimentRecord;
      } catch {
        console.warn(`⚠️ Skipping malformed experiment record: ${f}`);
        return null;
      }
    })
    .filter((r): r is ExperimentRecord => r !== null);
};

// --- Stale Record Cleanup ---

/** Timeout for URL health checks during stale record cleanup (ms). */
const URL_CHECK_TIMEOUT_MS = 10_000;

/**
 * Check if a URL returns a 404 (Not Found) status.
 * Returns true if the URL is reachable but returns 404.
 * Returns false for all other cases (success, network error, timeout, etc.)
 * to avoid accidentally deleting valid records.
 */
export const isUrl404 = async (url: string): Promise<boolean> => {
  try {
    const response = await fetch(url, {
      method: "HEAD",
      signal: AbortSignal.timeout(URL_CHECK_TIMEOUT_MS),
    });
    return response.status === 404;
  } catch {
    // Network error, timeout, etc. — don't delete the record
    return false;
  }
};

/**
 * Clean up stale experiment records by checking post URLs for 404.
 *
 * Reads all records from the vault, HEAD-requests each post URL,
 * and deletes records whose URLs return 404. This handles the case
 * where posts are deleted from the platform (e.g. manually removed
 * from Mastodon/Bluesky) — we don't want to keep stale records
 * that would pollute the experiment analysis.
 *
 * Returns the number of records deleted.
 */
export const cleanupStaleRecords = async (vaultDir: string): Promise<number> => {
  const dir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
  if (!fs.existsSync(dir)) return 0;

  const files = fs.readdirSync(dir)
    .filter((f) => f.endsWith(".json.md") || f.endsWith(".json"));

  let deleted = 0;

  for (const f of files) {
    const filePath = path.join(dir, f);
    try {
      const content = fs.readFileSync(filePath, "utf-8");
      const record = JSON.parse(content) as ExperimentRecord;

      if (record.postUrl) {
        const is404 = await isUrl404(record.postUrl);
        if (is404) {
          fs.unlinkSync(filePath);
          console.log(`🗑️ Deleted stale record (404): ${f} → ${record.postUrl}`);
          deleted++;
        }
      }
    } catch {
      // Skip malformed records — they'll be caught by readExperimentRecords
    }
  }

  return deleted;
};

// --- Vault Metric Fetching ---

/**
 * A platform-specific metric fetcher: given a record, returns engagement metrics.
 * Returns undefined if the record's platform is unsupported or credentials are unavailable.
 */
export type MetricFetcher = (record: ExperimentRecord) => Promise<EngagementMetrics | undefined>;

/**
 * Fetch and update engagement metrics for all experiment records in the vault.
 *
 * Reads each record from the vault's data/ab-test directory. For records
 * that have a postId but no metrics yet, calls the provided fetcher to
 * retrieve current engagement metrics from the platform API, then writes
 * the updated record back to disk.
 *
 * This bridges the gap between the posting pipeline (which creates records
 * without metrics) and the analysis pipeline (which needs metrics to compute
 * statistics).
 *
 * Returns the number of records updated.
 */
export const fetchAndUpdateVaultMetrics = async (
  vaultDir: string,
  fetcher: MetricFetcher,
): Promise<number> => {
  const dir = path.join(vaultDir, EXPERIMENT_DATA_DIR);
  if (!fs.existsSync(dir)) return 0;

  const files = fs.readdirSync(dir)
    .filter((f) => f.endsWith(".json.md") || f.endsWith(".json"));

  let updated = 0;

  for (const f of files) {
    const filePath = path.join(dir, f);
    try {
      const content = fs.readFileSync(filePath, "utf-8");
      const record = JSON.parse(content) as ExperimentRecord;

      if (record.metrics) continue;
      if (!record.postId && !record.postUri) continue;

      const metrics = await fetcher(record);
      if (!metrics) continue;

      const updatedRecord: ExperimentRecord = { ...record, metrics };
      fs.writeFileSync(filePath, JSON.stringify(updatedRecord, null, 2), "utf-8");
      updated++;
    } catch (error) {
      console.warn(`⚠️ Skipping record ${f}: ${error instanceof Error ? error.message : error}`);
    }
  }

  return updated;
};
