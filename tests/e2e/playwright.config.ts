import { defineConfig, devices } from "@playwright/test"

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
    url: "http://127.0.0.1:4173/tests/e2e/fixtures/word-meter.html",
    cwd: "../..",
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
})
