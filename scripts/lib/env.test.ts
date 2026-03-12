/**
 * Tests for scripts/lib/env.ts — Environment validation.
 */

import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";

import { isPlatformDisabled, validateEnvironment, getYesterdayDate } from "../lib/env.ts";

describe("isPlatformDisabled", () => {
  const envKey = "TEST_DISABLE_PLATFORM";

  afterEach(() => {
    delete process.env[envKey];
  });

  it("returns true for 'true'", () => {
    process.env[envKey] = "true";
    assert.equal(isPlatformDisabled(envKey), true);
  });

  it("returns true for '1'", () => {
    process.env[envKey] = "1";
    assert.equal(isPlatformDisabled(envKey), true);
  });

  it("returns true for 'yes' (case-insensitive)", () => {
    process.env[envKey] = "YES";
    assert.equal(isPlatformDisabled(envKey), true);
  });

  it("returns false for 'false'", () => {
    process.env[envKey] = "false";
    assert.equal(isPlatformDisabled(envKey), false);
  });

  it("returns false for unset variable", () => {
    delete process.env[envKey];
    assert.equal(isPlatformDisabled(envKey), false);
  });

  it("returns false for empty string", () => {
    process.env[envKey] = "";
    assert.equal(isPlatformDisabled(envKey), false);
  });
});

describe("getYesterdayDate", () => {
  it("returns a YYYY-MM-DD string", () => {
    const result = getYesterdayDate();
    assert.match(result, /^\d{4}-\d{2}-\d{2}$/);
  });

  it("returns a date before today", () => {
    const yesterday = getYesterdayDate();
    const today = new Date().toISOString().split("T")[0] as string;
    assert.ok(yesterday < today);
  });
});

describe("validateEnvironment", () => {
  const savedEnv: Record<string, string | undefined> = {};
  const requiredKeys = ["GEMINI_API_KEY", "OBSIDIAN_AUTH_TOKEN", "OBSIDIAN_VAULT_NAME"];

  beforeEach(() => {
    for (const key of requiredKeys) {
      savedEnv[key] = process.env[key];
      process.env[key] = `test-${key}`;
    }
    // Clear platform credentials
    for (const key of [
      "TWITTER_API_KEY", "TWITTER_API_SECRET", "TWITTER_ACCESS_TOKEN", "TWITTER_ACCESS_SECRET",
      "BLUESKY_IDENTIFIER", "BLUESKY_APP_PASSWORD",
      "MASTODON_INSTANCE_URL", "MASTODON_ACCESS_TOKEN",
      "DISABLE_TWITTER", "DISABLE_BLUESKY", "DISABLE_MASTODON",
      "GEMINI_MODEL", "GEMINI_QUESTION_MODEL",
    ]) {
      savedEnv[key] = process.env[key];
      delete process.env[key];
    }
  });

  afterEach(() => {
    for (const [key, value] of Object.entries(savedEnv)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  });

  it("throws when required keys are missing", () => {
    delete process.env.GEMINI_API_KEY;
    assert.throws(() => validateEnvironment(), /Missing required environment variables/);
  });

  it("returns null for unconfigured platforms", () => {
    const env = validateEnvironment();
    assert.equal(env.twitter, null);
    assert.equal(env.bluesky, null);
    assert.equal(env.mastodon, null);
  });

  it("returns gemini config with default model", () => {
    const env = validateEnvironment();
    assert.equal(env.gemini.apiKey, "test-GEMINI_API_KEY");
    assert.equal(env.gemini.model, "gemma-3-27b-it");
  });

  it("returns gemini config with default question model", () => {
    const env = validateEnvironment();
    assert.equal(env.gemini.questionModel, "gemini-3.1-flash-lite-preview");
  });

  it("uses custom question model when GEMINI_QUESTION_MODEL is set", () => {
    process.env.GEMINI_QUESTION_MODEL = "gemini-custom-model";
    const env = validateEnvironment();
    assert.equal(env.gemini.questionModel, "gemini-custom-model");
  });

  it("returns Twitter credentials when all 4 are set", () => {
    process.env.TWITTER_API_KEY = "key";
    process.env.TWITTER_API_SECRET = "secret";
    process.env.TWITTER_ACCESS_TOKEN = "token";
    process.env.TWITTER_ACCESS_SECRET = "secret2";
    const env = validateEnvironment();
    assert.ok(env.twitter);
    assert.equal(env.twitter.apiKey, "key");
  });

  it("returns null for Twitter when disabled", () => {
    process.env.TWITTER_API_KEY = "key";
    process.env.TWITTER_API_SECRET = "secret";
    process.env.TWITTER_ACCESS_TOKEN = "token";
    process.env.TWITTER_ACCESS_SECRET = "secret2";
    process.env.DISABLE_TWITTER = "true";
    const env = validateEnvironment();
    assert.equal(env.twitter, null);
  });

  it("returns Bluesky credentials when both are set", () => {
    process.env.BLUESKY_IDENTIFIER = "user.bsky.social";
    process.env.BLUESKY_APP_PASSWORD = "pass";
    const env = validateEnvironment();
    assert.ok(env.bluesky);
    assert.equal(env.bluesky.identifier, "user.bsky.social");
  });

  it("returns Mastodon credentials when both are set", () => {
    process.env.MASTODON_INSTANCE_URL = "https://mastodon.social";
    process.env.MASTODON_ACCESS_TOKEN = "token";
    const env = validateEnvironment();
    assert.ok(env.mastodon);
    assert.equal(env.mastodon.instanceUrl, "https://mastodon.social");
  });
});
