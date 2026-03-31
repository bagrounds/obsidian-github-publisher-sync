#!/usr/bin/env npx tsx

/**
 * Broken Link Audit CLI
 *
 * Samples pages from the live site and checks for broken internal links.
 * Always exits 0 — results are informational only, never blocking.
 *
 * Usage:
 *   npx tsx scripts/broken-link-audit.ts
 *   npx tsx scripts/broken-link-audit.ts --sample-size 50
 *   npx tsx scripts/broken-link-audit.ts --site-url https://bagrounds.org
 *
 * @module broken-link-audit
 */

import {
  runAudit,
  DEFAULT_SITE_URL,
  DEFAULT_SAMPLE_SIZE,
  DEFAULT_REQUEST_TIMEOUT_MS,
} from "./lib/broken-link-audit.ts";

const parseArgs = (
  args: readonly string[],
): { siteUrl: string; sampleSize: number } => {
  const siteUrl =
    args.find((_, i) => args[i - 1] === "--site-url") ?? DEFAULT_SITE_URL;
  const sampleSizeArg = args.find((_, i) => args[i - 1] === "--sample-size");
  const sampleSize = sampleSizeArg
    ? parseInt(sampleSizeArg, 10)
    : DEFAULT_SAMPLE_SIZE;

  return { siteUrl, sampleSize };
};

const main = async (): Promise<void> => {
  const { siteUrl, sampleSize } = parseArgs(process.argv.slice(2));

  await runAudit({
    siteUrl,
    sampleSize,
    requestTimeoutMs: DEFAULT_REQUEST_TIMEOUT_MS,
  });
};

main().catch((error) => {
  console.error("Broken link audit error:", error);
  // Always exit 0 — audit is informational, never blocking
  process.exit(0);
});
