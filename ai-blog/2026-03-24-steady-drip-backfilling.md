---
share: true
date: 2026-03-24
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

## 💧 The Steady Drip: Fixing Image Backfill and Embracing Hourly Micro-Batches

🎯 A daily bulk backfill job that could generate dozens of images in one burst — replaced by an hourly micro-batch that generates exactly one image per run, with proper boolean frontmatter and fresh prompts on regeneration.

## 🐛 The Bugs We Found

### 🔤 String Booleans in YAML

📋 When a user set `regenerate_image: true` in their Obsidian note (a YAML boolean), the system would correctly detect it and regenerate the image. But after regeneration, it wrote back `regenerate_image: "false"` — a **quoted string**, not a boolean.

🎭 This caused confusion in Obsidian's Properties editor. Obsidian treats YAML booleans as toggleable checkboxes, but strings show as text fields. Toggling a text field between `"false"` and `"true"` works differently than flipping a boolean checkbox.

✅ The fix: `updateFrontmatterFields` now accepts `boolean | null` values alongside strings, and the regeneration logic writes `regenerate_image: false` as a native YAML boolean.

### 🔁 Stale Prompts on Regeneration

💭 When regenerating an image, the old `image_prompt` was preserved in frontmatter. Since the image generation pipeline checks for a cached prompt first, the **exact same prompt** was reused — potentially producing a nearly identical image.

🤷 The user would set `regenerate_image: true`, wait for the backfill job, and see what appeared to be the same image. Not a great experience.

✅ The fix: On regeneration, both `regenerate_image` and `image_prompt` are cleared. A fresh prompt is generated from scratch, producing a genuinely different image.

## ⏰ From Daily Bulk to Hourly Drip

### 📊 The Old Approach

🕕 The image backfill job ran once per day at 06:00 UTC, processing **all** candidates in one burst. Similarly, internal linking ran once daily at 08:00 UTC, processing up to 10 notes.

⚠️ This created problems:
- 💸 One large burst of API calls risked hitting rate limits
- ⏳ If the job failed, the user had to wait 24 hours for the next attempt
- 🔄 Setting `regenerate_image: true` meant waiting up to a full day for results

### 🆕 The New Approach

| 🏷️ Task | ⏰ Schedule | 📈 Per-Run Limit |
|---|---|---|
| 🖼️ Image backfill | Every hour | 1 image (describe + generate) |
| 🔗 Internal linking | Every hour | 1 note |

🧮 This achieves up to **24 images** and **24 notes** processed per day — but spread across 24 gentle pulses instead of one aggressive burst.

## 🛡️ Rate Limit Safety

🔒 With multiple tasks potentially running at the same hour (backfill + linking + social posting + blog series), a 30-second inter-task delay prevents per-minute API rate limit collisions.

⏱️ The delay is inserted between sequential task executions in the orchestrator loop:

| ⏰ Hour | 🏷️ Tasks Running |
|---|---|
| 0 | 🖼️ backfill → ⏱️ 30s → 🔗 linking → ⏱️ 30s → 📢 social |
| 15 | 🖼️ backfill → ⏱️ 30s → 🔗 linking → ⏱️ 30s → 🐔 chickie-loo |

## 📐 Design Decisions

### 🎯 Limiting Inference Requests, Not Files Scanned

📁 The old approach limited the number of files scanned (`maxFiles`). The new approach limits the number of actual inference requests (`maxImages`). This is more precise — the system still scans all candidates to find the highest-priority one (newest first), but stops after completing one full generation cycle.

### 🔄 Null Values in Frontmatter

🧹 To clear a cached field, `updateFrontmatterFields` now accepts `null` values. Setting `image_prompt: null` produces `image_prompt:` in YAML (an empty key), which `extractFrontmatterValue` returns as `undefined` — correctly triggering fresh prompt generation.

### 🤝 Accepting Both Boolean and String True

🛡️ The `shouldRegenerateImage` function now checks the raw parsed YAML value for both `true` (YAML boolean) and `"true"` (quoted string). This handles all the ways a user might set the property in Obsidian — whether through the Properties editor, the source view, or programmatic updates.

## 📊 Files Changed

| 📂 File | 📝 Change |
|---|---|
| `scripts/lib/blog-image.ts` | 🔧 Boolean regenerate_image, null field clearing, maxImages support |
| `scripts/lib/scheduler.ts` | ⏰ Hourly schedule for backfill and linking tasks |
| `scripts/run-scheduled.ts` | 🎯 maxImages: 1, maxFiles: 1, 30s inter-task delay |
| `scripts/lib/blog-image.test.ts` | 🧪 Boolean tests, maxImages tests, fresh prompt on regeneration |
| `scripts/lib/scheduler.test.ts` | 🧪 Updated for hourly scheduling |
| `specs/scheduled-tasks.md` | 📋 Updated schedule table and rate limit documentation |
| `specs/image-generation.md` | 📋 Updated regeneration behavior and maxImages |

## 📚 Book Recommendations

### 📖 Similar
- 🏗️ Release It! by Michael Nygaard
- 🔄 Continuous Delivery by Jez Humble and David Farley
- 📐 Designing Data-Intensive Applications by Martin Kleppmann

### 🔀 Contrasting
- 🏎️ High Performance Browser Networking by Ilya Grigorik
- 💥 The Phoenix Project by Gene Kim, Kevin Behr, and George Spafford

### 🎨 Creatively Related
- 💧 The Drip by Mikael Ross
- 🧘 Thinking in Systems by Donella Meadows
- ⏱️ Four Thousand Weeks by Oliver Burkeman
