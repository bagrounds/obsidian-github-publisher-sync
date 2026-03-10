/**
 * Environment validation and configuration.
 *
 * Reads environment variables and constructs a typed configuration
 * object. Each platform is optional — present only when all required
 * credentials are configured and the platform is not disabled.
 *
 * @module env
 */

import type { EnvironmentConfig } from "./types.ts";
import { DEFAULT_GEMINI_MODEL } from "./types.ts";

/**
 * Check if a platform is explicitly disabled via an environment variable.
 * Accepted truthy values: "true", "1", "yes" (case-insensitive).
 */
export const isPlatformDisabled = (envVar: string): boolean => {
  const value = process.env[envVar]?.toLowerCase()?.trim();
  return value === "true" || value === "1" || value === "yes";
};

/**
 * Get yesterday's date in YYYY-MM-DD format (UTC).
 */
export const getYesterdayDate = (): string => {
  const now = new Date();
  now.setUTCDate(now.getUTCDate() - 1);
  return now.toISOString().split("T")[0] as string;
};

const allPresent = (keys: readonly string[]): boolean =>
  keys.every((key) => process.env[key]);

const logDisabled = (platform: string, envVar: string): void => {
  if (isPlatformDisabled(envVar)) {
    console.log(`🚫 ${platform} disabled via ${envVar} env var`);
  }
};

/**
 * Validate that all required environment variables are set.
 * Returns a typed configuration with platform credentials (null if unconfigured).
 */
export function validateEnvironment(): EnvironmentConfig {
  const required = ["GEMINI_API_KEY", "OBSIDIAN_AUTH_TOKEN", "OBSIDIAN_VAULT_NAME"];

  const missing = required.filter((key) => !process.env[key]);
  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(", ")}`);
  }

  // Twitter: all 4 credentials required, can be disabled
  const twitterKeys = [
    "TWITTER_API_KEY", "TWITTER_API_SECRET",
    "TWITTER_ACCESS_TOKEN", "TWITTER_ACCESS_SECRET",
  ] as const;
  const twitterDisabled = isPlatformDisabled("DISABLE_TWITTER");
  logDisabled("Twitter", "DISABLE_TWITTER");
  const twitter = !twitterDisabled && allPresent(twitterKeys)
    ? {
        apiKey: process.env.TWITTER_API_KEY as string,
        apiSecret: process.env.TWITTER_API_SECRET as string,
        accessToken: process.env.TWITTER_ACCESS_TOKEN as string,
        accessSecret: process.env.TWITTER_ACCESS_SECRET as string,
      }
    : null;

  // Bluesky: both credentials required, can be disabled
  const blueskyDisabled = isPlatformDisabled("DISABLE_BLUESKY");
  logDisabled("Bluesky", "DISABLE_BLUESKY");
  const bluesky = !blueskyDisabled && allPresent(["BLUESKY_IDENTIFIER", "BLUESKY_APP_PASSWORD"])
    ? {
        identifier: process.env.BLUESKY_IDENTIFIER as string,
        password: process.env.BLUESKY_APP_PASSWORD as string,
      }
    : null;

  // Mastodon: both credentials required, can be disabled
  const mastodonDisabled = isPlatformDisabled("DISABLE_MASTODON");
  logDisabled("Mastodon", "DISABLE_MASTODON");
  const mastodon = !mastodonDisabled && allPresent(["MASTODON_INSTANCE_URL", "MASTODON_ACCESS_TOKEN"])
    ? {
        instanceUrl: process.env.MASTODON_INSTANCE_URL as string,
        accessToken: process.env.MASTODON_ACCESS_TOKEN as string,
      }
    : null;

  return {
    twitter,
    bluesky,
    mastodon,
    gemini: {
      apiKey: process.env.GEMINI_API_KEY as string,
      model: process.env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL,
    },
    obsidian: {
      authToken: process.env.OBSIDIAN_AUTH_TOKEN as string,
      vaultName: process.env.OBSIDIAN_VAULT_NAME as string,
      vaultPassword: process.env.OBSIDIAN_VAULT_PASSWORD || undefined,
    },
  };
}
