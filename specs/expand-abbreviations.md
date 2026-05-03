# Expand Abbreviations in the Haskell Codebase

## Goal

🔤 Eliminate all abbreviated function and variable names from the Haskell codebase, one name at a time. 📖 Self-documenting code should speak for itself — no mental decoding tables required.

## Guiding Principles

- 🔤 Full words always: write `initialRequest` not `initReq`, `serviceAccountKey` not `sak`, `contentLines` not `ls`.
- 🏷️ No record field prefixes: use `author` not `bcAuthor`, `body` not `gcBody`. The module qualifier handles disambiguation.
- 🚫 No DuplicateRecordFields extension: when two records in the same module share a field name, move one record to its own file and import it qualified.
- 🧪 Build and run all tests after each rename to ensure correctness.

## Incremental Plan

Each step identifies one file and one abbreviated name to expand everywhere in the codebase. Check off each item after it is completed and merged.

### Phase 1 — Local Variable Names (No Record Disambiguation Required)

These are local bindings inside function bodies. Renaming them does not affect exported APIs or require qualified imports.

#### GcpAuth.hs

- [x] `initReq` → `initialRequest` (local binding for the parsed HTTP request before configuration)
- [x] `sak` → `serviceAccountKey` (parameter name in `getAccessTokenWithScope`)
- [x] `jcIss` → `issuer` (JwtClaims record field)
- [x] `jcScope` → `scope` (JwtClaims record field)
- [x] `jcAud` → `audience` (JwtClaims record field)
- [x] `jcIat` → `issuedAt` (JwtClaims record field)
- [x] `jcExp` → `expiresAt` (JwtClaims record field)
- [x] `trAccessToken` → `accessToken` (TokenResponse record field)
- [x] `trTokenType` → `tokenType` (TokenResponse record field)
- [x] `trExpiresIn` → `expiresIn` (TokenResponse record field)
- [x] `sakProjectId` → `projectId` (ServiceAccountKey record field)
- [x] `sakClientEmail` → `clientEmail` (ServiceAccountKey record field)
- [x] `sakPrivateKey` → `privateKey` (ServiceAccountKey record field)

#### BlogComments.hs

- [x] `initReq` → `initialRequest` (local binding for the parsed HTTP request)
- [x] `gc` → `graphqlComment` (parameter in `toComment`)
- (record field renames moved to Phase 2 — require moving Gql* types to a sub-module first)

#### BlogImage/Provider.hs

- [x] `initReq` → `initialRequest` (multiple local bindings for parsed HTTP requests)

#### StaticGiscus.hs

- [x] `initReq` → `initialRequest` (local binding for the parsed HTTP request)

#### Platforms/Mastodon.hs

- [x] `initialReq` → `initialRequest` (local binding — `initialReq` is still abbreviated: `Req` ≠ `Request`)

#### Platforms/Bluesky.hs

- [x] `initialReq` → `initialRequest` (multiple local bindings)

#### Platforms/Twitter.hs

- [x] `initialReq` → `initialRequest` (multiple local bindings)

### Phase 2 — Record Field Name Prefixes

Record field abbreviation prefixes must be removed. When two records in the same module would share the same field name after de-prefixing, move one record to its own module and import it qualified.

#### BlogComments.hs

- [ ] `bcAuthor` → `author` (BlogComment record field) — may require moving Gql* types to Automation.BlogComments.GraphQL
- [ ] `bcBody` → `body` (BlogComment record field)
- [ ] `bcCreatedAt` → `createdAt` (BlogComment record field)
- [ ] `bcIsPriority` → `isPriority` (BlogComment record field)
- [ ] `gcBody` → `body` (GqlComment record field) — move Gql* to sub-module first
- [ ] `gcAuthor` → `author` (GqlComment record field)
- [ ] `gcCreatedAt` → `createdAt` (GqlComment record field)
- [ ] `gcnNodes` → `nodes` (GqlCommentsNode record field)
- [ ] `gdTitle` → `title` (GqlDiscussion record field)
- [ ] `gdComments` → `comments` (GqlDiscussion record field)
- [ ] `gsnNodes` → `nodes` (GqlSearchNodes record field)
- [ ] `gsdSearch` → `search` (GqlSearchData record field)
- [ ] `grData` → `responseData` (GqlResponse record field)
- [ ] `grErrors` → `errors` (GqlResponse record field)
- [ ] `geMessage` → `message` (GqlError record field)
- [ ] `gaLogin` → `login` (GqlAuthor record field)

#### BlogImage/Eligibility.hs

- [ ] `bcFilePath` → `filePath` (BackfillCandidate record field)
- [ ] `bcDirectory` → `directory` (BackfillCandidate record field)
- [ ] `bcFilename` → `filename` (BackfillCandidate record field)
- [ ] `bcDate` → `date` (BackfillCandidate record field)
- [ ] `bcNeedsRegeneration` → `needsRegeneration` (BackfillCandidate record field)

#### BlogImage.hs

- [ ] `brImagesGenerated` → `imagesGenerated` (BackfillResult record field)
- [ ] `brFilesUpdated` → `filesUpdated` (BackfillResult record field)
- [ ] `brFilesSkipped` → `filesSkipped` (BackfillResult record field)
- [ ] `brModifiedFiles` → `modifiedFiles` (BackfillResult record field)
- [ ] `brErrors` → `errors` (BackfillResult record field)

#### BlogPrompt.hs

- [ ] `bcxSeries` → `series` (BlogContext record field)
- [ ] `bcxAgentsMd` → `agentsMd` (BlogContext record field)
- [ ] `bcxPreviousPosts` → `previousPosts` (BlogContext record field)
- [ ] `bcxComments` → `comments` (BlogContext record field)
- [ ] `bcxToday` → `today` (BlogContext record field)
- [ ] `bcxCrossSeriesPosts` → `crossSeriesPosts` (BlogContext record field)

#### GoogleAnalytics.hs

- [x] Audit all record fields for abbreviated prefixes — no abbreviated prefixes found; `pv`, `vis`, `br`, `pps`, `dur` local variables in `parseSummaryResponse` renamed to full names

#### DailyUpdates.hs

- [x] `idx` → `index` (local variable in section insertion logic)

#### Prompts.hs

- [x] `idx` → `index` (local variable in title truncation logic)

#### InternalLinking.hs

- [x] `ls` → `contentLines` (local variable in `extractBody` and `updateFrontmatterFields`, parameter in `upsertField`)
- [x] `pos` → `position` (local variable in `applyReplacements`)
- [x] `len` → `matchLength` (local variable in `applyReplacements`)
- [x] `wl` → `wikilink` (local variable in `applyReplacements`)
- [x] `val` → `yamlValue` (parameter in `upsertField`)
- [x] `acc` → `currentText` (accumulator parameter in `applyOne`)
- [ ] `mFileResult` → `maybeFileResult` (local binding in `go`)
- [ ] `infRef` → `inferenceCountRef` (IORef parameter in `processFiles`/`go`)
- [ ] `resRef` → `resultsRef` (IORef parameter in `processFiles`/`go`)
- [ ] `infCount` → `inferenceCount` (local binding in `go`)
- [ ] `mKey` → `maybeKey` (local binding in `lookupSecret`)

#### DailyReflection.hs

- [ ] `ls` → `contentLines` (local variable)
- [ ] `idx` → `index` (local variable)

#### BlogSeries.hs

- [ ] `ls` → `contentLines` (local variable)

#### AiFiction.hs

- [ ] `ls` → `contentLines` (local variable)
- [ ] `idx` → `index` (local variable in `findClosingDash`)

#### ReflectionTitle.hs

- [ ] `ls` → `titleLines` (local variable)
- [ ] `val` → `titleValue` (local variable in `titleMatchesDate`)
- [ ] `tl` → `titleLine` (parameter in `titleMatchesDate`)
- [ ] `acc` → `found` (accumulator in `findTitleLine`)
- [ ] `idx` → `index` (local variable in `stripInlinePreamble`)

#### SocialPosting.hs

- [ ] `acc` → `grouped` (accumulator in `addToGroup`)

#### AiBlogLinks.hs

- [ ] `ls` → `contentLines` (local variable in `updateNavLinks`)
- [ ] `idx` → `index` (local variable in `updateNavLinks` and `processFile`)
- [ ] `p` → `predicate` (parameter in local `findIndex`)
- [ ] `nlrFilename` → `filename` (NavLinkResult record field)
- [ ] `nlrModified` → `modified` (NavLinkResult record field)

#### BlogSeriesConfig.hs

- [ ] `bscId` → `identifier` (BlogSeriesConfig record field — `id` shadows Prelude)
- [ ] `bscName` → `name` (BlogSeriesConfig record field)
- [ ] `bscIcon` → `icon` (BlogSeriesConfig record field)
- [ ] `bscAuthor` → `author` (BlogSeriesConfig record field)
- [ ] `bscBaseUrl` → `baseUrl` (BlogSeriesConfig record field)
- [ ] `bscPriorityUser` → `priorityUser` (BlogSeriesConfig record field)
- [ ] `bscNavLink` → `navLink` (BlogSeriesConfig record field)
- [ ] `bscScheduleTime` → `scheduleTime` (BlogSeriesConfig record field)
- [ ] `bscContextQueries` → `contextQueries` (BlogSeriesConfig record field)

#### Frontmatter.hs

- [ ] `ls` → `contentLines` (local variable in `parseFrontmatter`)

#### Text.hs

- [ ] `xs` → `elements` (parameter in `findLastIndex`, `removeAt`, and lambda in `strategy4`)
- [ ] `len` → `postLength` (local variable in `validatePostLength`)
- [ ] `p` → `predicate` (parameter in `findLastIndex`)
- [ ] `lns` → `contentLines` (local variable in `fitPostToLimit` and `fitWithStrategies`)
- [ ] `urlIdx` → `urlIndex` (local variable in `fitWithStrategies`)
- [ ] `ci` → `colonIndex` (pattern variable in `strategy3`)

## Ordering Notes

- 🔤 Local variable renames (Phase 1) are safe and can be done in any order.
- 🏷️ Record field renames (Phase 2) require checking for name clashes within the same module. When a clash exists, move the record type to a dedicated sub-module and import it qualified.
- 🔢 Each step is a separate PR: one name, expanded everywhere in the codebase, with a passing build.
