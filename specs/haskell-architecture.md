# Haskell Architecture Improvement Plan

## Current State Summary

The Haskell codebase was ported from TypeScript and inherited several patterns that don't leverage Haskell's strengths for safety and correctness. The code works well and has good test coverage (870+ tests), but can be improved to better prevent accidental breakage and improve modularity.

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

Each item is a **vertical slice**: domain types, pure logic extraction, result types, tests, and documentation delivered together in one PR. Never separate type introduction from function extraction — they are one concern.

### Completed: Pure Extraction + Domain Types

Each function was extracted as a pure core with proper domain types, tested with property-based and unit tests:

- [x] `SocialPosting.isReflectionEligibleForPosting` — uses `Day` and `TimeOfDay` domain types
- [x] `Scheduler.pacificHour` — already pure, property test (result always 0-23) and PST/PDT unit tests
- [x] `Env.yesterdayDate :: UTCTime -> Day` — pure core extracted from IO wrapper
- [x] `Reflection.selectMostRecentReflection :: [String] -> Maybe Text` — moved to own domain module from SocialPosting, consolidated duplicate from InternalLinking
- [x] `Scheduler.blogPostMatchesToday :: Text -> [String] -> Bool` — pure filename matching
- [x] `BlogImage.checkCandidateEligibility` — uses `ContentDirectory` ADT, `Day` for dates, `CandidateEligibility` result type (with `IneligibilityReason` ADT instead of `Maybe Bool`)
- [x] `BlogImage.ContentDirectory` — closed ADT for the 13 content directories, with round-trip `toText`/`fromText` and `Bounded`/`Enum`
- [x] `BlogImage.parseDateFromFilename :: Text -> Maybe Day` — returns proper `Day` instead of `Text`
- [x] `BlogImage.BackfillCandidate` — uses `ContentDirectory` and `Day` instead of `Text`
- [x] `BlogPrompt.todayPacificDay :: IO Day` — returns Pacific `Day` directly, no string round-trip

### Next: Remaining Domain Types

Each type delivered as a vertical slice with constructor, tests, and migration of call sites:
- [x] `newtype Url = Url Text` with smart constructor validating it starts with `http://` or `https://`. Property: constructed `Url` always starts with `http://` or `https://`. Lives in `Automation.Url` module. Applied to `rdUrl`, `mprUrl`, `mcInstanceUrl`, `lcUri`.
- [x] `newtype Title = Title Text` for display titles. Smart constructor rejects empty/whitespace. Lives in `Automation.Title` module. Applied to `rdTitle`, `ogTitle`, `lcTitle`, `cnTitle`, `ceTitle`, `cePlainTitle`, `ulTitle`.
- [x] `DateStr` replaced with standard `Day` from `Data.Time`. Added `formatDay :: Day -> Text` helper in BlogPrompt. Removed custom `DateStr` newtype entirely.
- [x] `newtype RelativePath = RelativePath Text` for vault-relative paths. Smart constructor rejects empty and absolute paths. Lives in `Automation.RelativePath` module. Applied to `cnRelativePath`, `cnLinkedNotePaths`, `ceRelativePath`, `frRelativePath`, `ulRelativePath`.
- [x] `newtype Secret = Secret Text` — generalized from `ApiKey` to cover API keys, passwords, and auth tokens. Lives in `Automation.Secret` domain module. Custom `Show` instance displays `<redacted>`. Applied to all credential fields across `TwitterCredentials`, `BlueskyCredentials`, `MastodonCredentials`, `GeminiConfig`, `ObsidianCredentials`.
- [x] `data PlatformLimits = PlatformLimits { platformMaxCharacters :: Int, platformUrlCountLength :: Maybe Int }` for platform limits. Per-platform constants (`twitterLimits`, `blueskyLimits`, `mastodonLimits`), generalized `calculatePostLength` and `validatePostLength`. Removed backward-compat aliases.
- [x] `data SocialPost = Tweet Text | BlueskyPost Text | MastodonPost Text` — per-platform ADT with smart constructors (`mkTweet`, `mkBlueskyPost`, `mkMastodonPost`, `mkSocialPost`) that validate character limits at construction time.

### Completed: Break Up Types Module

**Goal**: Replaced the monolithic `Automation.Types` module with domain-specific modules. Each type and its constants lives in the module that owns its domain concept, following library-developer module design (vertical slicing by feature, not horizontal slicing by artifact kind). `Types.hs` is a thin re-export hub for shared types only.

Types moved to their owning feature modules (using qualified import pattern — consumers write `import qualified ... as Twitter` etc.):
- [x] `Credentials`, `PostResult`, `limits`, `twitterHandle`, `displayName`, `sectionHeader` → `Automation.Platforms.Twitter`
- [x] `Credentials`, `PostResult`, `EmbedResult`, `LinkCard`, `limits`, `displayName`, `sectionHeader`, `oembedInitialDelayMs`, `oembedRetryDelayMs` → `Automation.Platforms.Bluesky`
- [x] `Credentials`, `PostResult`, `limits`, `displayName`, `sectionHeader` → `Automation.Platforms.Mastodon`
- [x] `OgMetadata` → `Automation.Platforms.OgMetadata`
- [x] `Config`, `Request`, `Response`, `GenerationConfig`, `defaultModel`, `defaultQuestionModel`, `flashFallback`, `modelFallback` → `Automation.Gemini`
- [x] `EnvironmentConfig` → `Automation.Env`
- [x] `ObsidianCredentials` → `Automation.ObsidianSync` (was already defined there)
- [x] `EmbedSection` → `Automation.EmbedSection`
- [x] `ReflectionData` → `Automation.Reflection`
- [x] Qualified import pattern adopted: types use short names (e.g. `Credentials` not `TwitterCredentials`), consumers qualify with module alias (e.g. `Twitter.Credentials`)

Shared abstractions (used across multiple unrelated modules):
- [x] `PlatformLimits` type + `updatesSectionHeader` → `Automation.Platform`

Deleted horizontal-slice modules (replaced by vertical feature modules):
- [x] `Automation.Credentials` — deleted (was a horizontal slice grouping unrelated credential types)
- [x] `Automation.Embed` — deleted (was a horizontal slice grouping unrelated embed types)

`Automation.Types` retained as thin re-export hub for truly shared types only (Secret, PlatformLimits, Url, Title, RelativePath, ReflectionData, OgMetadata, EmbedSection, EnvironmentConfig, ObsidianCredentials).

### Completed: AppContext Record + Tests

**Goal**: Replaced parameter threading with a shared context record, following the [ReaderT design pattern](https://www.fpcomplete.com/blog/readert-design-pattern/) — the context holds all startup-time configuration and shared dependencies needed throughout the program's lifecycle.

Delivered as a single vertical slice:
- [x] Define `AppContext` in a new `Automation.Context` module — holds `httpManager`, `vaultDir`, `repoRoot`, `geminiApiKey`, and `obsidianCredentials`
- [x] Domain-descriptive field names (no `app` prefix) with module imported qualified as `Context`
- [x] Explicit field exports (no wildcard `(..)` imports)
- [x] Update `taskRunners` to construct with `AppContext`
- [x] Migrate all task runners (`runBlogSeries`, `runBackfillImages`, `runInternalLinking`, `runSocialPosting`, `runAiFiction`, `runReflectionTitle`) to accept `AppContext` instead of individual params
- [x] Test context construction and validation — smart constructor rejects empty paths, Show redacts secrets, property test for valid paths
- [x] `callGeminiForGenerator` uses API key from context (callback adapter ignores duplicate key from library interface)
- [x] `main` reads all environment variables once at startup and constructs validated `AppContext`

### Next: Explicit Error Types + Tests

**Goal**: Replace `Either Text` and silent failures with domain error ADTs, with tests for error paths.

Each error migration delivered with test coverage:
- [x] Define `Gemini.Error` ADT: `JsonParseError`, `ExtractionError Text`, `HttpError Int ApiStatus Text`, `AllModelsFailed Model Error`. Parse structured API error JSON (the `error.status` field from the official Gemini troubleshooting docs at https://ai.google.dev/gemini-api/docs/troubleshooting) into an `ApiStatus` ADT (`ResourceExhausted`, `InvalidArgument`, `PermissionDenied`, etc.) so rate-limit and quota detection use constructor matching, not string inspection. Changed `generateContentWithFallback` to take `NonEmpty Model` (eliminating `NoModelsProvided` and all empty-list runtime errors). Callers use `show` for string representation — no `renderError` unwrapper.
- [x] Define `Gemini.Model` ADT: `Gemma3`, `Gemini31FlashLite`, `Gemini3Flash`, `Gemini25Flash`, `Gemini25FlashLite`, `Gemini20Flash`, `Gemini31FlashImage`, `Custom Text`. Round-trip `modelToText`/`modelFromText` functions. `AllModelsFailed` carries `Model` not `Text`. All callers migrated: env-var overrides use `modelFromText` at the boundary, typed constructors used everywhere else. `BlogImage.geminiModelFallback` uses constructor pattern matching instead of prefix string matching.
- [x] Migrate all model chain types from `[Gemini.Model]` to `NonEmpty Gemini.Model` everywhere: `FictionConfig.fcModels`, `ReflectionTitleConfig.rtcModels`, `BlogSeriesRunConfig.bsrcModelChain`, `callGeminiForGenerator`, and all callback types. Dissolved empty-list runtime errors at the type level.
- [ ] Replace `Either Text` returns in platform modules (Twitter, Bluesky, Mastodon) with per-module `Error` ADTs. Test error propagation.
- [ ] Replace silent empty-string returns (like `findBestMatch` returning `""`) with `Maybe` or `Either`. Test the Nothing/Left paths.
- [ ] Replace `error` calls in non-startup code with `Either` returns. Test failure scenarios.

**Learnings from the Gemini error migration:**
1. **Ground detection in official docs**: Match error conditions on machine-readable fields from the API (like `error.status`), not on ad-hoc string patterns in the body. The Gemini API returns structured JSON with a `status` field — parse it into an ADT for reliable matching.
2. **Dissolve impossible states at the type level**: Instead of adding an error constructor for "no models provided" and handling it at runtime, change the function signature to use `NonEmpty` from `Data.List.NonEmpty` so the empty-list case is unrepresentable. Never accept a plain list and then call `error` when it is empty — use NonEmpty to encode the at-least-one guarantee statically.
3. **Don't unwrap typed errors back to Text**: The `Show` instance preserves full structure. A custom `renderError :: Error -> Text` encourages callers to discard type information. Pattern-match on constructors for decisions; use `show` for display.
4. **Parse external APIs at the boundary**: When the API returns structured error JSON, parse it immediately in `generateContent` into the typed `ApiStatus` ADT. Downstream code never sees raw response bodies.
5. **Closed sets as ADTs**: Model names are a known set — represent them as a sum type with dedicated constructors rather than raw `Text`. Environment variable overrides parse into the ADT (with a `Custom Text` fallback) at the boundary. This eliminates string typos, enables constructor pattern matching for fallback logic, and provides round-trip guarantees via property tests.

### Next: Separate Data from Behavior in ImageProviderConfig + Tests

**Goal**: Remove IO callbacks from `ImageProviderConfig`, with tests for each provider type.

- [ ] Define `data ImageProviderType = Cloudflare | HuggingFace | Together | Pollinations`
- [ ] Move provider-specific logic into a `generateImage :: Manager -> ImageProviderType -> ... -> IO (Either Text ...)` function
- [ ] Keep `ImageProviderConfig` as pure data (name, API key, model, provider type)
- [ ] Test provider configuration and selection logic

### Next: Break Up RunScheduled.hs + Tests

**Goal**: Split the 913-line orchestrator into focused modules, each with its own tests.

- [ ] Extract `Automation.TaskRunner` — task dispatch, inter-task delay, result tracking. Test dispatch logic.
- [ ] Extract `Automation.VaultSync` (from RunScheduled) — file sync helpers. Test sync logic.
- [ ] Extract `Automation.CliArgs` — CLI parsing. Test argument parsing.
- [ ] Keep `RunScheduled.hs` as a thin main that wires everything together (~100 lines)

## Guiding Principles

1. **Vertical slices**: Every improvement delivers types, logic, tests, and documentation together. Never separate pure extraction from domain type introduction — they are one concern.
2. **Test first**: Write failing tests for the new pure signatures before implementing the logic.
3. **One change per PR**: Each improvement should be a single focused PR that can be reviewed and merged independently.
4. **Always green**: Every intermediate state must build and pass all tests.
5. **Backward compatible exports**: When changing function signatures, keep the old signature available (as an IO wrapper) until all callers are migrated.
6. **No big bang**: Never refactor more than one module at a time.
7. **Domain types at extraction**: When extracting a pure function, always use proper domain types (ADTs for closed sets, Day for dates, newtypes for domain concepts). Never extract with primitive Text parameters.
