/**
 * Scheduler — pure scheduling logic for consolidated cron jobs.
 *
 * Given a UTC hour, determines which tasks should run. This module is
 * side-effect free and fully testable.
 *
 * @module scheduler
 */

export type TaskId =
  | "blog-series:chickie-loo"
  | "blog-series:auto-blog-zero"
  | "blog-series:systems-for-public-good"
  | "backfill-blog-images"
  | "internal-linking"
  | "social-posting";

export interface ScheduleEntry {
  readonly taskId: TaskId;
  readonly hoursUtc: readonly number[];
}

export interface BlogSeriesRunConfig {
  readonly seriesId: string;
  readonly defaultModel: string;
  readonly priorityUserEnvVar: string;
}

/**
 * Schedule definition — the single source of truth for when tasks run.
 *
 * Original cron schedules:
 *   chickie-loo:             0 15 * * *   (15:00 UTC daily)
 *   auto-blog-zero:          0 16 * * *   (16:00 UTC daily)
 *   systems-for-public-good: 0 17 * * *   (17:00 UTC daily)
 *   backfill-blog-images:    0 6  * * *   (06:00 UTC daily)
 *   internal-linking:        30 7 * * *   (07:30 UTC daily → rounded to 08:00)
 *   social-posting:          0 * /2 * * * (every 2 hours on even hours)
 */
export const SCHEDULE: readonly ScheduleEntry[] = [
  { taskId: "blog-series:chickie-loo", hoursUtc: [15] },
  { taskId: "blog-series:auto-blog-zero", hoursUtc: [16] },
  { taskId: "blog-series:systems-for-public-good", hoursUtc: [17] },
  { taskId: "backfill-blog-images", hoursUtc: [6] },
  { taskId: "internal-linking", hoursUtc: [8] },
  { taskId: "social-posting", hoursUtc: [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22] },
];

/**
 * Blog series runtime configuration — per-series defaults that mirror
 * the original per-workflow environment variable setup.
 */
export const BLOG_SERIES_RUN_CONFIGS: ReadonlyMap<string, BlogSeriesRunConfig> = new Map([
  [
    "chickie-loo",
    {
      seriesId: "chickie-loo",
      defaultModel: "gemini-3.1-flash-lite-preview",
      priorityUserEnvVar: "CHICKIE_LOO_PRIORITY_USER",
    },
  ],
  [
    "auto-blog-zero",
    {
      seriesId: "auto-blog-zero",
      defaultModel: "gemini-3.1-flash-lite-preview",
      priorityUserEnvVar: "AUTO_BLOG_ZERO_PRIORITY_USER",
    },
  ],
  [
    "systems-for-public-good",
    {
      seriesId: "systems-for-public-good",
      defaultModel: "gemini-2.5-flash",
      priorityUserEnvVar: "SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER",
    },
  ],
]);

export const VALID_TASK_IDS: ReadonlySet<TaskId> = new Set(
  SCHEDULE.map((e) => e.taskId),
);

export const getScheduledTasks = (hourUtc: number): readonly TaskId[] =>
  SCHEDULE.filter((entry) => entry.hoursUtc.includes(hourUtc)).map(
    (entry) => entry.taskId,
  );

export const isValidTaskId = (id: string): id is TaskId =>
  VALID_TASK_IDS.has(id as TaskId);

export const extractSeriesId = (taskId: TaskId): string | undefined =>
  taskId.startsWith("blog-series:") ? taskId.slice("blog-series:".length) : undefined;
