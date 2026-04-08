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

Each phase below is designed to be a standalone PR that improves the codebase without requiring other phases to be complete.

### Phase 1: Pure Function Extraction (Low Risk, High Value)

**Goal**: Identify functions that are IO but contain pure logic, and extract the pure core.

**Candidates**:
- [x] `SocialPosting.isReflectionEligibleForPosting` — done in initial PR
- [ ] `Scheduler.nowPacificHour` — already partially pure (`pacificHour` exists), but `getScheduledTasks` could take `UTCTime` directly
- [ ] `Env.getYesterdayDate` — extract pure `yesterdayDate :: UTCTime -> Text`
- [ ] `SocialPosting.findMostRecentReflection` — separate directory listing (IO) from "pick most recent" logic (pure sort/filter)
- [ ] `BlogImage.checkCandidate` — separate file reading from eligibility decision
- [ ] `Scheduler.blogPostExistsForToday` — separate directory listing from filename matching

**Pattern**: For each function, create a pure version that accepts all inputs as parameters, then create a thin IO wrapper that gathers the inputs and calls the pure function.

### Phase 2: Domain Types (Medium Risk, High Value)

**Goal**: Introduce newtypes for commonly confused domain values.

**Priority types**:
- [ ] `newtype Url = Url Text` with smart constructor validating it starts with `https://`
- [ ] `newtype Title = Title Text` for display titles
- [ ] `newtype DateStr = DateStr Text` — already exists in `BlogPrompt`, extend to `Types.hs` for shared use
- [ ] `newtype RelativePath = RelativePath Text` for vault-relative paths
- [ ] `newtype ApiKey = ApiKey Text` to prevent logging secrets
- [ ] `data CharLimit = CharLimit { clMax :: Int, clUrlLength :: Int }` for platform limits

**Approach**: Introduce one newtype at a time, starting with the most commonly confused. Each newtype gets its own PR.

### Phase 3: AppContext Record (Medium Risk, Medium Value)

**Goal**: Replace parameter threading with a shared context record.

```haskell
data AppContext = AppContext
  { acManager   :: Manager
  , acRepoRoot  :: FilePath
  , acVaultDir  :: FilePath
  , acEnvConfig :: EnvironmentConfig
  , acLogMsg    :: Text -> IO ()
  }
```

**Steps**:
- [ ] Define `AppContext` in a new `Automation.Context` module
- [ ] Update `taskRunners` to construct with `AppContext`
- [ ] Migrate one task runner at a time to accept `AppContext` instead of individual params
- [ ] Consider `ReaderT AppContext IO` monad if parameter threading becomes unwieldy

### Phase 4: Explicit Error Types (Medium Risk, High Value)

**Goal**: Replace `Either Text` and silent failures with domain error ADTs.

**Steps**:
- [ ] Define `data AppError = GeminiError Text | FileNotFound FilePath | ParseError Text FilePath | ...`
- [ ] Replace `Either Text` returns in Gemini module with `Either AppError`
- [ ] Replace silent empty-string returns (like `findBestMatch` returning `""`) with `Maybe` or `Either`
- [ ] Replace `error` calls in non-startup code with `Either` returns

### Phase 5: Separate Data from Behavior in ImageProviderConfig (Low Risk, Medium Value)

**Goal**: Remove IO callbacks from `ImageProviderConfig`.

**Steps**:
- [ ] Define `data ImageProviderType = Cloudflare | HuggingFace | Together | Pollinations`
- [ ] Move provider-specific logic into a `generateImage :: Manager -> ImageProviderType -> ... -> IO (Either Text ...)` function
- [ ] Keep `ImageProviderConfig` as pure data (name, API key, model, provider type)

### Phase 6: Break Up RunScheduled.hs (Medium Risk, Medium Value)

**Goal**: Split the 913-line orchestrator into focused modules.

**Steps**:
- [ ] Extract `Automation.TaskRunner` — task dispatch, inter-task delay, result tracking
- [ ] Extract `Automation.VaultSync` (from RunScheduled) — file sync helpers already in the file
- [ ] Extract `Automation.CliArgs` — CLI parsing
- [ ] Keep `RunScheduled.hs` as a thin main that wires everything together (~100 lines)

### Phase 7: Property-Based Testing (Low Risk, High Value)

**Goal**: Add QuickCheck properties for pure functions, especially after Phase 1 extractions.

**Candidates**:
- [ ] `isReflectionEligibleForPosting` — property: old dates are always eligible
- [ ] `pacificHour` — property: result is always 0-23
- [ ] `detectPostedPlatforms` — property: result is always a subset of all platforms
- [ ] `normalizeFilePath` — property: idempotent
- [ ] `wordJaccardSimilarity` — property: result is always 0.0-1.0, symmetric

## Guiding Principles

1. **One change per PR**: Each improvement should be a single focused PR that can be reviewed and merged independently.
2. **Always green**: Every intermediate state must build and pass all tests.
3. **Backward compatible exports**: When changing function signatures, keep the old signature available (as an IO wrapper) until all callers are migrated.
4. **Tests first**: Write failing tests for the new pure signatures before implementing.
5. **No big bang**: Never refactor more than one module at a time.
