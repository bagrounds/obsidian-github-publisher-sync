## PR Blogs
- 📝 With every PR, please generate a blog post describing your work in the ai-blog directory at the root of the repo. See some posts in https://bagrounds.org/ai-blog for prior examples.
- 🎯 Every heading, sentence, list item, and table cell in the blog post should begin with an emoji.
- 🚫 AI blog posts must never contain tags in their frontmatter or links in the content.
- 🧭 Always include breadcrumb nav links at the top of the blog post, right after the frontmatter: `[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]`
- 📚 Always include a book recommendations section at the bottom of the blog post with three sub-sections: Similar, Contrasting, and Related. Each recommendation should be in the form Title by Author followed by an explanation of why it is relevant to the post. Use this format:
```md
## 📚 Book Recommendations

### 📖 Similar
* Sapiens: A Brief History of Humankind by Yuval Noah Harari is relevant because...
* Behave: The Biology of Humans at Our Best and Worst by Robert M. Sapolsky is relevant because...

### ↔️ Contrasting
* The Philosophical Baby by Alison Gopnik offers a view on child intelligence being superior for exploration and learning

### 🔗 Related
* The Deep Learning Revolution by Terrence J. Sejnowski explores AI advancements
```
- 📖 Never put book titles in italics or quotes. Just write the title plainly.
- 🎧 Write for TTS listening. The blog owner always listens to posts via text-to-speech, so write in a style that sounds good when read aloud. Avoid relying on tables, code blocks, or back-ticked inline code to convey essential information — TTS readers skip or garble these. If a table or code block is truly necessary, always accompany it with a prose description that fully conveys the same information for audio listeners. Prefer descriptive sentences and lists over visual formatting.
- 🕐 Always use **Pacific time** (America/Los_Angeles) for the date in ai-blog filenames and frontmatter. The server clock is UTC, which can be a day ahead of Pacific in the evening. Convert with: `new Date().toLocaleDateString("en-CA", { timeZone: "America/Los_Angeles" })` or `TZ=America/Los_Angeles date +%Y-%m-%d`.
- 🔢 Always number ai-blog posts with a sequence number per day in the filename: `YYYY-MM-DD-N-slug.md` where N is the post's position that day (e.g., `2026-03-27-3-porting-internal-linking.md` is the third post on March 27). Check existing posts for that date to determine the next number.
- 📋 Use this as an example of the frontmatter template for all AI blog posts:
```md
---
share: true
aliases:
  - "2026-03-08 | 🐘 Auto-Posting to Mastodon 🤖"
title: "2026-03-08 | 🐘 Auto-Posting to Mastodon 🤖"
URL: https://bagrounds.org/ai-blog/2026-03-08-1-auto-post-mastodon
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-08 | 🐘 Auto-Posting to Mastodon 🤖
```
- 📅 The title always starts with the date in YYYY-MM-DD format.
- 🪞 The alias and title properties are exactly the same as the H1, wrapped in quotes.
- 🌐 The URL is our domain name (https://bagrounds.org) followed by the file path for that file (without the .md extension). It must match the filename exactly.
- 🐫 The file path slug is a kebab-case, emoji-stripped version of the title.

## Product & Engineering Specs
- 📋 All features must be covered by a product/engineering spec in the `specs/` directory.
- 🆕 Create or extend specs when implementing new features.
- 🐛 Amend specs when bugs are found or behavior changes.
- 🔗 The README should link to specs but not duplicate their content.

## Intelligent Planning
- 🧠 Before doing any work, always generate at least 3 initial plans. Analyze each of them and iterate on a best plan until you're very confident it'll produce a great result.

## Engineering Excellence
- 🏗️ Strong static types - inspiration from Haskell
- 🧪 Thorough test coverage, ideally with property based tests
- 🧩 Functional declarative programming patterns. Avoid for loops and conditional logic in favor of principled functional abstractions. Prefer map, reduce, filter, flatMap, and forEach to for and while loops. Never use mutable variables (const > let). Leverage function composition and expression oriented programming.
- 🔬 Prefer principled abstractions. Good ideas often come from category theory
- 🔧 Unix Philosophy & Modularity
- 📐 Domain Driven Design
- 📖 Self Documenting Code - never write comments that tell what the code is doing; always write well named functions and variables so that it's obvious
- 📊 Logging should be thorough but not spammy, easy for a human to read and understand what is happening, including decisions being made in code. Logs should be data-centric and maintain a high signal to noise ratio.

## Scientific Engineering
- 🔬 Always test your work and iterate until your tests succeed and verify that the goal has been achieved.
- 🐛 When fixing a bug, always write a failing test that reproduces the bug BEFORE writing the fix. Confirm the test fails, then apply the fix, then confirm the test passes. This is test-driven development (TDD).
- 🔴🟢 Follow the red-green cycle: red (failing test) → green (minimal fix) → refactor. Never skip the red step.

## Obsidian Vault is the Source of Truth
- 📱 The `content/` directory is a **read-only one-way sync** from the Obsidian vault on the user's phone. Never write to `content/` from GitHub Actions or scripts.
- 🚫 Never commit to the git repo from a GHA workflow. There is no reason to do this today.
- 🔄 All generated content (blog posts, images, attachments, updated frontmatter) must be persisted by syncing to the Obsidian vault using the Haskell `Automation.ObsidianSync` module (via the `run-scheduled` binary).
- 🔒 GHA workflows should use `contents: read` permissions — never `contents: write`.
