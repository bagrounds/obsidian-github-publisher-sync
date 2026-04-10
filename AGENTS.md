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
- 🔤 No abbreviations in names: write full words for all function and variable names. Legibility is more important than brevity. For example, use reflectionDate instead of rDate, postingCutoff instead of postHr.
- 🚫 No Hungarian notation: do not encode type information in variable names. The type system already tells us what a value is. For example, use today instead of todayStr, title instead of titleText.
- 🪶 No redundant suffixes: do not add type-category suffixes that merely restate what the type system already expresses. For example, use ContentDirectory instead of ContentDirectoryId, Platform instead of PlatformType.
- 🔡 No single-letter variables: unless the variable is truly abstract (such as a mathematical formula parameter), always use descriptive names. For example, use today instead of d, directory instead of x.
- 📊 Logging should be thorough but not spammy, easy for a human to read and understand what is happening, including decisions being made in code. Logs should be data-centric and maintain a high signal to noise ratio.
- 🧹 No dead code or tech debt: never leave unused parameters, ignored arguments, or dead code paths in the codebase. When a refactor makes code unnecessary, remove it immediately rather than leaving it behind with a workaround. Clean up interfaces, remove unused fields from records, and eliminate adapter shims that exist only to satisfy obsolete signatures. If it can be cleaned up now, clean it up now.

## Scientific Engineering
- 🔬 Always test your work and iterate until your tests succeed and verify that the goal has been achieved.
- 🐛 When fixing a bug, always write a failing test that reproduces the bug BEFORE writing the fix. Confirm the test fails, then apply the fix, then confirm the test passes. This is test-driven development (TDD).
- 🔴🟢 Follow the red-green cycle: red (failing test) → green (minimal fix) → refactor. Never skip the red step.

## Haskell Linting
- 🧹 Always run `hlint src/ app/ test/` from the `haskell/` directory before finishing work. CI enforces zero hlint hints (warnings and suggestions) — any hint fails the build.
- 🔧 Fix all hlint hints before pushing. Common hints include using `catMaybes` instead of `mapMaybe id`, using `isJust`/`isNothing` instead of comparison with `Nothing`, and using `Data.Bifunctor.second` instead of manual tuple mapping.
- 📦 If hlint is not installed locally, install it with `apt-get install -y hlint` or `cabal install hlint`.

## Haskell Architecture Best Practices
- 🧅 Functional Core, Imperative Shell: keep domain logic in pure functions, push IO to the edges. Never add IO to a function signature unless it truly needs side effects.
- 🧊 Separate data from behavior: model domain concepts as pure data types and write pure functions over them. Avoid embedding IO callbacks in data structures.
- 🏷️ Domain types over primitives: prefer newtypes and ADTs over raw Text, String, or Int for domain concepts like URLs, titles, dates, and platform limits. This prevents mixing up values that share a representation. When extracting a pure function, always introduce proper domain types in the same change — never extract a pure function with primitive Text parameters when a domain type exists or should be created.
- 🔒 Closed sets as ADTs: when a value comes from a fixed, known set (such as content directories, platform names, or task identifiers), model it as a sum type with one constructor per variant. Never use raw Text for a closed set. Include round-trip functions (toText and fromText) and derive Bounded and Enum for exhaustive testing.
- 🏠 Domain-specific modules: define each function in the module that owns its domain concept. Never import domain logic from an unrelated module. For example, reflection-related functions belong in a Reflection module, not in SocialPosting or InternalLinking. Keep modules focused, domain-specific, and orthogonal.
- 📦 Smart constructors: use validated newtypes with smart constructors for values with invariants (such as similarity thresholds between zero and one or valid URLs).
- 🚫 Dissolve impossible states: when a function requires at least one element, use NonEmpty instead of a list with a runtime check. Never add a runtime error for an empty list when NonEmpty encodes the constraint at the type level. Prefer Data.List.NonEmpty from base for non-empty guarantees.
- 🔀 Explicit error types: prefer Either with domain-specific error ADTs over throwing exceptions or returning empty defaults. Reserve exceptions for truly unrecoverable failures.
- 📖 ReaderT for shared context: when multiple functions need the same environment (Manager, config, vault path), prefer a ReaderT-based context over threading individual parameters.
- 🧩 Small focused modules: each module should do one thing. Break large orchestrators into smaller feature-specific modules.
- 🔬 Testability by design: if a function can be pure, make it pure. Pass time, randomness, and other ambient values as parameters so tests can be deterministic.
- 🔧 Result types over Booleans: when a function checks eligibility, prefer returning a descriptive result type (such as Eligible or IneligibleBecause reason) over bare Bool to preserve decision context.
- 📐 Vertical slices: every architecture improvement must deliver types, logic, tests, and documentation together. Never separate pure extraction from domain type introduction — they are one concern.
- 🕐 Pacific time for dates: always work in Pacific time. When obtaining the current date, convert from UTC to Pacific immediately and use Day or equivalent domain types throughout. Never pass date strings between functions.
- 📦 Library-developer module design: design every module as if it could become its own package. Each feature module should be self-contained with its own types, constants, and logic. Never group unrelated types into a shared module just because they share a structural pattern (such as putting all credential types together or all embed types together). Ask: if an arbitrary project wanted to use just this one feature (for example, only Bluesky posting), which modules would it need? Minimize that set. When removing or replacing a feature, deleting its module and updating a few imports should be sufficient — no unrelated modules should require changes.
- 🔀 Vertical over horizontal slicing: organize modules by feature or domain concept, not by code artifact kind. A module named by feature (such as Platforms.Twitter containing Credentials, limits, sectionHeader, PostResult, and the posting API) is better than modules named by artifact kind (such as a Credentials module grouping credentials from unrelated platforms, or a Constants module grouping constants from unrelated features).
- 🏷️ Qualified imports for feature modules: import feature modules qualified and use short names within the module (such as Credentials instead of TwitterCredentials, limits instead of twitterLimits). Consumers write `import qualified Automation.Platforms.Twitter as Twitter` and reference `Twitter.Credentials`, `Twitter.limits`, `Twitter.post`. This folds the namespace into the module qualifier, avoids redundant prefixes, and makes code read like natural language. Reserve unqualified imports for truly shared types (such as PlatformLimits, Secret, Url) and for modules where field names do not conflict.

## Obsidian Vault is the Source of Truth
- 📱 The `content/` directory is a **read-only one-way sync** from the Obsidian vault on the user's phone. Never write to `content/` from GitHub Actions or scripts.
- 🚫 Never commit to the git repo from a GHA workflow. There is no reason to do this today.
- 🔄 All generated content (blog posts, images, attachments, updated frontmatter) must be persisted by syncing to the Obsidian vault using the Haskell `Automation.ObsidianSync` module (via the `run-scheduled` binary).
- 🔒 GHA workflows should use `contents: read` permissions — never `contents: write`.
