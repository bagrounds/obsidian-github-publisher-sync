import { test, expect, type Page } from "@playwright/test"

// Selector contract every Word Meter implementation must honor:
//   wm-root          mounted container
//   wm-build         "PureScript build" / "JavaScript build" tag
//   wm-status        listening / idle status
//   wm-count         total words count
//   wm-count-label   "words counted" descriptor
//   wm-toggle        start / stop button
//   wm-version       "Word Meter v<x>" footer

const loadWordMeter = async (page: Page, build: "js" | "ps") => {
  await page.goto(`/tests/e2e/fixtures/word-meter.html?build=${build}`)
  await page.waitForFunction(() => Boolean(window.__wordMeter))
}

const simulateFinalTranscript = (page: Page, transcript: string) =>
  page.evaluate((text) => window.__wordMeter.simulateFinalTranscript(text), transcript)

test.describe("Word Meter — PureScript build — slice 1 — recording", () => {
  test("renders the panel and identifies the build", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-root")).toBeVisible()
    await expect(page.getByTestId("wm-build")).toHaveText(/purescript/i)
    await expect(page.getByTestId("wm-version")).toHaveText(/word meter \(purescript\) v0\.1\.0/i)
  })

  test("starts idle with zero words", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-status")).toHaveText(/idle/i)
    await expect(page.getByTestId("wm-count")).toHaveText("0")
    await expect(page.getByTestId("wm-toggle")).toHaveText(/start counting/i)
  })

  test("clicking the toggle flips listening status and button label", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-status")).toHaveText(/listening/i)
    await expect(page.getByTestId("wm-toggle")).toHaveText(/stop counting/i)
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-status")).toHaveText(/idle/i)
    await expect(page.getByTestId("wm-toggle")).toHaveText(/start counting/i)
  })

  test("injecting a final transcript while listening increments the count", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await simulateFinalTranscript(page, "hello world")
    await expect(page.getByTestId("wm-count")).toHaveText("2")
    await simulateFinalTranscript(page, "  the quick   brown fox  ")
    await expect(page.getByTestId("wm-count")).toHaveText("6")
  })

  test("injecting a transcript while idle does not change the count", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await simulateFinalTranscript(page, "hello world")
    await expect(page.getByTestId("wm-count")).toHaveText("0")
  })

  test("counter persists across stop and restart", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await simulateFinalTranscript(page, "one two three")
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-count")).toHaveText("3")
    await page.getByTestId("wm-toggle").click()
    await simulateFinalTranscript(page, "four five")
    await expect(page.getByTestId("wm-count")).toHaveText("5")
  })
})

test.describe("Word Meter — PureScript build — slice 2 — live captions", () => {
  test("renders an empty captions panel with a placeholder before any speech", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-captions")).toBeVisible()
    await expect(page.getByTestId("wm-captions-placeholder")).toBeVisible()
    await expect(page.getByTestId("wm-caption")).toHaveCount(0)
  })

  test("appends one caption per injected final transcript", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await simulateFinalTranscript(page, "hello there")
    await simulateFinalTranscript(page, "general kenobi")
    const captions = page.getByTestId("wm-caption")
    await expect(captions).toHaveCount(2)
    await expect(captions.nth(0)).toHaveText("hello there")
    await expect(captions.nth(1)).toHaveText("general kenobi")
    await expect(page.getByTestId("wm-captions-placeholder")).toHaveCount(0)
  })

  test("does not record a caption while idle", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await simulateFinalTranscript(page, "noise")
    await expect(page.getByTestId("wm-caption")).toHaveCount(0)
  })

  test("drops empty transcripts and keeps only the most recent six entries", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await simulateFinalTranscript(page, "   ")
    await expect(page.getByTestId("wm-caption")).toHaveCount(0)
    for (const phrase of ["one", "two", "three", "four", "five", "six", "seven", "eight"]) {
      await simulateFinalTranscript(page, phrase)
    }
    const captions = page.getByTestId("wm-caption")
    await expect(captions).toHaveCount(6)
    await expect(captions.nth(0)).toHaveText("three")
    await expect(captions.nth(5)).toHaveText("eight")
  })
})

test.describe("Word Meter — PureScript build — slice 4 — event log", () => {
  test("renders an empty event log with a placeholder before any speech", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-event-log")).toBeVisible()
    await expect(page.getByTestId("wm-event-log-placeholder")).toBeVisible()
    await expect(page.getByTestId("wm-event-log-entry")).toHaveCount(0)
  })

  test("appends one event-log entry per injected final transcript while listening", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(1_700_000_000_000)
      window.__wordMeter.simulateFinalTranscriptAt("hello there", 1_700_000_001_000)
      window.__wordMeter.simulateFinalTranscriptAt("general kenobi", 1_700_000_002_000)
    })
    const entries = page.getByTestId("wm-event-log-entry")
    await expect(entries).toHaveCount(2)
    // Chronological order: oldest first, newest last.
    await expect(entries.nth(0).getByTestId("wm-event-log-entry-transcript")).toHaveText(
      "hello there",
    )
    await expect(entries.nth(0).getByTestId("wm-event-log-entry-words")).toHaveText("2 w")
    await expect(entries.nth(1).getByTestId("wm-event-log-entry-transcript")).toHaveText(
      "general kenobi",
    )
    await expect(entries.nth(1).getByTestId("wm-event-log-entry-words")).toHaveText("2 w")
    await expect(page.getByTestId("wm-event-log-placeholder")).toHaveCount(0)
  })

  test("each entry surfaces a non-empty clock-time stamp", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(1_700_000_000_000)
      window.__wordMeter.simulateFinalTranscriptAt("one two three", 1_700_000_005_000)
    })
    const timeCell = page.getByTestId("wm-event-log-entry").nth(0).getByTestId(
      "wm-event-log-entry-time",
    )
    await expect(timeCell).toBeVisible()
    const timeText = (await timeCell.textContent()) ?? ""
    expect(timeText.trim().length).toBeGreaterThan(0)
    expect(timeText).not.toBe("—")
  })

  test("does not log an entry while idle or for empty / whitespace transcripts", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await simulateFinalTranscript(page, "noise while idle")
    await expect(page.getByTestId("wm-event-log-entry")).toHaveCount(0)
    await page.getByTestId("wm-toggle").click()
    await simulateFinalTranscript(page, "   ")
    await expect(page.getByTestId("wm-event-log-entry")).toHaveCount(0)
    await expect(page.getByTestId("wm-event-log-placeholder")).toBeVisible()
  })

  test("event log is preserved across stop and restart", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("alpha", 1_000)
      window.__wordMeter.stopAt(2_000)
      window.__wordMeter.startAt(3_000)
      window.__wordMeter.simulateFinalTranscriptAt("beta gamma", 4_000)
    })
    const entries = page.getByTestId("wm-event-log-entry")
    await expect(entries).toHaveCount(2)
    await expect(entries.nth(0).getByTestId("wm-event-log-entry-transcript")).toHaveText("alpha")
    await expect(entries.nth(1).getByTestId("wm-event-log-entry-transcript")).toHaveText(
      "beta gamma",
    )
  })

  test("caps the event log at the most recent entries", async ({ page }) => {
    await loadWordMeter(page, "ps")
    const limit = await page.evaluate(() => window.__wordMeter.getEventLogLimit())
    expect(limit).toBeGreaterThan(0)
    await page.evaluate((capacity) => {
      window.__wordMeter.startAt(0)
      for (let utteranceIndex = 0; utteranceIndex < capacity + 5; utteranceIndex++) {
        window.__wordMeter.simulateFinalTranscriptAt(
          `utterance number ${utteranceIndex}`,
          (utteranceIndex + 1) * 1000,
        )
      }
    }, limit)
    const length = await page.evaluate(() => window.__wordMeter.getEventLogLength())
    expect(length).toBe(limit)
    // Oldest five utterances were evicted — the first kept entry is utterance #5.
    const entries = page.getByTestId("wm-event-log-entry")
    await expect(entries.nth(0).getByTestId("wm-event-log-entry-transcript")).toHaveText(
      "utterance number 5",
    )
  })
})

test.describe("Word Meter — PureScript build — slice 3 — stats dashboard", () => {
  test("renders all five stat tiles starting at zero / em-dash", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-stats")).toBeVisible()
    await expect(page.getByTestId("wm-rate-short")).toContainText("0")
    await expect(page.getByTestId("wm-rate-long")).toContainText("0")
    await expect(page.getByTestId("wm-rate-overall")).toContainText("0")
    await expect(page.getByTestId("wm-duration")).toContainText("0s")
    await expect(page.getByTestId("wm-started")).toContainText("—")
  })

  test("captures the first-started timestamp on the very first start", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => window.__wordMeter.startAt(1_700_000_000_000))
    const firstStartedAt = await page.evaluate(() => window.__wordMeter.getFirstStartedAt())
    expect(firstStartedAt).toBe(1_700_000_000_000)
    await expect(page.getByTestId("wm-started")).not.toHaveText("—")
  })

  test("words / minute over the short window after a full minute", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("one two three four five six", 10_000)
      window.__wordMeter.tick(60_000)
    })
    expect(await page.evaluate(() => window.__wordMeter.getRateShort())).toBe(6)
    await expect(page.getByTestId("wm-rate-short")).toHaveText("6.0")
  })

  test("duration tile reflects active listening time across stop / start", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.stopAt(30_000)
      window.__wordMeter.startAt(60_000)
      window.__wordMeter.tick(90_000)
    })
    expect(await page.evaluate(() => window.__wordMeter.getDurationMs())).toBe(60_000)
    await expect(page.getByTestId("wm-duration")).toHaveText("1m 0s")
  })

  test("overall words / minute uses active listening time, not wall clock", async ({ page }) => {
    await loadWordMeter(page, "ps")
    // 6 words spoken over a 120s active-listening total with a 60s paused gap
    // in the middle. Overall WPM divides by active time (120s) → 3 wpm.
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("one two three", 30_000)
      window.__wordMeter.stopAt(60_000)
      window.__wordMeter.startAt(120_000)
      window.__wordMeter.simulateFinalTranscriptAt("four five six", 150_000)
      window.__wordMeter.tick(180_000)
    })
    expect(await page.evaluate(() => window.__wordMeter.getRateOverall())).toBe(3)
    await expect(page.getByTestId("wm-rate-overall")).toHaveText("3.0")
  })

  test("long-window rate counts everything inside the trailing 10 minutes", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("one two three four five", 60_000)
      window.__wordMeter.simulateFinalTranscriptAt("six seven eight nine ten", 120_000)
      window.__wordMeter.tick(600_000)
    })
    // 10 words / 10 minutes = 1 wpm
    expect(await page.evaluate(() => window.__wordMeter.getRateLong())).toBe(1)
    await expect(page.getByTestId("wm-rate-long")).toHaveText("1.0")
  })
})
