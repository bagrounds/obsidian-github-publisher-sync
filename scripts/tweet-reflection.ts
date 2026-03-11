/**
 * Social Post Reflection Automation Script
 *
 * This module re-exports the full public API from the decomposed lib/ modules.
 * All functionality has been refactored into focused, single-responsibility modules
 * under scripts/lib/, but this file maintains backward compatibility for existing
 * imports and the CLI entry point.
 *
 * @module tweet-reflection
 * @see scripts/lib/ for the decomposed implementation
 */

// --- Re-exports: Types ---
export type {
  ReflectionData,
  TweetResult,
  BlueskyPostResult,
  MastodonPostResult,
  EmbedResult,
  EmbedSection,
  OgMetadata,
  TwitterCredentials,
  BlueskyCredentials,
  MastodonCredentials,
  GeminiConfig,
  ObsidianCredentials,
  EnvironmentConfig,
  LinkCard,
} from "./lib/types.ts";

// --- Re-exports: Constants ---
export {
  TWITTER_HANDLE,
  TWITTER_DISPLAY_NAME,
  BLUESKY_DISPLAY_NAME,
  MASTODON_DISPLAY_NAME,
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  MASTODON_SECTION_HEADER,
  TWITTER_URL_LENGTH,
  TWITTER_MAX_LENGTH,
  BLUESKY_MAX_LENGTH,
  MASTODON_MAX_LENGTH,
  DEFAULT_GEMINI_MODEL,
  BLUESKY_OEMBED_INITIAL_DELAY_MS,
  BLUESKY_OEMBED_RETRY_DELAY_MS,
} from "./lib/types.ts";

// --- Re-exports: Timer ---
export { PipelineTimer } from "./lib/timer.ts";

// --- Re-exports: Text Processing ---
export {
  countGraphemes,
  truncateToGraphemeLimit,
  calculateTweetLength,
  validateTweetLength,
  fitPostToLimit,
} from "./lib/text.ts";

// --- Re-exports: HTML ---
export { escapeHtml, textToHtml, formatDisplayDate, MONTH_NAMES } from "./lib/html.ts";

// --- Re-exports: Retry ---
export { withRetry, TRANSIENT_HTTP_CODES } from "./lib/retry.ts";

// --- Re-exports: Frontmatter & Note I/O ---
export {
  parseFrontmatter,
  getReflectionPath,
  readReflection,
  readNote,
} from "./lib/frontmatter.ts";

// --- Re-exports: Embed Sections ---
export {
  createSectionBuilder,
  createSectionAppender,
  buildTweetSection,
  buildBlueskySection,
  buildMastodonSection,
  appendTweetSection,
  appendBlueskySection,
  appendMastodonSection,
} from "./lib/embed-section.ts";

// --- Re-exports: Gemini ---
export { buildGeminiPrompt, generateTweetWithGemini } from "./lib/gemini.ts";
export type { GenerateResult } from "./lib/gemini.ts";

// --- Re-exports: A/B Testing Experiment ---
export type { VariantId, VariantWeight, ExperimentAssignment, EngagementMetrics, ExperimentObservation } from "./lib/experiment.ts";
export {
  VARIANT_IDS,
  DEFAULT_WEIGHTS,
  selectVariant,
  randomVariant,
  createAssignment,
  getVariantOverride,
  resolveVariant,
  formatAssignment,
  validateWeights,
  isVariantId,
} from "./lib/experiment.ts";

// --- Re-exports: Versioned Prompts ---
export type { PromptPair, PromptBuilder } from "./lib/prompts.ts";
export { PROMPT_VARIANTS, getPromptBuilder, buildPromptForVariant } from "./lib/prompts.ts";

// --- Re-exports: Analytics ---
export {
  fetchMastodonMetrics,
  fetchBlueskyMetrics,
  totalEngagement,
  engagementRate,
  mean,
  variance,
  standardDeviation,
  welchTTest,
  approximatePValue,
  analyzeExperiment,
  formatExperimentSummary,
} from "./lib/analytics.ts";
export type { ExperimentSummary } from "./lib/analytics.ts";

// --- Re-exports: Environment ---
export { isPlatformDisabled, validateEnvironment, getYesterdayDate } from "./lib/env.ts";

// --- Re-exports: Obsidian Sync ---
export {
  runObCommand,
  syncObsidianVault,
  pushObsidianVault,
  runObSyncWithRetry,
  removeSyncLock,
  killObProcesses,
  ensureSyncClean,
  logSyncDiagnostics,
  appendEmbedsToObsidianNote,
} from "./lib/obsidian-sync.ts";

// --- Re-exports: Platform — Twitter ---
export {
  postTweet,
  deleteTweet,
  fetchOEmbed,
  generateLocalEmbed,
  getEmbedHtml,
} from "./lib/platforms/twitter.ts";

// --- Re-exports: Platform — Bluesky ---
export {
  postToBluesky,
  deleteBlueskyPost,
  extractBlueskyPostId,
  extractBlueskyDid,
  buildBlueskyPostUrl,
  fetchBlueskyOEmbed,
  generateLocalBlueskyEmbed,
  getBlueskyEmbedHtml,
} from "./lib/platforms/bluesky.ts";

// --- Re-exports: Platform — Mastodon ---
export {
  postToMastodon,
  deleteMastodonPost,
  extractMastodonInstanceUrl,
  extractMastodonStatusId,
  extractMastodonUsername,
  fetchMastodonOEmbed,
  generateLocalMastodonEmbed,
  getMastodonEmbedHtml,
} from "./lib/platforms/mastodon.ts";

// --- Re-exports: Platform — OG Metadata ---
export { fetchOgMetadata, fetchImageAsBuffer } from "./lib/platforms/og-metadata.ts";

// --- Re-exports: Pipeline ---
export { main } from "./lib/pipeline.ts";
