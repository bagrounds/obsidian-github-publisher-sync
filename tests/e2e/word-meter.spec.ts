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

  test("drops empty transcripts and prunes captions that age past the 30s window", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("   ", 100)
    })
    await expect(page.getByTestId("wm-caption")).toHaveCount(0)
    await page.evaluate(() => {
      window.__wordMeter.simulateFinalTranscriptAt("early word", 1_000)
      window.__wordMeter.simulateFinalTranscriptAt("later words", 25_000)
    })
    // Both captions are inside the 30s window.
    await expect(page.getByTestId("wm-caption")).toHaveCount(2)
    // Tick past the early caption's window; only the later one survives.
    await page.evaluate(() => window.__wordMeter.tick(35_000))
    const captions = page.getByTestId("wm-caption")
    await expect(captions).toHaveCount(1)
    await expect(captions.nth(0)).toHaveText("later words")
  })
})

test.describe("Word Meter — PureScript build — slice 4 — event log", () => {
  test("renders an empty event-log panel with a placeholder before any counting session", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-event-log")).toBeVisible()
    await expect(page.getByTestId("wm-event-log-placeholder")).toBeVisible()
    await expect(page.getByTestId("wm-event-log-entry")).toHaveCount(0)
  })

  test("does not log anything while a counting session is still open", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("hello there", 5_000)
    })
    await expect(page.getByTestId("wm-event-log-entry")).toHaveCount(0)
    await expect(page.getByTestId("wm-event-log-placeholder")).toBeVisible()
  })

  test("stop pushes one entry with started clock, duration, word count and wpm rate", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(1_700_000_000_000)
      window.__wordMeter.simulateFinalTranscriptAt(
        "one two three",
        1_700_000_005_000,
      )
      window.__wordMeter.stopAt(1_700_000_030_000)
    })
    const entry = page.getByTestId("wm-event-log-entry").nth(0)
    await expect(entry).toBeVisible()
    await expect(entry.getByTestId("wm-event-log-entry-duration")).toHaveText("30s")
    await expect(entry.getByTestId("wm-event-log-entry-words")).toHaveText("3 w")
    await expect(entry.getByTestId("wm-event-log-entry-rate")).toHaveText("6.0 wpm")
    const startedText =
      (await entry.getByTestId("wm-event-log-entry-started").textContent()) ?? ""
    expect(startedText.trim().length).toBeGreaterThan(0)
  })

  test("stop/restart appends a second entry in chronological order", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("alpha", 1_000)
      window.__wordMeter.stopAt(60_000) // 1 word / 60s → 1.0 wpm
      window.__wordMeter.startAt(120_000)
      window.__wordMeter.simulateFinalTranscriptAt("beta gamma delta", 130_000)
      window.__wordMeter.stopAt(240_000) // 3 words / 120s → 1.5 wpm
    })
    const entries = page.getByTestId("wm-event-log-entry")
    await expect(entries).toHaveCount(2)
    await expect(entries.nth(0).getByTestId("wm-event-log-entry-duration")).toHaveText("1m 0s")
    await expect(entries.nth(0).getByTestId("wm-event-log-entry-words")).toHaveText("1 w")
    await expect(entries.nth(0).getByTestId("wm-event-log-entry-rate")).toHaveText("1.0 wpm")
    await expect(entries.nth(1).getByTestId("wm-event-log-entry-duration")).toHaveText("2m 0s")
    await expect(entries.nth(1).getByTestId("wm-event-log-entry-words")).toHaveText("3 w")
    await expect(entries.nth(1).getByTestId("wm-event-log-entry-rate")).toHaveText("1.5 wpm")
  })

  test("intervals with no recognized utterances log a zero-word session", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("   ", 1_000)
      window.__wordMeter.stopAt(15_000)
    })
    const entry = page.getByTestId("wm-event-log-entry").nth(0)
    await expect(entry.getByTestId("wm-event-log-entry-words")).toHaveText("0 w")
    await expect(entry.getByTestId("wm-event-log-entry-duration")).toHaveText("15s")
    await expect(entry.getByTestId("wm-event-log-entry-rate")).toHaveText("0 wpm")
  })

  test("caps the event log at the most recent counting sessions", async ({ page }) => {
    await loadWordMeter(page, "ps")
    const limit = await page.evaluate(() => window.__wordMeter.getEventLogLimit())
    expect(limit).toBeGreaterThan(0)
    await page.evaluate((capacity) => {
      for (let intervalIndex = 0; intervalIndex < capacity + 5; intervalIndex++) {
        const startTs = intervalIndex * 10_000
        window.__wordMeter.startAt(startTs)
        window.__wordMeter.stopAt(startTs + 1_000)
      }
    }, limit)
    const length = await page.evaluate(() => window.__wordMeter.getEventLogLength())
    expect(length).toBe(limit)
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

test.describe("Word Meter — PureScript build — slice 5 — diagnostics", () => {
  test("renders the collapsible drawer collapsed by default with the snapshot in its content", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    const drawer = page.getByTestId("wm-diagnostics")
    await expect(drawer).toBeVisible()
    await expect(page.getByTestId("wm-diagnostics-toggle")).toHaveText(/diagnostics/i)
    // <details> is collapsed by default → no `open` attribute.
    await expect(drawer).not.toHaveAttribute("open", "")
    // The snapshot prefix is rendered into the content even while collapsed.
    await expect(page.getByTestId("wm-diagnostics-content")).toContainText("version")
    await expect(page.getByTestId("wm-diagnostics-content")).toContainText("0.1.0")
  })

  test("clicking the summary expands the drawer", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-diagnostics-toggle").click()
    await expect(page.getByTestId("wm-diagnostics")).toHaveAttribute("open", "")
  })

  test("records the init event in the diagnostics log on startup", async ({ page }) => {
    await loadWordMeter(page, "ps")
    expect(await page.evaluate(() => window.__wordMeter.getDiagnosticsLength())).toBeGreaterThan(0)
    await expect(page.getByTestId("wm-diagnostics-content")).toContainText("init")
  })

  test("records start, transcript, and stop entries through the reducer", async ({ page }) => {
    await loadWordMeter(page, "ps")
    const startingLength = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsLength(),
    )
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("hello there", 1_000)
      window.__wordMeter.stopAt(2_000)
    })
    const finalLength = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsLength(),
    )
    expect(finalLength).toBe(startingLength + 3)
    const text = await page.evaluate(() => window.__wordMeter.getDiagnosticsText())
    expect(text).toContain("start counting")
    expect(text).toContain("final transcript")
    expect(text).toContain("words=2")
    expect(text).toContain("stop counting")
  })

  test("caps the diagnostics log at the documented limit", async ({ page }) => {
    await loadWordMeter(page, "ps")
    const limit = await page.evaluate(() => window.__wordMeter.getDiagnosticsLimit())
    expect(limit).toBeGreaterThan(0)
    // Each start → counted utterance → stop appends three entries; drive
    // enough iterations to overflow the cap.
    await page.evaluate((capacity) => {
      const iterations = capacity + 5
      for (let i = 0; i < iterations; i++) {
        const startTs = i * 1_000
        window.__wordMeter.startAt(startTs)
        window.__wordMeter.simulateFinalTranscriptAt("alpha", startTs + 100)
        window.__wordMeter.stopAt(startTs + 500)
      }
    }, limit)
    const length = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsLength(),
    )
    expect(length).toBe(limit)
  })

  test.describe("copy diagnostics", () => {
    test.use({ permissions: ["clipboard-read", "clipboard-write"] })

    test("clicking the copy button updates the status and writes the rendered text to the clipboard", async ({
      page,
    }) => {
      await loadWordMeter(page, "ps")
      await expect(page.getByTestId("wm-diagnostics-copy-status")).toHaveText("")
      // Expand the drawer so the copy button is visible.
      await page.getByTestId("wm-diagnostics-toggle").click()
      await page.getByTestId("wm-diagnostics-copy").click()
      await expect(page.getByTestId("wm-diagnostics-copy-status")).toHaveText(/copied/i)
      const rendered = await page.evaluate(() => window.__wordMeter.getDiagnosticsText())
      const copied = await page.evaluate(() => navigator.clipboard.readText())
      expect(copied).toBe(rendered)
    })
  })
})

test.describe("Word Meter — PureScript build — slice 6 — reset + persistence", () => {
  test("renders a reset button next to the toggle", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-reset")).toBeVisible()
    await expect(page.getByTestId("wm-reset")).toHaveText(/reset/i)
  })

  test("reset button asks for confirmation and wipes accumulated stats on accept", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("alpha beta gamma", 1_000)
      window.__wordMeter.stopAt(2_000)
    })
    await expect(page.getByTestId("wm-count")).toHaveText("3")
    await expect(page.getByTestId("wm-event-log-entry")).toHaveCount(1)

    page.once("dialog", (dialog) => {
      expect(dialog.message()).toMatch(/reset all word meter stats/i)
      void dialog.accept()
    })
    await page.getByTestId("wm-reset").click()

    await expect(page.getByTestId("wm-count")).toHaveText("0")
    await expect(page.getByTestId("wm-event-log-placeholder")).toBeVisible()
    await expect(page.getByTestId("wm-event-log-entry")).toHaveCount(0)
    expect(await page.evaluate(() => window.__wordMeter.getTotalWords())).toBe(0)
  })

  test("declining the confirmation leaves stats untouched", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("hello world", 1_000)
      window.__wordMeter.stopAt(2_000)
    })
    await expect(page.getByTestId("wm-count")).toHaveText("2")

    page.once("dialog", (dialog) => void dialog.dismiss())
    await page.getByTestId("wm-reset").click()

    await expect(page.getByTestId("wm-count")).toHaveText("2")
  })

  test("totals and event log survive a full page reload via localStorage", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("one two three four", 1_000)
      window.__wordMeter.stopAt(5_000)
      window.__wordMeter.startAt(6_000)
      window.__wordMeter.simulateFinalTranscriptAt("five six", 7_000)
      window.__wordMeter.stopAt(8_000)
    })
    await expect(page.getByTestId("wm-count")).toHaveText("6")
    const persistedKey = await page.evaluate(() =>
      Object.keys(window.localStorage).find((k) => k.startsWith("word-meter-ps:state")),
    )
    expect(persistedKey).toBeTruthy()

    await page.reload()
    await page.waitForFunction(() => Boolean(window.__wordMeter))

    await expect(page.getByTestId("wm-count")).toHaveText("6")
    await expect(page.getByTestId("wm-event-log-entry")).toHaveCount(2)
    expect(await page.evaluate(() => window.__wordMeter.getEventLogLength())).toBe(2)
  })

  test("resetAt clears the persisted snapshot so a reload starts fresh", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => {
      window.__wordMeter.startAt(0)
      window.__wordMeter.simulateFinalTranscriptAt("alpha beta", 1_000)
      window.__wordMeter.stopAt(2_000)
    })
    await expect(page.getByTestId("wm-count")).toHaveText("2")

    await page.evaluate(() => window.__wordMeter.resetAt(3_000))
    await expect(page.getByTestId("wm-count")).toHaveText("0")

    await page.reload()
    await page.waitForFunction(() => Boolean(window.__wordMeter))
    await expect(page.getByTestId("wm-count")).toHaveText("0")
    expect(await page.evaluate(() => window.__wordMeter.getEventLogLength())).toBe(0)
  })
})
