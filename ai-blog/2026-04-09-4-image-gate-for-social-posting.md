---
share: true
aliases:
  - "2026-04-09 | 🖼️ Image Gate for Social Posting 🚪"
title: "2026-04-09 | 🖼️ Image Gate for Social Posting 🚪"
URL: https://bagrounds.org/ai-blog/2026-04-09-4-image-gate-for-social-posting
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-09 | 🖼️ Image Gate for Social Posting 🚪

## 🎯 The Problem

📢 Social media posts with attractive cover images get more engagement than plain text links.
🖼️ The site generates cover images for blog posts through an automated backfill pipeline that runs twice per hour.
📣 The social posting pipeline runs once every two hours, crawling content via breadth-first search to find unposted notes.
⏳ Because these two pipelines run independently, it was possible for the social poster to find and share a page before the image backfill had generated its cover image.
🤔 The result was social media posts with bland, generic open graph previews instead of the beautiful custom cover images.

## 💡 The Solution

🚪 We added an image readiness gate to the social posting content discovery pipeline.
🔍 Before selecting a note for posting, the system now checks whether the note is still waiting for an image backfill.
♻️ The check reuses the exact same logic from the image generation pipeline, specifically two functions from the BlogImage module and the content directory configuration from BlogSeriesConfig.

## 🧩 How It Works

📂 A note is considered awaiting image backfill when three conditions all hold true.
📁 First, the note lives in one of the configured image backfill content directories, which today covers all thirteen content directories including reflections, ai-blog, books, topics, and more.
📄 Second, the note's filename passes the shouldHaveImage predicate, meaning it is a markdown file not on the exclusion list of index, AGENTS, or IDEAS.
🚫 Third, the note's body does not contain an embedded image, checked via the hasEmbeddedImage function which looks for both Obsidian wiki-style image embeds and standard markdown image syntax.

✅ Notes that already have an image pass through normally and are posted.
✅ Notes that would never receive an image, such as files in unknown directories or excluded filenames, also pass through normally.
⏭️ Notes that are awaiting an image are skipped, but the breadth-first search still follows their links to discover other postable content beyond them.

## 📐 Design Decisions

🧮 The image backfill runs at twice the rate of social posting, generating two images per hour versus one social post every two hours.
📈 This means the pool of image-ready content grows faster than the posting queue drains it.
🔄 Eventually every eligible note will have its cover image, and the gate will stop filtering anything.

🧹 We chose to create a single pure function called isAwaitingImageBackfill that takes just the relative file path and the body text.
🧪 This keeps the function easy to test with ten new unit tests covering all the important cases.
🔗 The function is integrated at two points in the content discovery pipeline: the BFS loop for general content and the priority reflection path for the prior day's reflection.

## 🧪 Testing

🔬 Ten new tests validate the image gate logic.
📊 Nine pure unit tests cover the core predicate, including notes with and without images, notes in various content directories, excluded files, non-markdown files, and files in unknown directories.
🔄 One integration test verifies end-to-end BFS behavior: a note without an image is skipped, but its linked neighbor with an image is still discovered and selected for posting.
📝 Six existing BFS integration tests were updated to include image embeds in their test note content, since those notes live in backfill-eligible directories and would now be filtered without images.

## 📚 Book Recommendations

### 📖 Similar
* Thinking in Systems by Donella Meadows is relevant because this change is about coordinating two independent automated systems through a simple feedback mechanism, which is a core systems thinking concept.
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because the image gate pattern is essentially an eventually consistent read filter between two asynchronous data pipelines.

### ↔️ Contrasting
* Move Fast and Break Things by Jonathan Taplin offers a perspective where speed matters more than polish, contrasting with our deliberate decision to slow down posting in favor of higher quality previews.

### 🔗 Related
* The Art of Readable Code by Dustin Boswell and Trevor Foucher is relevant because the implementation prioritizes readability through a single well-named pure function that clearly communicates its intent.
