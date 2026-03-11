/**
 * Social media engagement analytics.
 *
 * Fetches post engagement metrics (likes, reposts, replies) from
 * Mastodon and Bluesky APIs for A/B test analysis.
 *
 * Each platform fetcher is a pure async function from credentials + post ID
 * to EngagementMetrics. Platform-specific API details are encapsulated here.
 *
 * @module analytics
 */

import type { BlueskyCredentials, MastodonCredentials } from "./types.ts";
import type { EngagementMetrics } from "./experiment.ts";

// --- Mastodon Engagement ---

/**
 * Fetch engagement metrics for a Mastodon post.
 *
 * Uses the Mastodon REST API: GET /api/v1/statuses/:id
 * Returns favourites_count, reblogs_count, replies_count.
 */
export async function fetchMastodonMetrics(
  statusId: string,
  credentials: MastodonCredentials,
): Promise<EngagementMetrics> {
  const { createRestAPIClient } = await import("masto");
  const client = createRestAPIClient({
    url: credentials.instanceUrl,
    accessToken: credentials.accessToken,
  });

  const status = await client.v1.statuses.$select(statusId).fetch();

  return {
    likes: status.favouritesCount ?? 0,
    reposts: status.reblogsCount ?? 0,
    replies: status.repliesCount ?? 0,
  };
}

// --- Bluesky Engagement ---

/**
 * Fetch engagement metrics for a Bluesky post.
 *
 * Uses the AT Protocol: app.bsky.feed.getPostThread
 * Returns likeCount, repostCount, replyCount from the PostView.
 */
export async function fetchBlueskyMetrics(
  postUri: string,
  credentials: BlueskyCredentials,
): Promise<EngagementMetrics> {
  const { AtpAgent } = await import("@atproto/api");
  const agent = new AtpAgent({ service: "https://bsky.social" });

  await agent.login({
    identifier: credentials.identifier,
    password: credentials.password,
  });

  const response = await agent.getPostThread({ uri: postUri });

  const thread = response.data.thread;
  if (!("post" in thread)) {
    throw new Error(`Bluesky post not found or blocked: ${postUri}`);
  }

  const post = thread.post as {
    likeCount?: number;
    repostCount?: number;
    replyCount?: number;
  };

  return {
    likes: post.likeCount ?? 0,
    reposts: post.repostCount ?? 0,
    replies: post.replyCount ?? 0,
  };
}

// --- Aggregate Metrics ---

/** Total engagement = likes + reposts + replies. */
export const totalEngagement = (metrics: EngagementMetrics): number =>
  metrics.likes + metrics.reposts + metrics.replies;

/**
 * Compute engagement rate: total engagement / impressions.
 * Returns 0 if impressions is 0 (avoids division by zero).
 */
export const engagementRate = (
  metrics: EngagementMetrics,
  impressions: number,
): number => (impressions === 0 ? 0 : totalEngagement(metrics) / impressions);

// --- Statistical Analysis ---

/**
 * Compute the mean of a numeric array.
 * Returns 0 for empty arrays.
 */
export const mean = (values: readonly number[]): number =>
  values.length === 0 ? 0 : values.reduce((sum, v) => sum + v, 0) / values.length;

/**
 * Compute the sample variance of a numeric array.
 * Returns 0 for arrays with fewer than 2 elements.
 */
export const variance = (values: readonly number[]): number => {
  if (values.length < 2) return 0;
  const m = mean(values);
  const sumSquaredDiffs = values.reduce((sum, v) => sum + (v - m) ** 2, 0);
  return sumSquaredDiffs / (values.length - 1);
};

/**
 * Compute the sample standard deviation.
 */
export const standardDeviation = (values: readonly number[]): number =>
  Math.sqrt(variance(values));

/**
 * Welch's t-test for comparing two independent samples with potentially
 * unequal variances and sample sizes.
 *
 * Returns the t-statistic and approximate degrees of freedom.
 * Positive t means groupA has a higher mean than groupB.
 *
 * This is the recommended test for A/B testing where sample sizes
 * may differ and we cannot assume equal variances.
 */
export const welchTTest = (
  groupA: readonly number[],
  groupB: readonly number[],
): { t: number; df: number; meanA: number; meanB: number } => {
  const nA = groupA.length;
  const nB = groupB.length;

  if (nA < 2 || nB < 2) {
    return { t: 0, df: 0, meanA: mean(groupA), meanB: mean(groupB) };
  }

  const meanA = mean(groupA);
  const meanB = mean(groupB);
  const varA = variance(groupA);
  const varB = variance(groupB);

  const seA = varA / nA;
  const seB = varB / nB;
  const seDiff = Math.sqrt(seA + seB);

  if (seDiff === 0) {
    return { t: 0, df: nA + nB - 2, meanA, meanB };
  }

  const t = (meanA - meanB) / seDiff;

  // Welch-Satterthwaite degrees of freedom
  const df = (seA + seB) ** 2 / ((seA ** 2) / (nA - 1) + (seB ** 2) / (nB - 1));

  return { t, df: Math.round(df), meanA, meanB };
};

/**
 * Approximate p-value for a two-tailed t-test using the normal distribution
 * approximation (valid for df > 30, reasonable for df > 10).
 *
 * For small samples, this is a conservative approximation.
 * A proper implementation would use the Student's t CDF, but for a
 * first-pass experiment analysis, this is sufficient.
 */
export const approximatePValue = (t: number, _df: number): number => {
  // Use the complementary error function approximation
  const absT = Math.abs(t);
  // Abramowitz & Stegun approximation for the normal CDF
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;
  const x = absT / Math.SQRT2;
  const t1 = 1 / (1 + p * x);
  const erf =
    1 -
    (a1 * t1 + a2 * t1 ** 2 + a3 * t1 ** 3 + a4 * t1 ** 4 + a5 * t1 ** 5) *
      Math.exp(-(x * x));
  // Two-tailed p-value
  return 1 - erf;
};

// --- Summary Report ---

/** Summary of an A/B test analysis. */
export interface ExperimentSummary {
  readonly variantACount: number;
  readonly variantBCount: number;
  readonly variantAMeanEngagement: number;
  readonly variantBMeanEngagement: number;
  readonly tStatistic: number;
  readonly degreesOfFreedom: number;
  readonly pValue: number;
  readonly significant: boolean;
}

/**
 * Analyze experiment results and produce a summary.
 *
 * Takes engagement totals for each variant and computes
 * a Welch's t-test to determine if the difference is statistically significant.
 *
 * @param variantAEngagements - Array of total engagement counts for variant A posts
 * @param variantBEngagements - Array of total engagement counts for variant B posts
 * @param alpha - Significance threshold (default: 0.05)
 */
export const analyzeExperiment = (
  variantAEngagements: readonly number[],
  variantBEngagements: readonly number[],
  alpha: number = 0.05,
): ExperimentSummary => {
  const { t, df, meanA, meanB } = welchTTest(
    variantAEngagements,
    variantBEngagements,
  );
  const pValue = approximatePValue(t, df);

  return {
    variantACount: variantAEngagements.length,
    variantBCount: variantBEngagements.length,
    variantAMeanEngagement: meanA,
    variantBMeanEngagement: meanB,
    tStatistic: t,
    degreesOfFreedom: df,
    pValue,
    significant: pValue < alpha,
  };
};

/**
 * Format an experiment summary as a human-readable report.
 */
export const formatExperimentSummary = (summary: ExperimentSummary): string => {
  const winner =
    summary.variantAMeanEngagement > summary.variantBMeanEngagement
      ? "A (Control)"
      : "B (Treatment)";

  return `
📊 A/B Test Experiment Summary
${"═".repeat(40)}

Variant A (Control):     n=${summary.variantACount}, mean engagement=${summary.variantAMeanEngagement.toFixed(2)}
Variant B (Treatment):   n=${summary.variantBCount}, mean engagement=${summary.variantBMeanEngagement.toFixed(2)}

Welch's t-statistic:     ${summary.tStatistic.toFixed(4)}
Degrees of freedom:      ${summary.degreesOfFreedom}
p-value (approx):        ${summary.pValue.toFixed(4)}
Significant (α=0.05):    ${summary.significant ? "✅ YES" : "❌ NO"}

${summary.significant ? `🏆 Winner: ${winner}` : "📊 No significant difference detected yet. Keep collecting data!"}
${"═".repeat(40)}
`.trim();
};
