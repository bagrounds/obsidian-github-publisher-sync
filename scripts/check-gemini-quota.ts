#!/usr/bin/env npx tsx

/**
 * Check Gemini API model availability and quota metadata.
 *
 * Usage:
 *   GEMINI_API_KEY=… npx tsx scripts/check-gemini-quota.ts --label "before blog generation"
 *
 * Flags:
 *   --label <text>   Contextual label for the report (default: "snapshot")
 *   --json           Output raw JSON instead of formatted text
 */

import {
  fetchModels,
  buildQuotaReport,
  formatQuotaReport,
} from "./lib/gemini-quota.ts";

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

interface CliArgs {
  readonly label: string;
  readonly json: boolean;
}

const parseArgs = (argv: readonly string[]): CliArgs => {
  const args = argv.slice(2);

  const flagValue = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    return idx >= 0 && idx + 1 < args.length ? (args[idx + 1] as string) : undefined;
  };

  return {
    label: flagValue("--label") ?? "snapshot",
    json: args.includes("--json"),
  };
};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const main = async (): Promise<void> => {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error("❌ GEMINI_API_KEY environment variable is required");
    process.exit(1);
  }

  const { label, json } = parseArgs(process.argv);

  const models = await fetchModels(apiKey);
  const report = buildQuotaReport(models, label);

  if (json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log(formatQuotaReport(report));
  }
};

main().catch((error) => {
  console.error("❌ Failed to check Gemini quota:", error);
  process.exit(1);
});
