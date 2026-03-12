/**
 * Shared types for the social media auto-posting pipeline.
 *
 * All domain types are defined here as a single source of truth,
 * following DDD principles of explicit, well-named value objects.
 *
 * @module types
 */

// --- Social Platform Types ---

export interface ReflectionData {
  readonly date: string;
  readonly title: string;
  readonly url: string;
  readonly body: string;
  readonly filePath: string;
  readonly hasTweetSection: boolean;
  readonly hasBlueskySection: boolean;
  readonly hasMastodonSection: boolean;
}

export interface TweetResult {
  readonly id: string;
  readonly text: string;
}

export interface BlueskyPostResult {
  readonly uri: string;
  readonly cid: string;
  readonly text: string;
}

export interface MastodonPostResult {
  readonly id: string;
  readonly url: string;
  readonly text: string;
}

export interface EmbedResult {
  readonly html: string;
}

export interface EmbedSection {
  readonly header: string;
  readonly embedHtml: string;
  readonly buildSection: (content: string, html: string) => string;
}

export interface OgMetadata {
  readonly title?: string;
  readonly description?: string;
  readonly imageUrl?: string;
}

// --- Credential Types ---

export interface TwitterCredentials {
  readonly apiKey: string;
  readonly apiSecret: string;
  readonly accessToken: string;
  readonly accessSecret: string;
}

export interface BlueskyCredentials {
  readonly identifier: string;
  readonly password: string;
}

export interface MastodonCredentials {
  readonly instanceUrl: string;
  readonly accessToken: string;
}

export interface GeminiConfig {
  readonly apiKey: string;
  readonly model: string;
  /** Model for generating discussion questions (variant B). Falls back to `model` if not set. */
  readonly questionModel: string;
}

export interface ObsidianCredentials {
  readonly authToken: string;
  readonly vaultName: string;
  readonly vaultPassword?: string;
}

export interface EnvironmentConfig {
  readonly twitter: TwitterCredentials | null;
  readonly bluesky: BlueskyCredentials | null;
  readonly mastodon: MastodonCredentials | null;
  readonly gemini: GeminiConfig;
  readonly obsidian: ObsidianCredentials;
}

// --- Link Card for Bluesky ---

export interface LinkCard {
  readonly uri: string;
  readonly title: string;
  readonly description: string;
  readonly thumbUrl?: string;
}

// --- Constants ---

export const TWITTER_HANDLE = "bagrounds";
export const TWITTER_DISPLAY_NAME = "Bryan Grounds";
export const BLUESKY_DISPLAY_NAME = "Bryan Grounds";
export const MASTODON_DISPLAY_NAME = "Bryan Grounds";

export const TWEET_SECTION_HEADER = "## 🐦 Tweet";
export const BLUESKY_SECTION_HEADER = "## 🦋 Bluesky";
export const MASTODON_SECTION_HEADER = "## 🐘 Mastodon";

export const TWITTER_URL_LENGTH = 23;
export const TWITTER_MAX_LENGTH = 280;
export const BLUESKY_MAX_LENGTH = 300;
export const MASTODON_MAX_LENGTH = 500;

export const DEFAULT_GEMINI_MODEL = "gemma-3-27b-it";
export const DEFAULT_QUESTION_MODEL = "gemini-3.1-flash-lite-preview";

export const BLUESKY_OEMBED_INITIAL_DELAY_MS = 0;
export const BLUESKY_OEMBED_RETRY_DELAY_MS = 2_000;
