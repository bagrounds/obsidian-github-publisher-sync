# Haskell Architecture Improvement Plan

## Current State Summary

The Haskell codebase was ported from TypeScript and inherited several patterns that don't leverage Haskell's strengths for safety and correctness. The code works well and has good test coverage (800+ tests), but can be improved to better prevent accidental breakage and improve modularity.

### Key Issues Identified

1. **IO pervasive**: Many functions use IO when their core logic is pure. They read the clock, environment, or file system in the middle of domain logic rather than receiving these values as parameters.
2. **Text everywhere**: Domain concepts like URLs, titles, dates, and file paths are represented as raw `Text`, making it possible to accidentally swap or misuse them.
3. **God module**: `RunScheduled.hs` is 913 lines with 33 imports and acts as an orchestration monolith.
4. **IO callbacks in data structures**: `ImageProviderConfig` embeds IO callback functions, making testing difficult and tightly coupling data to behavior.
5. **Inconsistent error handling**: Mix of `Either Text`, `Maybe`, exceptions, silent empty-string returns, and `error` calls.
6. **No shared context pattern**: Manager, repo root, vault dir, and API keys are threaded as separate parameters through many functions.

## Architecture Vision

Follow the **Functional Core, Imperative Shell** pattern:
- Pure domain logic in the core, tested deterministically
- IO effects pushed to the boundaries (main, task runners)
- Shared context via a lightweight `AppContext` record
- Domain types that prevent misuse at compile time
- Explicit error types that preserve decision context

## Incremental Improvement Plan

Each phase is a vertical slice: types, logic, tests, and documentation delivered together. Every phase is a standalone PR.

### Phase 1: Pure Function Extraction + Tests

**Goal**: Identify functions that are IO but contain pure logic, extract the pure core, and add deterministic tests for each.

**Candidates** (each delivered with property-based and unit tests):
- [x] `SocialPosting.isReflectionEligibleForPosting` — done (uses `Day` and `TimeOfDay`)
- [ ] `Scheduler.nowPacificHour` — already partially pure (`pacificHour` exists), but `getScheduledTasks` could take `UTCTime` directly. Add property: result is always 0-23.
- [ ] `Env.getYesterdayDate` — extract pure `yesterdayDate :: UTCTime -> Day`. Add property: result is always `pred` of today.
- [ ] `SocialPosting.findMostRecentReflection` — separate directory listing (IO) from "pick most recent" logic (pure sort/filter). Test the pure selection logic.
- [ ] `BlogImage.checkCandidate` — separate file reading from eligibility decision. Test eligibility as pure function.
- [ ] `Scheduler.blogPostExistsForToday` — separate directory listing from filename matching. Test the matching logic.

### Phase 2: Domain Types + Tests

**Goal**: Introduce newtypes for commonly confused domain values, with smart constructors and property tests.

Each type delivered as a vertical slice with constructor, tests, and migration of one or two call sites:
- [ ] `newtype Url = Url Text` with smart constructor validating it starts with `https://`. Property: constructed `Url` always starts with `https://`.
- [ ] `newtype Title = Title Text` for display titles
- [ ] Promote `DateStr` — already exists in `BlogPrompt`, extend to `Types.hs` for shared use
- [ ] `newtype RelativePath = RelativePath Text` for vault-relative paths
- [ ] `newtype ApiKey = ApiKey Text` to prevent logging secrets. Smart constructor, `Show` instance redacts.
- [ ] `data PlatformLimits = PlatformLimits { maxChars :: Int, urlLength :: Int }` for platform limits

### Phase 3: AppContext Record + Tests

**Goal**: Replace parameter threading with a shared context record, with tests for context construction.

Delivered as a single vertical slice:
- [ ] Define `AppContext` in a new `Automation.Context` module
- [ ] Update `taskRunners` to construct with `AppContext`
- [ ] Migrate one task runner at a time to accept `AppContext` instead of individual params
- [ ] Test context construction and validation
- [ ] Consider `ReaderT AppContext IO` monad if parameter threading becomes unwieldy

### Phase 4: Explicit Error Types + Tests

**Goal**: Replace `Either Text` and silent failures with domain error ADTs, with tests for error paths.

Each error migration delivered with test coverage:
- [ ] Define `data AppError = GeminiError Text | FileNotFound FilePath | ParseError Text FilePath | ...`
- [ ] Replace `Either Text` returns in Gemini module with `Either AppError`. Test error propagation.
- [ ] Replace silent empty-string returns (like `findBestMatch` returning `""`) with `Maybe` or `Either`. Test the Nothing/Left paths.
- [ ] Replace `error` calls in non-startup code with `Either` returns. Test failure scenarios.

### Phase 5: Separate Data from Behavior in ImageProviderConfig + Tests

**Goal**: Remove IO callbacks from `ImageProviderConfig`, with tests for each provider type.

- [ ] Define `data ImageProviderType = Cloudflare | HuggingFace | Together | Pollinations`
- [ ] Move provider-specific logic into a `generateImage :: Manager -> ImageProviderType -> ... -> IO (Either Text ...)` function
- [ ] Keep `ImageProviderConfig` as pure data (name, API key, model, provider type)
- [ ] Test provider configuration and selection logic

### Phase 6: Break Up RunScheduled.hs + Tests

**Goal**: Split the 913-line orchestrator into focused modules, each with its own tests.

- [ ] Extract `Automation.TaskRunner` — task dispatch, inter-task delay, result tracking. Test dispatch logic.
- [ ] Extract `Automation.VaultSync` (from RunScheduled) — file sync helpers. Test sync logic.
- [ ] Extract `Automation.CliArgs` — CLI parsing. Test argument parsing.
- [ ] Keep `RunScheduled.hs` as a thin main that wires everything together (~100 lines)

## Guiding Principles

1. **Vertical slices**: Every phase delivers types, logic, tests, and documentation together. Never defer testing to a later phase.
2. **Test first**: Write failing tests for the new pure signatures before implementing the logic.
3. **One change per PR**: Each improvement should be a single focused PR that can be reviewed and merged independently.
4. **Always green**: Every intermediate state must build and pass all tests.
5. **Backward compatible exports**: When changing function signatures, keep the old signature available (as an IO wrapper) until all callers are migrated.
6. **No big bang**: Never refactor more than one module at a time.
