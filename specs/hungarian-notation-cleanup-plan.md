# Hungarian Notation Cleanup Plan

## Why This Plan Exists

With the [mechanism decorator cleanup](mechanism-decorator-cleanup-plan.md) complete, a
fresh compliance audit against `AGENTS.md` found that the next most common naming
aberration across the active source code is the **No Hungarian notation** rule:

> 🚫 No Hungarian notation: do not encode type information in variable names. The type
> system already tells us what a value is. For example, use today instead of todayStr,
> title instead of titleText.

The audit found 15 clear violations across 8 files. This document is the single source of
truth for cleaning them up across future PRs.

## Evidence

Whole-word identifiers ending in a type-encoding suffix across `haskell/src`,
`haskell/app`, and `purs-ps/src` at the time of the audit:

* `*Str` — 10 occurrences across 6 files (`yStr`, `mStr`, `dStr` in BlogPrompt.hs;
  `hourStr`, `taskStr` in CliArgs.hs; `taskStr` in RunScheduled.hs; `numStr` in
  Json.hs; `baselineStr` in ObsidianSync.hs; `numberStr` in DailyUpdates.hs;
  `messageStr` in Gemini.hs).
* `*Text` (type-encoding) — 1 occurrence (`numberText` in DailyUpdates.hs where
  the value is a digit substring parsed from an emoji line — the name encodes that it
  is Text, not what it represents).
* `*Array` — 2 occurrences (`metricsArray`, `dimsArray` in GoogleAnalytics.hs where
  the variables hold parsed JSON arrays — the type already says Array).
* `*List` — 1 occurrence (`modelsList` in AiFiction.hs where the variable is the
  list conversion of a NonEmpty — the type already says list).
* `*Map` (type-encoding in variable names) — debatable but present in `commentsMap`,
  `seriesMap`, `noteMap`, `envMap`, `imageEnvMap`, `parentMap` across StaticGiscus.hs,
  TaskRunners.hs, SocialPosting.hs, BlogSeries.hs, and ContentDiscovery.hs. These are
  tracked as a secondary tier because renaming them requires choosing indexed-plural or
  by-key names to avoid collisions with existing list-typed variables of the same base
  name.

No occurrences of `*Bool`, `*Int`, or `*Number` as type-encoding suffixes were found
in source identifiers.

## Naming Guidance

Each suffix should be replaced by a name that describes what the value represents at
the call site, not what type it is.

| Current | Rename | Rationale |
| --- | --- | --- |
| `yStr`, `mStr`, `dStr` | `yearPart`, `monthPart`, `dayPart` | The values are string fragments of a date being parsed — they represent the year, month, and day portions. |
| `hourStr` | `hour` | The value is the CLI hour argument before parsing. |
| `taskStr` (CliArgs + RunScheduled) | `task` | The value is the CLI task argument before parsing. |
| `numStr` | `numberLiteral` | The value is the assembled numeric literal being parsed. |
| `baselineStr` | `baseline` | The value is the raw baseline file content before parsing. |
| `numberStr` | `digits` | The value is the leading digit characters from a stats line. |
| `messageStr` | drop entirely (inline `T.unpack message`) | The binding just unpacks the existing `message` parameter — removing it eliminates the indirection. |
| `numberText` | `digits` | Same as `numberStr` — leading digit characters from an emoji line. |
| `metricsArray` | `metrics` | The value is the parsed metric values structure. |
| `dimsArray` | `dimensions` | The value is the parsed dimension values structure. |
| `modelsList` | `models` | The value is the list of fiction models for rotation. |

### Secondary tier (Map variables)

| Current | Rename | Rationale |
| --- | --- | --- |
| `commentsMap` | `commentsByPathname` | Describes the indexing key, not the container type. |
| `seriesMap` | `seriesByIdentifier` | Describes the indexing key. |
| `noteMap` | `groupedByNote` | Describes what the grouping represents. |
| `envMap` / `imageEnvMap` | `environment` / `imageEnvironment` | The values are environment variable lookups. |
| `parentMap` | `parentsByNode` | Describes the relationship the map encodes. |

## Incremental Plan

Each step is a self-contained PR that removes one suffix class, runs the linter and
the full test suite, and ships its own AI blog post. Pure renames must not change
behavior, so the existing tests are the safety net.

1. [x] **`*Str` → concept-level name** in `haskell/src` and `haskell/app` (10
   occurrences across 7 files): rename every `*Str`-suffixed identifier to a name
   that describes the value at the call site. The `messageStr` binding in
   `Gemini.hs` can be inlined entirely since it merely unpacks the already-named
   `message` parameter.

2. [x] **`*Text` / `*Array` / `*List` → concept-level name** (4 occurrences across
   3 files): rename `numberText` → `digits`, `metricsArray` → `metrics`,
   `dimsArray` → `dimensions`, `modelsList` → `models`.

3. [ ] **`*Map` → indexed-plural or by-key name** (secondary tier, ~6 unique
   variable names across 5+ files): rename each `*Map` variable to a name that
   describes the indexing relationship. This step has broader scope because several
   of these variables appear in type aliases, function signatures, and multiple
   call sites.

## Definition of Done Per Step

* Zero occurrences of the targeted suffix as a type-encoding identifier suffix in
  the targeted scope.
* `hlint src/ app/ test/` reports zero hints from the `haskell/` directory.
* `npm run test:ps` and `cabal test` both pass.
* The change is verified against the full `AGENTS.md` checklist before submission.
