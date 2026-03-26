/**
 * Scheduler — pure scheduling logic for consolidated cron jobs.
 *
 * Given a UTC hour, determines which tasks should run. This module is
 * side-effect free and fully testable.
 *
 * Blog series tasks use "at or after" scheduling: they become eligible
 * at their scheduled hour and remain eligible for the rest of the day.
 * The orchestrator checks whether today's post already exists before
 * running, making the system resilient to partial failures.
 *
 * @module scheduler
 */

import fs from "node:fs";
import path from "node:path";

export type TaskId =
  | "blog-series:chickie-loo"
  | "blog-series:auto-blog-zero"
  | "blog-series:systems-for-public-good"
  | "backfill-blog-images"
  | "internal-linking"
  | "social-posting"
  | "reflection-title";

export interface ScheduleEntry {
  readonly taskId: TaskId;
  /**
   * Hours declared in **Pacific time** (0–23). The scheduler converts
   * to/from UTC internally using `nowPacificHour()`.
   */
  readonly hoursPacific: readonly number[];
  /** When true, the task becomes eligible at the earliest specified hour and remains eligible for all subsequent hours of the day (in Pacific time). */
  readonly atOrAfter?: boolean;
}

export interface BlogSeriesRunConfig {
  readonly seriesId: string;
  readonly modelChain: readonly string[];
  readonly priorityUserEnvVar: string;
}

/**
 * Schedule definition — the single source of truth for when tasks run.
 *
 * All times are declared in **Pacific time**. The scheduler converts
 * to/from UTC internally using nowPacificHour().
 *
 * Blog series entries use "at or after" semantics: they become eligible
 * starting at their scheduled Pacific hour and remain eligible until
 * 11:59 PM Pacific. The orchestrator's idempotency check (today's post
 * exists?) prevents duplicate generation.
 *
 * The reflection-title task also uses "at or after" scheduling (via the
 * atOrAfter flag) at 10 PM Pacific. It generates a creative title for
 * the current day's reflection note once all content is in.
 *
 * Other tasks use exact-hour matching.
 *
 * Original schedules (Pacific time):
 *   chickie-loo:             7 AM PT daily
 *   auto-blog-zero:          8 AM PT daily
 *   systems-for-public-good: 9 AM PT daily
 *   reflection-title:       10 PM PT daily
 *   backfill-blog-images:    every hour (1 image per run)
 *   internal-linking:        every hour (1 note per run)
 *   social-posting:          every 2 hours on even hours
 */
const EVERY_HOUR: readonly number[] = Array.from({ length: 24 }, (_, i) => i);

export const SCHEDULE: readonly ScheduleEntry[] = [
  { taskId: "blog-series:chickie-loo", hoursPacific: [7] },
  { taskId: "blog-series:auto-blog-zero", hoursPacific: [8] },
  { taskId: "blog-series:systems-for-public-good", hoursPacific: [9] },
  { taskId: "reflection-title", hoursPacific: [22], atOrAfter: true },
  { taskId: "backfill-blog-images", hoursPacific: EVERY_HOUR },
  { taskId: "internal-linking", hoursPacific: EVERY_HOUR },
  { taskId: "social-posting", hoursPacific: [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22] },
];

/**
 * Blog series runtime configuration — per-series model fallback chains
 * and environment variable mappings.
 *
 * The modelChain is an ordered list of Gemini models to try. The first
 * model is the default; subsequent models are tried on failure.
 *
 * systems-for-public-good leads with gemini-2.5-flash because it
 * supports Google Search grounding on the free tier.
 */
export const BLOG_SERIES_RUN_CONFIGS: ReadonlyMap<string, BlogSeriesRunConfig> = new Map([
  [
    "chickie-loo",
    {
      seriesId: "chickie-loo",
      modelChain: ["gemini-3.1-flash-lite-preview", "gemini-2.5-flash", "gemini-2.5-flash-lite"],
      priorityUserEnvVar: "CHICKIE_LOO_PRIORITY_USER",
    },
  ],
  [
    "auto-blog-zero",
    {
      seriesId: "auto-blog-zero",
      modelChain: ["gemini-3.1-flash-lite-preview", "gemini-2.5-flash", "gemini-2.5-flash-lite"],
      priorityUserEnvVar: "AUTO_BLOG_ZERO_PRIORITY_USER",
    },
  ],
  [
    "systems-for-public-good",
    {
      seriesId: "systems-for-public-good",
      modelChain: ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3.1-flash-lite-preview"],
      priorityUserEnvVar: "SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER",
    },
  ],
]);

export const VALID_TASK_IDS: ReadonlySet<TaskId> = new Set(
  SCHEDULE.map((e) => e.taskId),
);

/**
 * Returns the current hour (0–23) in Pacific time.
 */
export const nowPacificHour = (now: Date = new Date()): number =>
  parseInt(
    new Intl.DateTimeFormat("en-US", {
      hour: "numeric",
      hour12: false,
      timeZone: "America/Los_Angeles",
    }).format(now),
    10,
  );

/**
 * Returns tasks eligible to run at the given **Pacific** hour.
 *
 * Blog series tasks and entries with atOrAfter=true use "at or after"
 * scheduling: they're eligible at their scheduled Pacific hour AND all
 * subsequent hours until 11:59 PM Pacific. The orchestrator's idempotency
 * check prevents duplicate execution.
 *
 * Other tasks use exact-hour matching.
 */
export const getScheduledTasks = (hourPacific: number): readonly TaskId[] =>
  SCHEDULE.filter((entry) =>
    entry.atOrAfter || entry.taskId.startsWith("blog-series:")
      ? entry.hoursPacific.some((h) => hourPacific >= h)
      : entry.hoursPacific.includes(hourPacific),
  ).map((entry) => entry.taskId);

export const isValidTaskId = (id: string): id is TaskId =>
  VALID_TASK_IDS.has(id as TaskId);

export const extractSeriesId = (taskId: TaskId): string | undefined =>
  taskId.startsWith("blog-series:") ? taskId.slice("blog-series:".length) : undefined;

/**
 * Checks whether a blog post already exists for today in a series directory.
 * Used by the orchestrator for idempotent "at or after" scheduling.
 */
export const blogPostExistsForToday = (
  seriesDir: string,
  today: string,
): boolean =>
  fs.existsSync(seriesDir) &&
  fs.readdirSync(seriesDir).some((f) => f.startsWith(today));
