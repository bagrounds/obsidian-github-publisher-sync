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
