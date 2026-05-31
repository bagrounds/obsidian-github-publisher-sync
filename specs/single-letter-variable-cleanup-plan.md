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

Aeson `withObject "Name" $ \v -> ...` parameters count as violations: name them `object`.
Truly abstract mathematical parameters (for example a formula argument) may remain single
letters, but text lines, paths, posts, platforms, and JSON values are domain values and
must be named.

## Incremental Plan

Each step is a self-contained PR that renames one single-letter class repository-wide,
runs the linter and the full test suite, and ships its own AI blog post. Pure renames must
not change behavior, so the existing tests are the safety net — no new tests are required
unless a rename surfaces a latent bug.

Steps 2 through 7 are tracked in GitHub issue #7088.

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
2. ⬜ **`l` in `haskell/app` and `haskell/test`**: extend the `l` → `line` rename to the
   application entry points and test suites so zero `l` lambda parameters remain anywhere.
3. ⬜ **`v` → `object`/`value`**: rename Aeson `withObject "..." $ \v ->` parameters and
   other `v` bindings, heaviest in `StaticGiscus/GraphQL.hs` and `BlogComments/GraphQL.hs`.
4. ⬜ **`c` → `character`/`comment`**: rename the `Char`-predicate lambdas and comment
   bindings.
5. ⬜ **`s` → `string`/`set`/`state`** and **`p` → `path`/`post`/`platform`**: rename per
   call-site meaning.
6. ⬜ **Remaining stragglers** (`r`, `f`, `e`, `t`, `n`, `i`, `u`, `m`, `h`, `a`): rename
   every remaining single-letter lambda parameter and binding across `haskell/src`,
   `haskell/app`, and `haskell/test`.
7. ⬜ **PureScript (`purs-ps/src`)**: rename the remaining single-letter bindings (for
   example the `\s ->` lambdas) to descriptive names.

## Definition of Done Per Step

* Zero occurrences of the targeted single letter as a lambda parameter or binding in the
  targeted scope.
* `hlint src/ app/ test/` reports zero hints from the `haskell/` directory.
* Full Haskell and PureScript test suites pass.
* The change is verified against the full `AGENTS.md` checklist before submission.
