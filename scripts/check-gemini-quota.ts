#!/usr/bin/env npx tsx

/**
 * Check Gemini API model availability, quota limits, and real-time usage.
 *
 * Usage:
 *   GEMINI_API_KEY=… npx tsx scripts/check-gemini-quota.ts --label "before blog generation"
 *
 * With GCP service account for full quota + usage data:
 *   GEMINI_API_KEY=… GCP_SERVICE_ACCOUNT_KEY='{"project_id":…}' \
 *     npx tsx scripts/check-gemini-quota.ts --label "before blog generation"
 *
 * Flags:
 *   --label <text>   Contextual label for the report (default: "snapshot")
 *   --json           Output raw JSON instead of formatted text
 *
 * Environment:
 *   GEMINI_API_KEY           Required. Gemini API key for model catalog.
 *   GCP_SERVICE_ACCOUNT_KEY  Optional. JSON service account key for quota limits + usage.
 *   GCP_PROJECT_ID           Optional. Override project ID from service account key.
 */

import {
  fetchFullQuotaReport,
  formatQuotaReport,
} from "./lib/gemini-quota.ts";
import {
  parseServiceAccountKey,
  getAccessToken,
} from "./lib/gcp-auth.ts";

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

  let accessToken: string | undefined;
  let projectId: string | undefined;

  const serviceAccountRaw = process.env.GCP_SERVICE_ACCOUNT_KEY;
  if (serviceAccountRaw) {
    try {
      const sa = parseServiceAccountKey(serviceAccountRaw);
      projectId = process.env.GCP_PROJECT_ID ?? sa.project_id;
      accessToken = await getAccessToken(sa);
      console.log(`🔑 GCP authenticated as ${sa.client_email} (project: ${projectId})`);
    } catch (err) {
      console.warn(`⚠️ GCP authentication failed, falling back to model catalog only: ${err instanceof Error ? err.message : err}`);
    }
  } else {
    console.log("ℹ️  No GCP_SERVICE_ACCOUNT_KEY set — showing model catalog only (no quota limits or usage data)");
    console.log("   To enable full quota reporting, add GCP_SERVICE_ACCOUNT_KEY secret.");
  }

  const report = await fetchFullQuotaReport({
    apiKey,
    label,
    accessToken,
    projectId,
  });

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
