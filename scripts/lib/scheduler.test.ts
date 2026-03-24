import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  getScheduledTasks,
  SCHEDULE,
  VALID_TASK_IDS,
  BLOG_SERIES_RUN_CONFIGS,
  isValidTaskId,
  extractSeriesId,
  type TaskId,
} from "./scheduler.ts";

// ---------------------------------------------------------------------------
// getScheduledTasks
// ---------------------------------------------------------------------------

describe("getScheduledTasks", () => {
  it("returns chickie-loo at hour 15", () => {
    const tasks = getScheduledTasks(15);
    assert.ok(tasks.includes("blog-series:chickie-loo"));
  });

  it("returns auto-blog-zero and social-posting at hour 16", () => {
    const tasks = getScheduledTasks(16);
    assert.ok(tasks.includes("blog-series:auto-blog-zero"));
    assert.ok(tasks.includes("social-posting"));
  });

  it("returns systems-for-public-good at hour 17", () => {
    const tasks = getScheduledTasks(17);
    assert.ok(tasks.includes("blog-series:systems-for-public-good"));
  });

  it("returns backfill-blog-images at hour 6", () => {
    const tasks = getScheduledTasks(6);
    assert.ok(tasks.includes("backfill-blog-images"));
  });

  it("returns internal-linking at hour 8", () => {
    const tasks = getScheduledTasks(8);
    assert.ok(tasks.includes("internal-linking"));
  });

  it("returns social-posting at all even hours", () => {
    [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22].forEach((hour) => {
      const tasks = getScheduledTasks(hour);
      assert.ok(
        tasks.includes("social-posting"),
        `social-posting missing at hour ${hour}`,
      );
    });
  });

  it("does not return social-posting at odd hours", () => {
    [1, 3, 5, 7, 9, 11, 13, 19, 21, 23].forEach((hour) => {
      const tasks = getScheduledTasks(hour);
      assert.ok(
        !tasks.includes("social-posting"),
        `social-posting should not run at hour ${hour}`,
      );
    });
  });

  it("returns empty array at hours with no scheduled tasks", () => {
    assert.deepStrictEqual(getScheduledTasks(1), []);
    assert.deepStrictEqual(getScheduledTasks(3), []);
    assert.deepStrictEqual(getScheduledTasks(23), []);
  });

  it("returns multiple tasks when schedules overlap", () => {
    const tasksAt6 = getScheduledTasks(6);
    assert.ok(tasksAt6.includes("backfill-blog-images"));
    assert.ok(tasksAt6.includes("social-posting"));
    assert.equal(tasksAt6.length, 2);

    const tasksAt8 = getScheduledTasks(8);
    assert.ok(tasksAt8.includes("internal-linking"));
    assert.ok(tasksAt8.includes("social-posting"));
    assert.equal(tasksAt8.length, 2);

    const tasksAt16 = getScheduledTasks(16);
    assert.ok(tasksAt16.includes("blog-series:auto-blog-zero"));
    assert.ok(tasksAt16.includes("social-posting"));
    assert.equal(tasksAt16.length, 2);
  });

  it("preserves order: blog tasks before infrastructure tasks before social", () => {
    const tasksAt16 = getScheduledTasks(16);
    const blogIdx = tasksAt16.indexOf("blog-series:auto-blog-zero");
    const socialIdx = tasksAt16.indexOf("social-posting");
    assert.ok(blogIdx < socialIdx, "blog tasks should come before social posting");
  });

  // Property: every hour returns only valid task IDs
  Array.from({ length: 24 }, (_, h) => h).forEach((hour) => {
    it(`returns only valid task IDs at hour ${hour}`, () => {
      const tasks = getScheduledTasks(hour);
      tasks.forEach((task) => {
        assert.ok(VALID_TASK_IDS.has(task), `Invalid task: ${task}`);
      });
    });
  });

  // Property: every scheduled task appears at least once across all hours
  it("every scheduled task runs at least once in a 24-hour cycle", () => {
    const allTasks = new Set(
      Array.from({ length: 24 }, (_, h) => getScheduledTasks(h)).flat(),
    );
    VALID_TASK_IDS.forEach((taskId) => {
      assert.ok(allTasks.has(taskId), `Task ${taskId} never runs in 24 hours`);
    });
  });
});

// ---------------------------------------------------------------------------
// SCHEDULE invariants
// ---------------------------------------------------------------------------

describe("SCHEDULE", () => {
  it("contains only valid hours (0-23)", () => {
    SCHEDULE.forEach((entry) => {
      entry.hoursUtc.forEach((h) => {
        assert.ok(h >= 0 && h <= 23, `Invalid hour ${h} for task ${entry.taskId}`);
      });
    });
  });

  it("has no duplicate task IDs", () => {
    const ids = SCHEDULE.map((e) => e.taskId);
    assert.equal(ids.length, new Set(ids).size);
  });

  it("has no duplicate hours within an entry", () => {
    SCHEDULE.forEach((entry) => {
      const hours = entry.hoursUtc;
      assert.equal(
        hours.length,
        new Set(hours).size,
        `Duplicate hours in ${entry.taskId}`,
      );
    });
  });
});

// ---------------------------------------------------------------------------
// BLOG_SERIES_RUN_CONFIGS
// ---------------------------------------------------------------------------

describe("BLOG_SERIES_RUN_CONFIGS", () => {
  it("has a config for every blog series task in the schedule", () => {
    SCHEDULE.filter((e) => e.taskId.startsWith("blog-series:"))
      .map((e) => e.taskId.slice("blog-series:".length))
      .forEach((seriesId) => {
        assert.ok(
          BLOG_SERIES_RUN_CONFIGS.has(seriesId),
          `Missing run config for series: ${seriesId}`,
        );
      });
  });

  it("each config has non-empty fields", () => {
    BLOG_SERIES_RUN_CONFIGS.forEach((config, key) => {
      assert.ok(config.seriesId.length > 0, `${key}: empty seriesId`);
      assert.ok(config.defaultModel.length > 0, `${key}: empty defaultModel`);
      assert.ok(
        config.priorityUserEnvVar.length > 0,
        `${key}: empty priorityUserEnvVar`,
      );
    });
  });

  it("systems-for-public-good uses gemini-2.5-flash (for grounding support)", () => {
    const config = BLOG_SERIES_RUN_CONFIGS.get("systems-for-public-good");
    assert.ok(config);
    assert.equal(config.defaultModel, "gemini-2.5-flash");
  });
});

// ---------------------------------------------------------------------------
// isValidTaskId
// ---------------------------------------------------------------------------

describe("isValidTaskId", () => {
  it("accepts all known task IDs", () => {
    const known: readonly TaskId[] = [
      "blog-series:chickie-loo",
      "blog-series:auto-blog-zero",
      "blog-series:systems-for-public-good",
      "backfill-blog-images",
      "internal-linking",
      "social-posting",
    ];
    known.forEach((id) => assert.ok(isValidTaskId(id)));
  });

  it("rejects unknown strings", () => {
    assert.ok(!isValidTaskId("unknown-task"));
    assert.ok(!isValidTaskId(""));
    assert.ok(!isValidTaskId("blog-series:nonexistent"));
  });
});

// ---------------------------------------------------------------------------
// extractSeriesId
// ---------------------------------------------------------------------------

describe("extractSeriesId", () => {
  it("extracts series ID from blog-series task", () => {
    assert.equal(extractSeriesId("blog-series:chickie-loo"), "chickie-loo");
    assert.equal(
      extractSeriesId("blog-series:auto-blog-zero"),
      "auto-blog-zero",
    );
    assert.equal(
      extractSeriesId("blog-series:systems-for-public-good"),
      "systems-for-public-good",
    );
  });

  it("returns undefined for non-blog-series tasks", () => {
    assert.equal(extractSeriesId("backfill-blog-images"), undefined);
    assert.equal(extractSeriesId("internal-linking"), undefined);
    assert.equal(extractSeriesId("social-posting"), undefined);
  });
});
