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

test.describe("Word Meter — PureScript build — slice 7 — keep-awake toggle", () => {
  test("renders a keep-awake checkbox that defaults to checked", async ({ page }) => {
    await loadWordMeter(page, "ps")
    const checkbox = page.getByTestId("wm-keep-awake")
    await expect(checkbox).toBeVisible()
    await expect(checkbox).toHaveAttribute("type", "checkbox")
    await expect(checkbox).toBeChecked()
    expect(await page.evaluate(() => window.__wordMeter.getKeepAwake())).toBe(true)
    await expect(page.getByTestId("wm-keep-awake-status")).toHaveText("")
  })

  test("setKeepAwake flips the preference and reflects it on the rendered checkbox", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => window.__wordMeter.setKeepAwake(false))
    expect(await page.evaluate(() => window.__wordMeter.getKeepAwake())).toBe(false)
    await expect(page.getByTestId("wm-keep-awake")).not.toBeChecked()
    await page.evaluate(() => window.__wordMeter.setKeepAwake(true))
    await expect(page.getByTestId("wm-keep-awake")).toBeChecked()
  })

  test("toggling the checkbox via the DOM dispatches a SetKeepAwake action", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-keep-awake").uncheck()
    expect(await page.evaluate(() => window.__wordMeter.getKeepAwake())).toBe(false)
    await page.getByTestId("wm-keep-awake").check()
    expect(await page.evaluate(() => window.__wordMeter.getKeepAwake())).toBe(true)
  })

  test("starting with keep-awake on records a wake-lock attempt in diagnostics", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-keep-awake")).toBeChecked()
    const lengthBefore = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsLength(),
    )
    await page.getByTestId("wm-toggle").click()
    // The status reflects either success ("screen will stay on") or an
    // "unavailable" reason in parens — both prove the request flowed
    // through. Headless Chromium typically denies wake locks, so the
    // unavailable path is what we usually observe; we accept either.
    await expect(page.getByTestId("wm-keep-awake-status")).not.toHaveText("")
    const lengthAfter = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsLength(),
    )
    expect(lengthAfter).toBeGreaterThan(lengthBefore)
    const diagnostics = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsText(),
    )
    expect(/wake lock (acquired|failure)/i.test(diagnostics)).toBe(true)
  })

  test("stopping releases the wake lock and clears the status", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-keep-awake-status")).not.toHaveText("")
    await page.getByTestId("wm-toggle").click()
    expect(await page.evaluate(() => window.__wordMeter.getWakeLockHeld())).toBe(false)
    await expect(page.getByTestId("wm-keep-awake-status")).toHaveText("")
    // Some wake-lock activity must be visible in the diagnostics: either
    // we acquired and released (real browser), or we recorded an
    // acquisition failure (headless Chromium denies the lock). Either is
    // a valid audit trail — silent no-ops are what we are guarding
    // against.
    const diagnostics = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsText(),
    )
    expect(/wake lock (acquired|failure|release)/i.test(diagnostics)).toBe(true)
  })

  test("starting with keep-awake off does not request a wake lock", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => window.__wordMeter.setKeepAwake(false))
    await page.getByTestId("wm-toggle").click()
    // No status text means we never tried to acquire.
    await expect(page.getByTestId("wm-keep-awake-status")).toHaveText("")
    const diagnostics = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsText(),
    )
    expect(/wake lock acquired|wake lock failure/i.test(diagnostics)).toBe(false)
  })

  test("the checkbox is disabled while listening", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await expect(page.getByTestId("wm-keep-awake")).toBeEnabled()
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-keep-awake")).toBeDisabled()
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-keep-awake")).toBeEnabled()
  })

  test("the keep-awake preference is not persisted across reload (always defaults on)", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.evaluate(() => window.__wordMeter.setKeepAwake(false))
    expect(await page.evaluate(() => window.__wordMeter.getKeepAwake())).toBe(false)
    await page.reload()
    await page.waitForFunction(() => Boolean(window.__wordMeter))
    expect(await page.evaluate(() => window.__wordMeter.getKeepAwake())).toBe(true)
  })
})

test.describe("Word Meter — PureScript build — slice 8 — recognition errors", () => {
  test("renders an empty error banner before any error", async ({ page }) => {
    await loadWordMeter(page, "ps")
    const banner = page.getByTestId("wm-error")
    await expect(banner).toBeVisible()
    await expect(banner).toHaveText("")
    await expect(banner).toHaveAttribute("role", "alert")
  })

  test("a transient error (no-speech) does not show a banner and keeps listening", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-status")).toHaveText(/listening/i)
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("no-speech", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText("")
    await expect(page.getByTestId("wm-status")).toHaveText(/listening/i)
    expect(await page.evaluate(() => window.__wordMeter.getListening())).toBe(true)
    const diagnostics = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsText(),
    )
    expect(/recognition\.onerror/.test(diagnostics)).toBe(true)
    expect(/code=no-speech/.test(diagnostics)).toBe(true)
  })

  test("a permission-denied error shows the banner and stops listening", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("not-allowed", "blocked"),
    )
    await expect(page.getByTestId("wm-error")).toHaveText(
      /microphone permission denied/i,
    )
    await expect(page.getByTestId("wm-status")).toHaveText(/idle/i)
    expect(await page.evaluate(() => window.__wordMeter.getListening())).toBe(
      false,
    )
    const diagnostics = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsText(),
    )
    expect(/recognition\.onerror/.test(diagnostics)).toBe(true)
    expect(/session ended/.test(diagnostics)).toBe(true)
    expect(/reason=permission denied/.test(diagnostics)).toBe(true)
  })

  test("a service-not-allowed error is also treated as permission-denied", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("service-not-allowed", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText(
      /microphone permission denied/i,
    )
    expect(await page.evaluate(() => window.__wordMeter.getListening())).toBe(
      false,
    )
  })

  test("a network error shows a banner but keeps listening (recoverable)", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("network", "offline"),
    )
    await expect(page.getByTestId("wm-error")).toHaveText(/network error/i)
    expect(await page.evaluate(() => window.__wordMeter.getListening())).toBe(true)
  })

  test("an unknown error code falls back to a generic banner", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("weird", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText("Recognition error: weird")
  })

  test("an empty error code renders the unknown-code banner", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText("Recognition error: unknown")
  })

  test("starting again after a network error clears the banner", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("network", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText(/network error/i)
    // Stop, then start again — the start branch clears the banner.
    await page.getByTestId("wm-toggle").click()
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-error")).toHaveText("")
  })

  test("reset clears any prior error banner", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("network", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText(/network error/i)
    await page.evaluate(() => window.__wordMeter.resetAt(99999))
    await expect(page.getByTestId("wm-error")).toHaveText("")
  })

  test("getErrorBanner reflects the rendered text", async ({ page }) => {
    await loadWordMeter(page, "ps")
    expect(await page.evaluate(() => window.__wordMeter.getErrorBanner())).toBe("")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("network", ""),
    )
    expect(await page.evaluate(() => window.__wordMeter.getErrorBanner())).toMatch(
      /network error/i,
    )
  })
})

test.describe("Word Meter — PureScript build — slice 9c — language-not-supported retry", () => {
  test("on-device language-not-supported swaps to cloud once without showing a banner", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    // Start listening. With the on-device pre-flight disabled in the
    // fixture, the orchestrator lands on the cloud path. Manually
    // pin the active path back to "on-device" through the test hook
    // so we can drive the slice-9c retry branch deterministically.
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-status")).toHaveText(/listening/i)
    await page.evaluate(() =>
      window.__wordMeter.setActiveRecognitionPath("on-device"),
    )
    expect(
      await page.evaluate(() => window.__wordMeter.getActiveRecognitionPath()),
    ).toBe("on-device")

    // Fire the runtime language-not-supported error. The retry branch
    // must keep listening, leave the banner empty, set the flag, and
    // swap the active path back to cloud.
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("language-not-supported", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText("")
    expect(await page.evaluate(() => window.__wordMeter.getListening())).toBe(true)
    expect(
      await page.evaluate(() => window.__wordMeter.getCloudFallbackAttempted()),
    ).toBe(true)
    expect(
      await page.evaluate(() => window.__wordMeter.getActiveRecognitionPath()),
    ).toBe("cloud")
    const diagnostics: string = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsText(),
    )
    expect(
      /language-not-supported at runtime — falling back to cloud/.test(diagnostics),
    ).toBe(true)
    expect(/code=language-not-supported/.test(diagnostics)).toBe(true)
  })

  test("a second language-not-supported on the cloud path surfaces the banner (no infinite retry)", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    // First strike: from the on-device path the orchestrator swallows
    // the error and swaps to cloud. The slice-9c flag is now consumed.
    await page.evaluate(() =>
      window.__wordMeter.setActiveRecognitionPath("on-device"),
    )
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("language-not-supported", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText("")

    // Second strike: the path is now cloud; the slice-9c branch must
    // not fire again. The reducer falls back to the language-unavailable
    // banner from slice 8.
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("language-not-supported", ""),
    )
    await expect(page.getByTestId("wm-error")).toHaveText(
      /speech recognition is not available for your language/i,
    )
  })

  test("Toggle (start) clears cloudFallbackAttempted so the next session gets a fresh retry budget", async ({
    page,
  }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await page.evaluate(() =>
      window.__wordMeter.setActiveRecognitionPath("on-device"),
    )
    await page.evaluate(() =>
      window.__wordMeter.simulateRecognitionError("language-not-supported", ""),
    )
    expect(
      await page.evaluate(() => window.__wordMeter.getCloudFallbackAttempted()),
    ).toBe(true)

    // Stop and start a fresh session; the budget must reset.
    await page.getByTestId("wm-toggle").click()
    await page.getByTestId("wm-toggle").click()
    expect(
      await page.evaluate(() => window.__wordMeter.getCloudFallbackAttempted()),
    ).toBe(false)
  })
})

test.describe("Word Meter — PureScript build — slice 9b — on-device pre-flight", () => {
  test("with on-device pre-flight disabled, start logs the cloud-fallback diagnostic and never sets the download status", async ({ page }) => {
    await loadWordMeter(page, "ps")
    await page.getByTestId("wm-toggle").click()
    await expect(page.getByTestId("wm-status")).toHaveText(/listening/i)
    const diagnostics: string = await page.evaluate(() =>
      window.__wordMeter.getDiagnosticsText(),
    )
    expect(/on-device API absent — falling back to cloud/.test(diagnostics)).toBe(true)
    // The "downloading on-device language pack…" override is only set
    // while install() is in flight; the API-absent branch must never
    // touch it.
    const statusOverride: string = await page.evaluate(() =>
      window.__wordMeter.getRecognitionStatusOverride(),
    )
    expect(statusOverride).toBe("")
  })

  test("getRecognitionStatusOverride defaults to empty on idle", async ({ page }) => {
    await loadWordMeter(page, "ps")
    expect(
      await page.evaluate(() => window.__wordMeter.getRecognitionStatusOverride()),
    ).toBe("")
  })
})
