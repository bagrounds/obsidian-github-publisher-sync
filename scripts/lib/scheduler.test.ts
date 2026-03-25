import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  getScheduledTasks,
  SCHEDULE,
  VALID_TASK_IDS,
  BLOG_SERIES_RUN_CONFIGS,
  isValidTaskId,
  extractSeriesId,
  blogPostExistsForToday,
  type TaskId,
} from "./scheduler.ts";

// ---------------------------------------------------------------------------
// getScheduledTasks — "at or after" for blog series and atOrAfter entries, exact for others
// ---------------------------------------------------------------------------

describe("getScheduledTasks", () => {
  it("returns chickie-loo at its scheduled hour 15", () => {
    const tasks = getScheduledTasks(15);
    assert.ok(tasks.includes("blog-series:chickie-loo"));
  });

  it("returns chickie-loo at hours AFTER its scheduled hour (resilient retry)", () => {
    [16, 17, 18, 23].forEach((hour) => {
      const tasks = getScheduledTasks(hour);
      assert.ok(
        tasks.includes("blog-series:chickie-loo"),
        `chickie-loo should be eligible at hour ${hour} (at-or-after scheduling)`,
      );
    });
  });

  it("does NOT return chickie-loo before its scheduled hour", () => {
    [0, 1, 14].forEach((hour) => {
      const tasks = getScheduledTasks(hour);
      assert.ok(
        !tasks.includes("blog-series:chickie-loo"),
        `chickie-loo should NOT be eligible at hour ${hour}`,
      );
    });
  });

  it("returns auto-blog-zero at and after hour 16", () => {
    assert.ok(getScheduledTasks(16).includes("blog-series:auto-blog-zero"));
    assert.ok(getScheduledTasks(17).includes("blog-series:auto-blog-zero"));
    assert.ok(!getScheduledTasks(15).includes("blog-series:auto-blog-zero"));
  });

  it("returns systems-for-public-good at and after hour 17", () => {
    assert.ok(getScheduledTasks(17).includes("blog-series:systems-for-public-good"));
    assert.ok(getScheduledTasks(23).includes("blog-series:systems-for-public-good"));
    assert.ok(!getScheduledTasks(16).includes("blog-series:systems-for-public-good"));
  });

  it("at hour 17, returns all three blog series (resilient catchup)", () => {
    const tasks = getScheduledTasks(17);
    assert.ok(tasks.includes("blog-series:chickie-loo"));
    assert.ok(tasks.includes("blog-series:auto-blog-zero"));
    assert.ok(tasks.includes("blog-series:systems-for-public-good"));
  });

  it("returns reflection-title at and after hour 5 (at-or-after scheduling)", () => {
    assert.ok(getScheduledTasks(5).includes("reflection-title"));
    assert.ok(getScheduledTasks(6).includes("reflection-title"));
    assert.ok(getScheduledTasks(23).includes("reflection-title"));
  });

  it("does NOT return reflection-title before hour 5", () => {
    [0, 1, 2, 3, 4].forEach((hour) => {
      assert.ok(
        !getScheduledTasks(hour).includes("reflection-title"),
        `reflection-title should NOT be eligible at hour ${hour}`,
      );
    });
  });

  it("returns backfill-blog-images at every hour", () => {
    Array.from({ length: 24 }, (_, h) => h).forEach((hour) => {
      assert.ok(
        getScheduledTasks(hour).includes("backfill-blog-images"),
        `backfill-blog-images should run at hour ${hour}`,
      );
    });
  });

  it("returns internal-linking at every hour", () => {
    Array.from({ length: 24 }, (_, h) => h).forEach((hour) => {
      assert.ok(
        getScheduledTasks(hour).includes("internal-linking"),
        `internal-linking should run at hour ${hour}`,
      );
    });
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

  it("returns only backfill tasks before blog series are scheduled", () => {
    const tasksAt1 = getScheduledTasks(1);
    assert.ok(tasksAt1.includes("backfill-blog-images"));
    assert.ok(tasksAt1.includes("internal-linking"));
    assert.ok(!tasksAt1.includes("social-posting"));
    assert.ok(!tasksAt1.includes("blog-series:chickie-loo"));
    assert.ok(!tasksAt1.includes("reflection-title"));

    const tasksAt3 = getScheduledTasks(3);
    assert.ok(tasksAt3.includes("backfill-blog-images"));
    assert.ok(tasksAt3.includes("internal-linking"));
    assert.ok(!tasksAt3.includes("social-posting"));
    assert.ok(!tasksAt3.includes("reflection-title"));
  });

  it("returns multiple tasks when schedules overlap", () => {
    const tasksAt6 = getScheduledTasks(6);
    assert.ok(tasksAt6.includes("backfill-blog-images"));
    assert.ok(tasksAt6.includes("internal-linking"));
    assert.ok(tasksAt6.includes("social-posting"));

    const tasksAt8 = getScheduledTasks(8);
    assert.ok(tasksAt8.includes("internal-linking"));
    assert.ok(tasksAt8.includes("backfill-blog-images"));
    assert.ok(tasksAt8.includes("social-posting"));
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

  it("each config has non-empty modelChain and priorityUserEnvVar", () => {
    BLOG_SERIES_RUN_CONFIGS.forEach((config, key) => {
      assert.ok(config.seriesId.length > 0, `${key}: empty seriesId`);
      assert.ok(config.modelChain.length > 0, `${key}: empty modelChain`);
      assert.ok(
        config.priorityUserEnvVar.length > 0,
        `${key}: empty priorityUserEnvVar`,
      );
    });
  });

  it("systems-for-public-good leads with gemini-2.5-flash (for grounding support)", () => {
    const config = BLOG_SERIES_RUN_CONFIGS.get("systems-for-public-good");
    assert.ok(config);
    assert.equal(config.modelChain[0], "gemini-2.5-flash");
  });

  it("all model chains include gemini-2.5-flash-lite as fallback", () => {
    BLOG_SERIES_RUN_CONFIGS.forEach((config, key) => {
      assert.ok(
        config.modelChain.includes("gemini-2.5-flash-lite"),
        `${key}: modelChain should include gemini-2.5-flash-lite`,
      );
    });
  });

  it("gemini-2.5-flash-lite is never the first (default) model", () => {
    BLOG_SERIES_RUN_CONFIGS.forEach((config, key) => {
      assert.notEqual(
        config.modelChain[0],
        "gemini-2.5-flash-lite",
        `${key}: gemini-2.5-flash-lite should not be the default model`,
      );
    });
  });

  it("no duplicate models within a model chain", () => {
    BLOG_SERIES_RUN_CONFIGS.forEach((config, key) => {
      assert.equal(
        config.modelChain.length,
        new Set(config.modelChain).size,
        `${key}: duplicate models in modelChain`,
      );
    });
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
      "reflection-title",
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

// ---------------------------------------------------------------------------
// blogPostExistsForToday
// ---------------------------------------------------------------------------

describe("blogPostExistsForToday", () => {
  it("returns false for non-existent directory", () => {
    assert.equal(blogPostExistsForToday("/tmp/nonexistent-dir-xyz", "2026-03-24"), false);
  });

  it("returns false for empty directory", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "scheduler-test-"));
    try {
      assert.equal(blogPostExistsForToday(tmpDir, "2026-03-24"), false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns true when a post for today exists", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "scheduler-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-24-test-post.md"), "content");
      assert.equal(blogPostExistsForToday(tmpDir, "2026-03-24"), true);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns false when posts exist for other dates only", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "scheduler-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-23-yesterday.md"), "content");
      assert.equal(blogPostExistsForToday(tmpDir, "2026-03-24"), false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});
