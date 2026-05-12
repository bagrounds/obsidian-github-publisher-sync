import { test, expect, type Page } from "@playwright/test"

// Implementation-agnostic Word Meter end-to-end tests.
//
// Each test loads the fixture page with a specific `?impl=` so the
// same selector contract can verify both the legacy JavaScript build
// and the new PureScript build as the port progresses. Slice 1 only
// covers the PureScript hello-world mount; the JavaScript suite will
// grow in lockstep as we port behavior.
//
// Selector contract (must be honored by every implementation):
//   [data-testid="wm-root"]        - container the script mounts into
//   [data-testid="wm-count"]       - big total-words number
//   [data-testid="wm-count-label"] - "words counted" descriptor
//   [data-testid="wm-toggle"]      - start/stop button
//   [data-testid="wm-version"]     - footer "Word Meter v<x>" line
//   [data-testid="wm-impl"]        - "PureScript build" / "JavaScript build" tag

const openFixture = async (page: Page, impl: "js" | "ps") => {
  await page.goto(`/tests/e2e/fixtures/word-meter.html?impl=${impl}`)
}

test.describe("Word Meter — PureScript build (slice 1: hello world)", () => {
  test("mounts a root element inside #word-meter", async ({ page }) => {
    await openFixture(page, "ps")
    await expect(page.getByTestId("wm-root")).toBeVisible()
  })

  test("renders a zero count and a count label", async ({ page }) => {
    await openFixture(page, "ps")
    await expect(page.getByTestId("wm-count")).toHaveText("0")
    await expect(page.getByTestId("wm-count-label")).toHaveText(/words counted/i)
  })

  test("shows a start/stop toggle button", async ({ page }) => {
    await openFixture(page, "ps")
    await expect(page.getByTestId("wm-toggle")).toBeVisible()
    await expect(page.getByTestId("wm-toggle")).toHaveText(/start counting/i)
  })

  test("renders a version label that announces the implementation", async ({ page }) => {
    await openFixture(page, "ps")
    const version = page.getByTestId("wm-version")
    await expect(version).toBeVisible()
    await expect(version).toHaveText(/word meter \(purescript\) v\d+\.\d+\.\d+/i)
  })

  test("tags the build as PureScript", async ({ page }) => {
    await openFixture(page, "ps")
    await expect(page.getByTestId("wm-impl")).toHaveText(/purescript/i)
  })
})
