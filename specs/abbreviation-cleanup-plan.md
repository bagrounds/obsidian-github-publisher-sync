# Abbreviation Cleanup Plan

## Why This Plan Exists

A compliance audit against `AGENTS.md` found that the single most common aberration
across the active source code is the **No abbreviations in names** rule:

> 🔤 No abbreviations in names: write full words for all function and variable names.
> Legibility is more important than brevity.

Abbreviated identifiers are far more frequent than any other rule violation
(single-letter variables, narrating comments, and banner comments are all an order of
magnitude less common). This document is the single source of truth for cleaning them up
across future PRs.

## Evidence

Whole-word identifier counts across `haskell/src`, `haskell/app`, `haskell/test`, and
`purs-ps/src` at the time of the audit:

* `err` — 180 occurrences (the dominant offender)
* `dir` — 143 occurrences
* `msg` — 42 occurrences
* `ctx` — 29 occurrences
* `req` — 21 occurrences
* smaller offenders: `tmp` (5), and stray `idx`, `num`, `str`

Worst concentrations for `err`:

* `haskell/src/Automation/Platforms/Bluesky.hs` — 19
* `haskell/src/Automation/TaskRunners.hs` — 16
* `haskell/src/Automation/SocialPosting.hs` — 13
* `haskell/src/Automation/BlogImage.hs` — 10
* `haskell/test/Automation/GoogleAnalyticsTest.hs`, `GeminiTest.hs` — 10 each

The dominant pattern is `Left err ->` arms in `Either` handling, where a fuller name such
as `failure` makes the decision context clearer at the call site.

## Target Renamings

| Abbreviation | Full word to use |
| --- | --- |
| `err` | `failure` (or a domain-specific name such as `parseFailure`, `httpFailure`) |
| `dir` | `directory` |
| `msg` | `message` |
| `ctx` | `context` |
| `req` | `request` |
| `tmp` | `temporary` (or a name describing what the value holds) |

Note: in Haskell, `err` must **not** become `error`, because `error :: String -> a` is in
`Prelude`. Use `failure` or a domain-specific error name instead. Where the bound value is
already a domain error ADT, name it after the concept it carries (for example
`classifyException postFailure`).

## Incremental Plan

Each step is a self-contained PR that renames one abbreviation class repository-wide,
runs the linter and the full test suite, and ships its own AI blog post. Pure renames must
not change behavior, so the existing tests are the safety net — no new tests are required
unless a rename surfaces a latent bug.

1. ✅ **`err` → `failure`** (done): highest-impact, mechanical. Renamed every `Left err`
   arm and every `err`-named binding across `haskell/src`, `haskell/app`, and
   `haskell/test` to `failure`. Pure rename — all 2021 Haskell tests still pass and the
   `-Werror` build is clean. Zero whole-word `err` identifiers remain.
2. ✅ **`dir` → `directory`** (done): renamed every standalone `dir` parameter and
   binding across `haskell/src` and `haskell/test`, including `isDir` → `isDirectory`
   in `SocialPosting.hs` and `ObsidianSync.hs`. Pure rename — all Haskell tests still
   pass and the `-Werror` build is clean. Zero whole-word `dir` identifiers remain.
3. ✅ **`msg` → `message`** and **`ctx` → `context`** (done): renamed every standalone
   `msg` parameter and binding across `haskell/src`, `haskell/app`, and `haskell/test`
   to `message` (or a domain-specific name like `responseMessage` where `message` was
   already in scope). Renamed every `ctx` binding to `context`. Pure rename — zero
   whole-word `msg` or `ctx` identifiers remain as variable names.
4. ✅ **`req` → `request`** and remaining stragglers (`tmp`, `idx`, `num`, `str`) (done):
   renamed every standalone `req`/`resp` parameter and binding across `haskell/src` and
   `haskell/app` to `request`/`response`, including compound forms (`httpReq` →
   `httpRequest`, `headReq` → `headRequest`, `fallbackReq` → `fallbackRequest`,
   `gqlResp` → `graphqlResponse`, `tokenResp` → `tokenResponse`). Also renamed compound
   `Msg` forms (`logMsg` → `logMessage`, `errMsg` → `errorMessage`), `suf` → `suffix`,
   `str` → `string`, `idx` → `index`, `num` → `numberText`, and `_err` → `_failure`.
   No `tmp` variable names were found — all five occurrences were string literals
   (filesystem paths), not identifiers. Pure rename — all 2021 Haskell tests still pass,
   hlint reports zero hints, and the `-Werror` build is clean.

   **Note:** Compound `Dir` identifiers (`vaultDir`, `contentDir`, `obsidianDir`, etc.)
   were intentionally excluded from this step due to their breadth (75+ `vaultDir`
   occurrences alone across 10+ files including app entry points and config records). A
   separate follow-up issue has been filed to rename these systematically.

## Definition of Done Per Step

* Zero occurrences of the targeted abbreviation as a whole-word identifier.
* `hlint src/ app/ test/` reports zero hints from the `haskell/` directory.
* Full Haskell and PureScript test suites pass.
* The change is verified against the full `AGENTS.md` checklist before submission.
