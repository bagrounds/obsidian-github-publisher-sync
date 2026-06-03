## Compliance Checklist
- ✅ Use AGENTS.md as a checklist to verify your changes. A green build and passing tests are not done; compliance with these rules is part of done.
- 🐑 Never let neighboring code override a written rule. If existing code models a forbidden pattern, follow this file, not the surrounding style — and fix the bad pattern when it sits in lines you are already touching.

## PR Blogs
- 📝 With every PR, generate a blog post describing your work in the ai-blog directory at the root of the repo. See https://bagrounds.org/ai-blog for examples.
- 🎯 Every heading, sentence, list item, and table cell begins with an emoji.
- 🚫 AI blog posts never contain tags in their frontmatter or links in the content.
- 🧭 Include nav links after frontmatter: `[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]`
- 📚 Include book recommendations at the end in this format:
```md
## 📚 Book Recommendations

* Sapiens: A Brief History of Humankind by Yuval Harari
* Behave: The Biology of Humans at Our Best and Worst by Robert Sapolsky
* The Philosophical Baby by Alison Gopnik
* The Deep Learning Revolution by Terrence Sejnowski
```
- 📖 Never put book titles in italics or quotes.
- 🎧 Write for TTS listening. Avoid tables, code blocks, and back-ticked inline code for essential information — TTS garbles these. Prefer descriptive sentences and lists over visual formatting.
- 🕐 Always use Pacific time for the date.
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
- 🌐 The URL is our domain name (https://bagrounds.org) followed by the file path (without the .md extension). It must match the filename.
- 🐫 The file path slug is a kebab-case, emoji-stripped version of the title.

## Product & Engineering Specs
- 📋 All features are covered by a product/engineering spec in the `specs/` directory.
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
- 🪪 No mechanism decorators on identifiers (`Impl`, `Internal`, `Helper`, `Raw`, `Unsafe`): name the thing, not how it is implemented — the type system, module boundary, and `foreign import` keyword already say what kind of thing it is. A wrapper that adds behavior gets its own concept-level name (`currentTimeMillis`, not `nowMsImpl` alongside `nowMs`). Applies to every language in the repo.
- 🚫 No Hungarian notation: do not encode type information in variable names. The type system already tells us what a value is. For example, use today instead of todayStr, title instead of titleText.
- 🪶 No redundant suffixes: do not add type-category suffixes that merely restate what the type system already expresses. For example, use ContentDirectory instead of ContentDirectoryId, Platform instead of PlatformType.
- 🔡 No single-letter variables: unless the variable is truly abstract (such as a mathematical formula parameter), always use descriptive names. For example, use today instead of d, directory instead of x.
- 📊 Logging should be thorough but not spammy: data-centric, human-readable, high signal-to-noise, and clear about the decisions the code is making.
- 🧹 No dead code or tech debt: never leave unused parameters, ignored arguments, or dead code paths. When a refactor makes code unnecessary — record fields, interfaces, adapter shims satisfying obsolete signatures — remove it now rather than working around it.
- 🚫 No section-demarcating comments: do not use banner-style comment blocks (such as lines of dashes with a section title) to separate code within a module. Well-named functions and good module scoping make these unnecessary. If a section feels like it needs a heading, it probably belongs in its own module.
- 🚫 No re-exports: each module should only export symbols it defines. Consumers should import directly from the module that defines the functionality they need. Do not re-export symbols from sub-modules to create a facade — this adds unnecessary complexity and obscures where functionality is defined.

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
- 🔇 Never silently swallow errors: every fallible boundary (FFI, IO, network, parsing, third-party API) must surface failure in a typed return value (Either with a domain-specific error ADT, or an equivalent error encoding for the language). Never let an exception, parse failure, or unavailable capability collapse into a default value, a Boolean, or a no-op without recording the error in the return type and logging it in the diagnostics or audit trail. This rule applies in every language in the repository — Haskell, PureScript, TypeScript, JavaScript, and JS FFI shims.
- 📖 ReaderT for shared context: when multiple functions need the same environment (Manager, config, vault path), prefer a ReaderT-based context over threading individual parameters.
- 🧩 Small focused modules: each module should do one thing. Break large orchestrators into smaller feature-specific modules.
- 🔬 Testability by design: if a function can be pure, make it pure. Pass time, randomness, and other ambient values as parameters so tests can be deterministic.
- 🔧 Result types over Booleans: when a function checks eligibility, prefer returning a descriptive result type (such as Eligible or IneligibleBecause reason) over bare Bool to preserve decision context.
- 📐 Vertical slices: every architecture improvement must deliver types, logic, tests, and documentation together. Never separate pure extraction from domain type introduction — they are one concern.
- 🕐 Pacific time for dates: always work in Pacific time. When obtaining the current date, convert from UTC to Pacific immediately and use Day or equivalent domain types throughout. Never pass date strings between functions.
- 📦 Library-developer module design: design every module as if it could become its own package — self-contained with its own types, constants, and logic. Never group unrelated types into a shared module just because they share a structural pattern. Removing a feature should mean deleting its module and updating a few imports, with no unrelated modules requiring changes.
- 🔀 Vertical over horizontal slicing: organize modules by feature or domain concept, not by code artifact kind. A module named by feature (such as Platforms.Twitter containing Credentials, limits, sectionHeader, PostResult, and the posting API) is better than modules named by artifact kind (such as a Credentials module grouping credentials from unrelated platforms, or a Constants module grouping constants from unrelated features).
- 🏷️ Qualified imports for feature modules: import feature modules qualified and use short names within them (`Credentials`, not `TwitterCredentials`). Consumers write `import qualified Automation.Platforms.Twitter as Twitter` and reference `Twitter.Credentials`, `Twitter.post`. Reserve unqualified imports for truly shared types (PlatformLimits, Secret, Url) and modules whose field names do not conflict.

## Obsidian Vault is the Source of Truth
- 📱 The `content/` directory is a **read-only one-way sync** from the Obsidian vault on the user's phone. Never write to `content/` from GitHub Actions or scripts.
- 🚫 Never commit to the git repo from a GHA workflow. There is no reason to do this today.
- 🔄 All generated content (blog posts, images, attachments, updated frontmatter) must be persisted by syncing to the Obsidian vault using the Haskell `Automation.ObsidianSync` module (via the `run-scheduled` binary).
- 🔒 GHA workflows should use `contents: read` permissions — never `contents: write`.

## Launching a New Auto Blog Series
- 🚀 When a PR adds a new auto blog series, follow every step in the [launch checklist](specs/blog-series-launch-checklist.md). The checklist covers everything from the JSON config to the documentation updates that keep the README, specs, and scheduled-tasks tables in sync.
- 🔗 The auto-discovery architecture means **zero Haskell code changes** are needed, but several documentation files must be updated to reflect the new series.
- 📋 The checklist is the single source of truth for what belongs in a launch PR. If something is missing from the checklist, update it.

## Root Cause Analysis
- 🚫 Never guess or invent a root cause. If you do not know what caused a bug, say so explicitly.
- 🔍 Show all the evidence you have: logs, timestamps, file diffs, version history, and GHA run data.
- 🧪 Submit the most plausible hypotheses, each with a clear justification grounded in the evidence.
- 📊 Rank hypotheses by plausibility and explain what evidence supports or contradicts each one.
- 🔬 When possible, write a failing test that reproduces the exact conditions of the bug before proposing a fix.
- 🛡️ If the root cause is uncertain, prioritize defensive fixes that prevent the class of failure regardless of cause.
