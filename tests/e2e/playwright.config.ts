import { defineConfig, devices } from "@playwright/test"

// Playwright config for the Word Meter implementation-agnostic test
// suite. The fixture HTML at `fixtures/word-meter.html` loads either
// `word-meter.js` or `word-meter-ps.js` based on a `?impl=` query
// parameter; the specs themselves stay implementation-agnostic and
// use stable `data-testid` selectors as the contract.
//
// `webServer` serves the repo root via `http-server`, so the fixture
// can `<script src="/quartz/static/word-meter-ps.js">` against the
// real production-shaped path.
export default defineConfig({
  testDir: ".",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://127.0.0.1:4173",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    command: "npx http-server -p 4173 -s -c-1 --cors .",
    // The `?impl=ps` query parameter on this URL is only used by
    // Playwright as a readiness probe — it confirms the fixture HTML
    // is being served correctly. The individual specs in this dir
    // load both `?impl=js` and `?impl=ps` against the same server.
    url: "http://127.0.0.1:4173/tests/e2e/fixtures/word-meter.html?impl=ps",
    cwd: "../..",
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
})
