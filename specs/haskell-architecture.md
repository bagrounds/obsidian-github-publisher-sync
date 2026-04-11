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
- [x] Replace `Either Text` returns in platform modules (Twitter, Bluesky, Mastodon) with per-module `Error` ADTs (`HttpError Int Text`, `JsonParseError Text`, `ExtractionError Text`, `NetworkError Text`). Added `classifyException` to each module that preserves HTTP status codes from `HttpCodeException` instead of collapsing to `T.pack (show err)`. Fixed Bluesky `tryOEmbedWithRetry` to pattern match on `HttpError 404` instead of string-searching for `"404"`. All callers in SocialPosting use `show` for string representation. 54 new tests covering parse error paths, classifyException, and Show properties.
- [x] Replace silent empty-string returns: Reviewed all `= ""` patterns in the codebase. All instances are correct identity-element behavior (empty list → empty string for path joining, prompt building, and HTML rendering) or safe default values (`safeIdx` returning `""` causes downstream pattern matches to correctly reject the value). No changes needed — no actual silent failures exist.
- [x] Replace `error` calls in non-startup code with `Either` returns. Removed `validatedTitle`, `validatedUrl`, and `validatedRelativePath` helper functions (which wrapped `error`) from `Frontmatter`, `SocialPosting`, and `InternalLinking`. File-parsing functions (`readReflection`, `readNote`, `readContentNote`, `readEntry`) now use `mkTitle`/`mkUrl`/`mkRelativePath` directly and return `Nothing` with a warning log on validation failure instead of crashing. `findLinkCandidates` accepts `RelativePath` instead of `Text`, pushing validation to the boundary. `processFile` returns `Maybe FileResult`, skipping files with invalid paths. `buildBlogContext` returns `Either Text BlogContext`, propagating `lookupSeries` errors to the caller. 15 new tests covering error paths.

**Learnings from the Gemini error migration:**
1. **Ground detection in official docs**: Match error conditions on machine-readable fields from the API (like `error.status`), not on ad-hoc string patterns in the body. The Gemini API returns structured JSON with a `status` field — parse it into an ADT for reliable matching.
2. **Dissolve impossible states at the type level**: Instead of adding an error constructor for "no models provided" and handling it at runtime, change the function signature to use `NonEmpty` from `Data.List.NonEmpty` so the empty-list case is unrepresentable. Never accept a plain list and then call `error` when it is empty — use NonEmpty to encode the at-least-one guarantee statically.
3. **Don't unwrap typed errors back to Text**: The `Show` instance preserves full structure. A custom `renderError :: Error -> Text` encourages callers to discard type information. Pattern-match on constructors for decisions; use `show` for display.
4. **Parse external APIs at the boundary**: When the API returns structured error JSON, parse it immediately in `generateContent` into the typed `ApiStatus` ADT. Downstream code never sees raw response bodies.
5. **Closed sets as ADTs**: Model names are a known set — represent them as a sum type with dedicated constructors rather than raw `Text`. Environment variable overrides parse into the ADT (with a `Custom Text` fallback) at the boundary. This eliminates string typos, enables constructor pattern matching for fallback logic, and provides round-trip guarantees via property tests.

**Learnings from the platform error migration:**
6. **Classify exceptions at the boundary with typed constructors**: When using `try @SomeException`, immediately classify the caught exception into a typed `Error` ADT using `classifyException` that preserves the HTTP status code as an `Int` and the message as `Text`. This replaces `T.pack (show err)` which discards the machine-readable status code.
7. **Replace string inspection with constructor matching**: When code checks error messages with `T.isInfixOf "404"` or similar string patterns, migrate to pattern matching on `HttpError 404 _`. This eliminates false positives from unrelated errors that happen to contain the same substring.
8. **Consistent per-module Error ADT pattern**: Each platform module defines its own `Error` type with four constructors (`HttpError`, `JsonParseError`, `ExtractionError`, `NetworkError`) following vertical slicing. The structure is intentionally identical across platforms — if a platform-specific error constructor is needed later, it can be added independently without affecting other modules.

**Learnings from replacing `error` calls:**
9. **Never wrap smart constructors with `error`**: The pattern `validatedFoo = either (error . T.unpack) id . mkFoo` creates a time bomb — it compiles fine but crashes at runtime when fed unexpected data. Instead, use the `Either` return directly and handle the `Left` case by logging a warning and skipping the record (returning `Nothing` from IO-based record parsers).
10. **Use `Either` monadic bind to chain validations**: When building a record that requires multiple validated fields, use `do`-notation in the `Either` monad: `do { title <- mkTitle t; url <- mkUrl u; pure Record{..} }`. The first validation failure short-circuits with a descriptive error message, and the `Left` is handled once at the call site.
11. **Push validation to function boundaries via domain types**: When a function takes `Text` only to immediately validate it into a domain type (like `RelativePath`), change the parameter to accept the domain type directly. This moves validation to the caller (the boundary) where error handling is more natural, and makes the function's contract explicit in its type signature.
12. **Prefer `Maybe` over `Either` when callers don't distinguish errors**: For file-parsing functions that return `IO (Maybe Record)`, validation failures can use the same `Nothing` path as "file not found" — the caller already handles absence. Reserve `Either` for cases where the caller needs to distinguish different failure reasons.

### Completed: Separate Data from Behavior in ImageProviderConfig + Tests

**Goal**: Remove IO callbacks from `ImageProviderConfig`, with tests for each provider type.

- [x] Define `data ImageProvider = Cloudflare Text | HuggingFace | Together | Pollinations | GeminiImage` — closed ADT for image providers, with `Cloudflare` carrying its account ID. `providerName :: ImageProvider -> Text` replaces the old `ipcName` field.
- [x] Define `data PromptDescriber = PromptDescriber { describerApiKey :: Secret, describerModel :: Gemini.Model }` — pure data replacing the `ipcDescribePrompt` IO callback. `Show` instance redacts the API key via `Secret`'s custom `Show`.
- [x] Rewrite `ImageProviderConfig` as pure data: replaced `ipcName :: Text` with `ipcProvider :: ImageProvider`, replaced `ipcGenerator :: Manager -> ... -> IO (...)` with dispatch function, replaced `ipcDescribePrompt :: Maybe (Manager -> ...)` with `ipcDescriber :: Maybe PromptDescriber`. Config now derives `Show` and `Eq`.
- [x] Add `generateImage :: Manager -> ImageProviderConfig -> Text -> IO (Either Text (LBS.ByteString, Text))` — pattern matches on `ImageProvider` to dispatch to the correct HTTP generator function.
- [x] Add `describeContent :: Manager -> PromptDescriber -> Text -> IO (Either Text Text)` — dispatches to `describeImageWithGemini` using the describer's API key and model.
- [x] Update all provider resolvers (`mkCloudflareProvider`, `mkHuggingFaceProvider`, `mkTogetherProvider`, `mkPollinationsProvider`, `mkGeminiProvider`) to construct pure data configs.
- [x] Update all callers (`generateAndSaveImage`, `resolvePrompt`, `processWithProviders`) to use `generateImage`, `describeContent`, and `providerName . ipcProvider`.
- [x] 22 new tests: `ImageProvider` (providerName, Eq, Show, Cloudflare account ID), `PromptDescriber` (Show redaction, Eq, model comparison), `ImageProviderConfig` (Show, Eq, describer population, provider type resolution).

**Learnings from separating data from behavior:**
13. **Replace IO callbacks with ADT dispatch**: When a data structure embeds IO callbacks (like `ipcGenerator :: Manager -> ... -> IO (...)`), the type cannot derive `Show` or `Eq`, making it untestable as data. Replace the callback with a closed ADT (`ImageProvider`) and a dispatch function (`generateImage`) that pattern-matches on the constructor. The data structure becomes pure, testable, and the dispatch function is the single point where IO is introduced.
14. **Extract cross-cutting concerns as separate data**: When every variant of a config carries the same optional callback (like `ipcDescribePrompt`), it's a cross-cutting concern, not a per-variant behavior. Extract it as its own pure data record (`PromptDescriber`) with its own dispatch function (`describeContent`). This makes the relationship explicit: the describer is independent of the image provider.
15. **Derive instances to prove purity**: After removing IO from a data structure, immediately derive `Show` and `Eq`. If the compiler refuses, there's still hidden behavior embedded in the data. Successfully deriving both instances is proof that the structure is pure data.

### Completed: Break Up RunScheduled.hs + Tests

**Goal**: Split the 906-line orchestrator into focused modules, each with its own tests.

- [x] Extract `Automation.TaskRunner` — `runTasks`, `runTasksWithDelay` (configurable inter-task delay for testability), `logMsg`, `formatTimestamp`, `interTaskDelayMicroseconds`, `inferenceDashboards`, `TaskResult` type alias. 14 tests covering dispatch, error handling, execution order, and properties.
- [x] Extract `Automation.VaultSync` — `syncFileToVault`, `syncNewAiBlogPosts` (accepts logger callback to decouple from logging implementation), `copySeriesPosts`, `findBestMatch`, `showScore`, `similarityThreshold`. 14 tests covering pure functions and properties.
- [x] Extract `Automation.CliArgs` — `CliArgs` type (with `Show` and `Eq` instances) and `parseCliArgs`. 12 tests covering all flag combinations and properties.
- [x] Slim `RunScheduled.hs` from 906 to 722 lines. Task runner implementations remain in the executable (they are app-specific orchestration, not reusable library code).
- [x] Replace remaining `validatedTitle`/`validatedRelativePath` error wrappers with proper `Either` handling via `mkTitle`/`mkRelativePath`, logging warnings and filtering with `mapMaybe` instead of crashing.

**Learnings from breaking up RunScheduled.hs:**
16. **Configurable delays for testability**: When a module includes timing behavior (like inter-task delays), expose a configurable variant (`runTasksWithDelay`) alongside the production default (`runTasks`). Tests use zero delay to avoid hanging. The production function is a thin wrapper: `runTasks = runTasksWithDelay interTaskDelayMicroseconds`.
17. **Logger callbacks decouple IO modules**: When an extracted module needs to log but should not depend on the logging module, accept a `Text -> IO ()` callback parameter. The caller passes its own logger, keeping the extracted module focused on its domain.
18. **Use throwIO not error in tests**: Pure `error` calls produce bottom values that may not be caught by `try @SomeException` in all GHC versions. Use `throwIO` from `Control.Exception` to create proper IO-level exceptions that `try` reliably catches.
19. **Banker's rounding in Haskell**: `round` uses round-half-to-even (banker's rounding). `round 250.5 == 250` because 250 is even. When writing tests for rounding behavior, account for this or use an explicit rounding function.

### Completed: Extract Pure Utilities from RunScheduled.hs + Tests

**Goal**: Continue shrinking RunScheduled.hs by extracting pure functions to their owning domain modules, eliminating code duplication, and making previously untested logic testable.

- [x] Extract `generateSlug :: Text -> Text` to `Automation.BlogPrompt` — where the `Slug` type and `mkSlug` already live. Converts a title to a URL-safe kebab-case slug by stripping emojis, lowercasing, replacing non-alphanumeric characters with spaces, and collapsing into hyphens. 13 tests: 10 unit tests (emoji stripping, special characters, digit preservation, whitespace handling, empty input) and 3 property tests (no uppercase, no leading/trailing hyphens, output character set).
- [x] Extract `stripCodeFences :: Text -> Text` to `Automation.Text` — general text utility that strips markdown code fences from LLM output. Handles `` ```markdown ``, `` ```md ``, and plain `` ``` `` prefixes/suffixes. 9 unit tests covering all fence variants, partial fences, empty content, and multiline content.
- [x] Extract `overrideModelChain :: Maybe Text -> NonEmpty Model -> NonEmpty Model` to `Automation.Gemini` — DRY extraction of model chain override logic that was duplicated three times in RunScheduled.hs (`runBlogSeries`, `runAiFiction`, `tryTitleForDate`). Parses an optional environment variable override, prepends it to the default chain, and removes duplicates. 8 unit tests covering Nothing, empty string, whitespace, known models, custom models, trimming, deduplication.
- [x] Extract `isReflectionFile :: String -> Bool` to `Automation.ReflectionTitle` — pure predicate validating the `YYYY-MM-DD.md` filename pattern for reflection files. 8 unit tests covering valid files, wrong extensions, wrong lengths, non-numeric characters.
- [x] Extract `extractCreativeTitle :: Text -> Text` to `Automation.ReflectionTitle` — pure function that parses the creative part of a reflection title (the text after the date and pipe separator in the frontmatter `title:` field). 8 unit tests covering pipe extraction, missing pipes, missing title lines, quoted/unquoted values, multiple pipe separators.
- [x] Slim `RunScheduled.hs` from 722 to 665 lines (removed 57 lines of duplicated logic).

**Learnings from extracting pure utilities:**
20. **DRY via pure extraction**: When the same pattern appears three or more times in an app module (like model chain override logic), extract it as a pure function in the appropriate library module. This eliminates duplication, makes the logic testable, and reduces the app module's surface area.
21. **Place functions in their owning domain module**: `generateSlug` belongs with `Slug` and `mkSlug` in `BlogPrompt`, not in a generic `Utilities` module. `stripCodeFences` belongs in `Text` alongside other text transformations. `isReflectionFile` and `extractCreativeTitle` belong in `ReflectionTitle` since they're part of the reflection title domain. Following vertical slicing means the function lives where its domain concept is defined.
22. **Separate IO from pure logic in IO functions**: When an IO function like `extractRecentCreativeTitles` contains both file I/O and pure parsing, extract the pure parsing as a separate function. The IO function becomes a thin wrapper that reads the file and delegates to the pure function.

### Completed: Replace Error Calls in RunScheduled.hs Task Runners + Tests

**Goal**: Replace non-startup `error` calls in RunScheduled.hs with typed `TaskError` exceptions. The `error` function throws untyped `ErrorCall` exceptions, while `TaskError` provides a typed exception with a clean `Show` instance that outputs the message text directly (no constructor prefix), making error messages in the TaskRunner's run summary more readable.

- [x] Define `TaskError` typed exception in `Automation.TaskRunner` — `newtype TaskError = TaskError Text` with `Exception` instance and custom `Show` that outputs the message text directly (no constructor wrapper). This replaces the blunt `ErrorCall` thrown by `error`.
- [x] Add `failTask :: Text -> IO a` helper — throws `TaskError`, providing a consistent error handling pattern for all task runners. Accepts `Text` directly (no `T.unpack` needed at call sites).
- [x] Replace 7 non-startup `error` calls in `RunScheduled.hs` with `failTask`: `callGeminiForGenerator` (Gemini API error), `runBlogSeries` (no run config, lookupSeries failure, blog context build failure, blog generation failure, failed to parse generated post, invalid slug).
- [x] Restructure slug construction from pure `let` binding with `error` fallback to monadic `either failTask pure` pattern (since `failTask` returns `IO a`, it cannot be used in a pure binding).
- [x] 7 new tests (1202 → 1209): Show instance outputs message without constructor, unicode preservation, SomeException catch, fromException type match, runTasks integration marks task as failed, error message fidelity in run summary, property test for message round-trip through catch.

**Learnings from replacing error calls:**
23. **Typed exceptions over error**: Use `throwIO` with a domain-specific exception type instead of `error`. The `error` function throws `ErrorCall` which carries no type information. A `TaskError` exception can be caught specifically with `fromException`, and its custom `Show` instance provides clean messages without the `ErrorCall` prefix.
24. **Accept Text at the boundary**: `failTask :: Text -> IO a` accepts `Text` directly, eliminating `T.unpack` calls at error sites. Since most error messages are already `Text` values (from domain functions like `lookupSeries` returning `Either Text`), this reduces boilerplate.
25. **Pure bindings cannot use IO failures**: When replacing `error` (which is `forall a. String -> a` and fits in any expression) with `failTask` (which returns `IO a`), pure `let` bindings must be restructured into monadic `do` bindings. The `either failTask pure` pattern cleanly bridges `Either Text a` values into `IO a`.

### Next: Remaining Improvements

Prioritized list of remaining architecture improvements:

1. **Break up SocialPosting.hs** — 921 lines, 38 imports. Extract platform-specific posting orchestration, reflection eligibility checks, and post formatting into focused modules.
2. **Break up BlogImage.hs** — 1,291 lines, 26 imports. Extract image provider resolution, backfill orchestration, and eligibility checking into focused modules.
3. **Break up InternalLinking.hs** — 961 lines, 25 imports. Extract link candidate discovery, similarity matching, and file processing into focused modules.
4. **Extract remaining pure cores** — Several IO functions in library modules mix I/O with pure logic that could be extracted and tested independently.

## Guiding Principles

1. **Vertical slices**: Every improvement delivers types, logic, tests, and documentation together. Never separate pure extraction from domain type introduction — they are one concern.
2. **Test first**: Write failing tests for the new pure signatures before implementing the logic.
3. **One change per PR**: Each improvement should be a single focused PR that can be reviewed and merged independently.
4. **Always green**: Every intermediate state must build and pass all tests.
5. **Backward compatible exports**: When changing function signatures, keep the old signature available (as an IO wrapper) until all callers are migrated.
6. **No big bang**: Never refactor more than one module at a time.
7. **Domain types at extraction**: When extracting a pure function, always use proper domain types (ADTs for closed sets, Day for dates, newtypes for domain concepts). Never extract with primitive Text parameters.
