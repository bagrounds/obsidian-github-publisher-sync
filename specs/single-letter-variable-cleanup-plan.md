# Single-Letter Variable Cleanup Plan

## Why This Plan Exists

With the [abbreviation cleanup](abbreviation-cleanup-plan.md) complete, a fresh
compliance audit against `AGENTS.md` found the single most common remaining aberration
across the active source code is the **No single-letter variables** rule:

> 🔡 No single-letter variables: unless the variable is truly abstract (such as a
> mathematical formula parameter), always use descriptive names. For example, use
> `today` instead of `d`, `directory` instead of `x`.

Single-letter lambda parameters and bindings are now the dominant rule violation across
`haskell/src`, `haskell/app`, and `haskell/test`. This document is the single source of
truth for cleaning them up across future PRs.

## Evidence

Whole-word single-letter lambda parameters across `haskell/src`, `haskell/app`, and
`haskell/test` at the time of the audit (roughly 139 occurrences total). The most common
offenders by letter:

* `c` — 27 occurrences (usually a character or comment value)
* `v` — 21 occurrences (usually an Aeson object/value in `withObject "..." $ \v ->`)
* `s` — 21 occurrences (usually a string or accumulating set/state)
* `p` — 19 occurrences (usually a path, post, or platform)
* `l` — 15 occurrences (usually a line of text, occasionally a link)
* smaller offenders: `r`, `f`, `e`, `t`, `n`, `i`, `u`, `m`, `h`, `a`

Worst concentrations:

* `haskell/test/Automation/SocialPostingTest.hs` — 11
* `haskell/src/Automation/StaticGiscus/GraphQL.hs` — 10
* `haskell/src/Automation/ReflectionTitle.hs` — 9
* `haskell/src/Automation/BlogComments/GraphQL.hs` — 8
* `haskell/src/Automation/SocialPosting/ContentDiscovery.hs` — 6
* `haskell/src/Automation/InternalLinking.hs` — 6

The dominant pattern is `filter`/`break`/`fmap`/`foldr` lambdas over lists of text lines,
where a fuller name such as `line` makes the predicate obvious at the call site.

## Naming Guidance

Each single letter should be renamed to a descriptive name based on what the value holds
at that call site, not a mechanical one-to-one mapping. Common cases:

| Single letter | Descriptive name (context dependent) |
| --- | --- |
| `l` | `line` (a line of text), `linkPath`/`linkedPath` (a link target) |
| `v` | `object` / `value` (an Aeson value being parsed) |
| `c` | `character` (a `Char`), `comment` (a comment record) |
| `s` | `string`, `set`, or `state` depending on what it carries |
| `p` | `path`, `post`, or `platform` depending on what it carries |
| `e` | `element` / `entry` (a list element), `event` |
| `i` | `index` |
| `n` | a name describing the value (`neighborPath`, `count`, ...) |

Aeson `withObject "Name" $ \v -> ...` parameters count as violations: name them `value`
(or `object` where that name is free — note `Json.hs` already exports an `object` smart
constructor, so modules importing it must use `value` to avoid shadowing under `-Werror`).
Truly abstract mathematical parameters (for example a formula argument) may remain single
letters, but text lines, paths, posts, platforms, and JSON values are domain values and
must be named.

## Incremental Plan

Each step is a self-contained PR that renames one single-letter class repository-wide,
runs the linter and the full test suite, and ships its own AI blog post. Pure renames must
not change behavior, so the existing tests are the safety net — no new tests are required
unless a rename surfaces a latent bug.

Steps 2 through 4 were tracked in GitHub issue #7090. Step 5 followed in its own PR. The
remaining steps 6 and 7 are tracked in a follow-up ticket. 

1. ✅ **`l` → `line` (and `linkPath`/`linkedPath` for links, `left`/`right` for an
   operator)** (done): renamed every single-letter `l` binding across `haskell/src` —
   lambda parameters as well as recursive-helper and pattern arguments — to a descriptive
   name. Text lines became `line`; link targets in the breadth-first content/link
   discovery became `linkedPath`/`linkPath`; the operands of the local `<|>` operator in
   `Text.hs` became `left`/`right`. Co-located single letters in a touched lambda were
   fixed in the same change (`\l i ->` became `\line index ->`, and a stray `acc` became
   `accumulated` in `BlogImage/TitleExtraction.hs`). Pure rename — the `-Werror` build is
   clean and all 2025 Haskell tests still pass. Zero whole-word `l` bindings remain in
   `haskell/src`.
2. ✅ **`l` in `haskell/app` and `haskell/test`** (done): the audit found that no
   single-letter `l` lambda parameter or binding remained in `haskell/app` or
   `haskell/test` once step 1 finished, so this step was already satisfied. Confirmed and
   recorded — zero whole-word `l` bindings remain anywhere in the Haskell sources, app, or
   tests.
3. ✅ **`v` → `value`** (done): renamed every single-letter `v` binding across `haskell/src`
   and `haskell/test` to `value` — the Aeson `withObject "..." $ \v ->` parameters in
   `BlogComments/GraphQL.hs`, `StaticGiscus/GraphQL.hs`, and `GcpAuth.hs`, the `FromValue`
   instance arguments and combinator helpers in `Json.hs`, and the key/value-pair lambdas
   in `BlogImage.hs`, `InternalLinking.hs`, `Platforms/Twitter.hs`, `Frontmatter.hs`, and
   `BlogImage/Eligibility.hs`. The plan's first choice of `object` for the Aeson parameters
   would have shadowed the existing `object` smart constructor exported from `Json.hs`
   (a `-Wname-shadowing`/`-Werror` build error), so the equally honest `value` was used
   throughout. `v` characters inside string literals (sample JSON keys, a shell `grep -v`
   flag, a `?v=1` query parameter) are data, not bindings, and were left untouched. Pure
   rename — the `-Werror` build is clean and all 2025 Haskell tests still pass.
4. ✅ **`c` → `character`/`comment`/`candidate`/`value`** (done): renamed every
   single-letter `c` binding across `haskell/src` and `haskell/test` (the `haskell/app`
   tree had none). The dominant case was `Char` predicates and folds — the `\c ->`
   lambdas, `(c : characters)` recursive arguments, and `escapeChar`/`isEmoji`-style
   helpers in `Text.hs`, `Json.hs`, `Frontmatter.hs`, `BlogImage.hs`, `ReflectionTitle.hs`,
   `Html.hs`, `Bluesky.hs`, and the link/markdown parsers — all became `character`. Comment
   records became `comment` (`toStaticComment`/`renderStaticComment` in `StaticGiscus.hs`,
   `formatComment` in `BlogPrompt.hs`). Link-match records became `candidate`
   (`sortByDateDesc` in `BlogImage.hs`, the `CandidateDiscovery` self-link filter, and the
   `(candidate:_)` case arms across `InternalLinkingTest.hs` and
   `CandidateDiscoveryTest.hs`). The polymorphic right-hand value of the `mapLeft` helpers
   in `BlogImage/Provider.hs` and `GoogleAnalytics.hs` became `value`. `c` characters inside
   string literals (sample paths such as `a/b/c`, `?v=1`-style fixtures, the `-c` bash flag)
   and the abstract `c` type variables in the `mapLeft` signatures are data and abstract
   parameters, not bindings, and were left untouched. Pure rename — the `-Werror` build is
   clean, `hlint src/ app/ test/` reports no hints, and all 2025 Haskell tests still pass.
5. ✅ **`s` → `string`/`set`/`state`** and **`p` → `path`/`post`/`platform`** (done):
   renamed every single-letter `s` and `p` binding across `haskell/src`, `haskell/app`, and
   `haskell/test` to a descriptive name chosen per call-site meaning. The dominant `s` cases
   were unpacked `String` values fed to regex matches (`T.unpack` bindings in `Markdown.hs`,
   `Eligibility.hs`, `Masking.hs`, the `findMatch`/`parseLinks` helpers in
   `CandidateDiscovery.hs` and the two `LinkExtraction.hs` modules) and the `QC.ASCIIString`
   QuickCheck lambdas across the test suite — all became `string`; the trimmed-title binding
   in `BlogPrompt.hs` became `stripped`, the JSON exponent sign in `Json.hs` became
   `exponentSign`, the parsed Bluesky session became `session`, the deduplicating grounding
   source in `Gemini.hs` became `existing`, the visited-link accumulator in `LinkExtraction.hs`
   became `visitedSet`, and the `BlogSeriesConfig` records in `BlogSeriesConfigTest.hs` became
   `series`. The `p` cases became `path` (file paths), `pid` (a process id in `ObsidianSync.hs`),
   `predicate` (the `findM` callback in `Scheduler.hs`), `pathname` (`normalizePathname` in
   `StaticGiscus.hs`), `mostRecentPost` (the latest series post in `TaskRunners.hs`),
   `targetPlatform` (the platform-filter lambdas in `ContentDiscovery.hs`, where `platform` is
   already a record accessor and would shadow under `-Werror`), `provider` (the
   `ImageProviderConfig` lambdas and pattern binds in the BlogImage tests), and `resultPath`
   (the result-path predicates in `SocialPostingTest.hs`). `s` and `p` characters inside string
   literals (sample paths, slugs, regex fixtures, shell flags) are data, not bindings, and were
   left untouched. Pure rename — the `-Werror` build is clean, `hlint src/ app/ test/` reports
   no hints, and all 2025 Haskell tests still pass.
6. ✅ **Remaining stragglers** (`r`, `f`, `e`, `t`, `n`, `i`, `u`, `m`, `h`, `a`) (done):
   renamed every remaining single-letter lambda parameter, function-argument binding, and
   `let`/`where` binding across `haskell/src`, `haskell/app`, and `haskell/test`. Text
   parameters in stripping/parsing helpers became `text` (the dominant case, across
   `BlogImage/Markdown.hs`, `ReflectionTitle.hs`, `Frontmatter.hs`, `BlogPrompt.hs`,
   `BlogSeries.hs`, `BlogImage/Eligibility.hs`, `BlogImage/TitleExtraction.hs`,
   `Gemini.hs`, `Html.hs`, `Json.hs`, `Platforms/Bluesky.hs`, the
   `InternalLinking/CandidateDiscovery.hs` and `InternalLinking/Gemini.hs` helpers, both
   `LinkExtraction.hs` modules, `Text.hs`, and the matching test helpers). File-path
   predicates became `file` (`isPostFile`, `isImageFile`, `isDateFile`, `isTodayMarkdown`,
   `isRegenerable`, the `htmlFiles`/`mdFiles`/`dateFiles` filter lambdas in
   `StaticGiscus.hs`, `InternalLinking/CandidateDiscovery.hs`, `Reflection.hs`). The
   `withObject`/`parseMaybe` parser functions in `Json.hs` became `parser`. The two
   `mapLeft` value equations in `BlogImage/Provider.hs` and `GoogleAnalytics.hs` became
   `mapLeft transform (Left leftValue)` while keeping their type-variable signatures
   intact. The Aeson-style `\e -> failTask $ "Invalid display title: " <> e` lambda in
   `TaskRunners.hs` became `\failure ->` per the repo rule that `err` must NOT be renamed
   to `error` (Prelude clash). Index-style integer parameters in `AiBlogLinks.hs`,
   `Text.hs`, `ReflectionTitle.hs`, and `InternalLinking/Gemini.hs` became `index`. The
   `n` parameter in `GcpAuth.integerBitLength` became `value`, and the `n` in
   `GcpAuth.hexChar` became `nibble`. Sort-comparator lambdas in `InternalLinking.hs` and
   `InternalLinking/CandidateDiscovery.hs` became `\leftCandidate rightCandidate`. Other
   per-call-site renames: `\a -> Gql.login a == pu` → `\author`, `\h -> ... breakOn h
   content` → `\heading`, `foldr (\a b -> a <> "\n" <> b)` → `\first rest`, `\u -> if
   T.null u then Nothing` → `\user`, `\m -> ... Gemini.modelToText m` → `\model`,
   `dropWhile (\r -> T.isPrefixOf "  -" r)` → `\aliasLine`, `let t = T.strip title` →
   `stripped` (matching step 5 precedent), `case ... of n -> intersectionSize / n` →
   `nonZeroUnion`, `let h = pacificHour utc; in h >= 0 && h <= 23` → `hour`, plus the
   collapseStep helper's `t'` became `collapsed`. Type variables in signatures, class
   heads, and instance heads (for example `safeIO :: IO a -> IO (Either Text a)`,
   `class FromValue a where`, `Monad m => ...`) are abstract per AGENTS.md and were left
   untouched. Letters inside string literals, character literals, regex fixtures, and
   sample paths are data and were left untouched. Pure rename — the `-Werror` build is
   clean and all 2025 Haskell tests still pass.
7. ✅ **PureScript (`purs-ps/src`)** (done): renamed every remaining single-letter
   lambda parameter, function-argument binding, and case-arm pattern binding across
   `purs-ps/src` and `purs-ps/test`. The `\s ->` lambdas in `TestHook.purs` that read
   the live session through `readSession` became `\session ->`. The
   `millisecondsBetween a b` formula in `Recording/Math.purs` became
   `millisecondsBetween later earlier` (and its docstring was updated to match);
   `takeEndArray n xs` in `Recording/Reducer.purs` became
   `takeEndArray count items`. The reducer's start branch `Just t -> Just t` for the
   sticky `firstStartedAt` became `Just existingStart -> Just existingStart`. In the
   test suite, `stuffEntries n entry entries` became `stuffEntries count …`, the
   property-test helpers `containsDigit s = Array.any (\d -> …)` became
   `containsDigit text = Array.any (\digit -> …)`, and the `Just t`/`Just e`/`Just c`
   pattern binds for the persisted-session round-trip and caption assertions became
   `Just startedAt`/`Just environment`/`Just caption`. Type variables in `forall`
   signatures (`forall m. Clock m =>`, `forall a. Int -> Array a -> Array a`,
   `newtype AppM a = …`) are abstract per AGENTS.md and were left untouched. Single
   letters inside string literals, regex fixtures, and digit/character sample data
   are data, not bindings, and were left untouched. Pure rename — `npm run test:ps`
   reports zero errors and all 900 PureScript unit tests still pass; the Word Meter
   bundle builds clean.

## Definition of Done Per Step

* Zero occurrences of the targeted single letter as a lambda parameter or binding in the
  targeted scope.
* `hlint src/ app/ test/` reports zero hints from the `haskell/` directory.
* Full Haskell and PureScript test suites pass.
* The change is verified against the full `AGENTS.md` checklist before submission.
