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

- [x] `bcAuthor` → `author` (BlogComment record field) — moved Gql* types to Automation.BlogComments.GraphQL
- [x] `bcBody` → `body` (BlogComment record field)
- [x] `bcCreatedAt` → `createdAt` (BlogComment record field)
- [x] `bcIsPriority` → `isPriority` (BlogComment record field)
- [x] `gcBody` → `body` (GqlComment record field) — moved to Automation.BlogComments.GraphQL
- [x] `gcAuthor` → `author` (GqlComment record field)
- [x] `gcCreatedAt` → `createdAt` (GqlComment record field)
- [x] `gcnNodes` → `nodes` (GqlCommentsNode record field)
- [x] `gdTitle` → `title` (GqlDiscussion record field)
- [x] `gdComments` → `comments` (GqlDiscussion record field)
- [x] `gsnNodes` → `searchNodes` (GqlSearchNodes record field — renamed `searchNodes` not `nodes` to avoid same-module conflict with `GqlCommentsNode.nodes`)
- [x] `gsdSearch` → `search` (GqlSearchData record field)
- [x] `grData` → `responseData` (GqlResponse record field)
- [x] `grErrors` → `errors` (GqlResponse record field)
- [x] `geMessage` → `message` (GqlError record field)
- [x] `gaLogin` → `login` (GqlAuthor record field)

#### BlogImage/Eligibility.hs

- [x] `bcFilePath` → `filePath` (BackfillCandidate record field)
- [x] `bcDirectory` → `directory` (BackfillCandidate record field)
- [x] `bcFilename` → `filename` (BackfillCandidate record field)
- [x] `bcDate` → `date` (BackfillCandidate record field)
- [x] `bcNeedsRegeneration` → `requiresRegeneration` (BackfillCandidate record field — renamed `requiresRegeneration` not `needsRegeneration` to avoid same-module conflict with `CandidateEligibility.needsRegeneration`)
- [x] `fm` → `frontmatter` (local binding for `parseFrontmatter` result in `shouldRegenerateImage`)

#### BlogImage.hs

- [x] `brImagesGenerated` → `imagesGenerated` (BackfillResult record field)
- [x] `brFilesUpdated` → `filesUpdated` (BackfillResult record field)
- [x] `brFilesSkipped` → `filesSkipped` (BackfillResult record field)
- [x] `brModifiedFiles` → `modifiedFiles` (BackfillResult record field)
- [x] `brErrors` → `errors` (BackfillResult record field)
- [x] `fm` → `frontmatter` (local binding for `parseFrontmatter` result in `extractFrontmatterValue`)
- [x] `ls` → `contentLines` (local variable in `updateFrontmatterFields`)

#### BlogPrompt.hs

- [x] `bcxSeries` → `series` (BlogContext record field)
- [x] `bcxAgentsMd` → `agentsMd` (BlogContext record field)
- [x] `bcxPreviousPosts` → `previousPosts` (BlogContext record field)
- [x] `bcxComments` → `comments` (BlogContext record field)
- [x] `bcxToday` → `today` (BlogContext record field)
- [x] `bcxCrossSeriesPosts` → `crossSeriesPosts` (BlogContext record field)

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
- [x] `mFileResult` → `maybeFileResult` (local binding in `visitFiles`)
- [x] `infRef` → `inferenceCount` (IORef parameter in `visitFiles`, dropping redundant `Ref` suffix)
- [x] `resRef` → `fileResults` (IORef parameter in `visitFiles`, dropping redundant `Ref` suffix)
- [x] `infCount` → `currentInferenceCount` (local read binding in `visitFiles`)
- [x] `mKey` → `maybeKey` (local binding in `lookupSecret`)
- [x] `go` → `visitFiles` (meaningless helper name replaced with descriptive name)
- [x] `inferenceRef` → `inferenceCount` (outer IORef binding in `processFiles`, dropping `Ref`)
- [x] `resultRef` → `fileResults` (outer IORef binding in `processFiles`, dropping `Ref`)
- [x] `fm` → `frontmatter` (local binding for `parseFrontmatter` result in `alreadyAnalyzed`)

#### DailyReflection.hs

- [x] `ls` → `contentLines` (local variable)
- [x] `idx` → `index` (local variable)

#### BlogSeries.hs

- [x] `ls` → `contentLines` (local variable)

#### AiFiction.hs

- [x] `ls` → `contentLines` (local variable)
- [x] `idx` → `index` (local variable in `findClosingDash`)

#### ReflectionTitle.hs

- [x] `ls` → `contentLines` (local variable — also renamed `lsBeforeUpdates` → `contentLinesBeforeUpdates`)
- [x] `val` → `titleValue` (local variable in `reflectionNeedsTitle`)
- [x] `tl` → `titleLine` (parameter in `reflectionNeedsTitle`)
- [x] `acc` → `found` (accumulator in `findTitleLine`)
- [x] `idx` → `index` (local variable in `stripInlinePreamble`)

#### SocialPosting.hs

- [x] `acc` → `grouped` (accumulator in `addToGroup`)
- [x] `env` → `environmentConfig` (parameter name for `EnvironmentConfig` in `postToPlatform`, `postToTwitterPlatform`, `postToBlueskyPlatform`, `postToMastodonPlatform`, `runPostingPipeline`, `processNoteGroup`, `postForPlatform`, and `run`)

#### AiBlogLinks.hs

- [x] `ls` → `contentLines` (local variable in `updateNavLinks`)
- [x] `idx` → `index` (local variable in `updateNavLinks` and `processFile`)
- [x] `p` → `predicate` (parameter in local `findIndex`)
- [x] `fm` → `frontmatter` (local binding for `parseFrontmatter` result in `processFile`)
- [x] `nlrFilename` → `filename` (NavLinkResult record field)
- [x] `nlrModified` → `modified` (NavLinkResult record field)

#### BlogSeriesConfig.hs

- [x] `bscId` → `identifier` (BlogSeriesConfig record field — `id` shadows Prelude)
- [x] `bscName` → `name` (BlogSeriesConfig record field)
- [x] `bscIcon` → `icon` (BlogSeriesConfig record field)
- [x] `bscAuthor` → `author` (BlogSeriesConfig record field)
- [x] `bscBaseUrl` → `baseUrl` (BlogSeriesConfig record field)
- [x] `bscPriorityUser` → `priorityUser` (BlogSeriesConfig record field)
- [x] `bscNavLink` → `navLink` (BlogSeriesConfig record field)
- [x] `bscScheduleTime` → `scheduleTime` (BlogSeriesConfig record field)
- [x] `bscContextQueries` → `contextQueries` (BlogSeriesConfig record field)

#### Frontmatter.hs

- [x] `ls` → `contentLines` (local variable in `parseFrontmatter`)
- [x] `fm` → `frontmatter` (local binding for `parseFrontmatter` result in `deriveUrl`, `readReflection`, and `readNote`)

#### Text.hs

- [x] `xs` → `elements` (parameter in `findLastIndex`, `removeAt`, and lambda in `strategy4`)
- [x] `len` → `postLength` (local variable in `validatePostLength`)
- [x] `p` → `predicate` (parameter in `findLastIndex`)
- [x] `lns` → `contentLines` (parameter in `fitWithStrategies`; local variable `contentLines` inside renamed to `preUrlLines` to avoid shadowing)
- [x] `urlIdx` → `urlIndex` (local variable in `fitWithStrategies`)
- [x] `ci` → `colonIndex` (pattern variable in `strategy3`)
- [x] `colonIdx` → `colonPosition` (local binding in `strategy3` — the `Maybe Int` holding the colon position)
- [x] `i` → `index` (parameter in `removeAt`)

#### Scheduler.hs

- [x] `fm` → `frontmatter` (local binding for frontmatter text in `needsRegeneration` and `parseFrontmatterText`)

#### InternalLinking/Masking.hs

- [x] `fm` → `frontmatter` (local binding for frontmatter text in `maskProtectedRegions`)
- [x] `fmBlock` → `frontmatterBlock` (local binding for the masked frontmatter block in `maskFrontmatter`)

#### InternalLinking/CandidateDiscovery.hs

- [x] `fm` → `frontmatter` (local binding for `parseFrontmatter` result in `contentTitle`)

#### SocialPosting/ContentDiscovery.hs

- [x] `fm` → `frontmatter` (local binding for `parseFrontmatter` result in `readContentNote`)

#### BlogPosts.hs

- [x] `fm` → `frontmatter` (local binding for `parseFrontmatter` result in `readPost`)

#### Gemini.hs

- [x] `req` → `request` (parameter name for `Request` in `generateContent`)

#### GcpAuth.hs

- [x] `bs` → `bytes` (parameter name for `ByteString` in `parseDerTag`, `parseDerInteger`, `parseDerLength`, `bytesToInteger`, and `decodePem`)

#### StaticGiscus.hs

- [x] `sgaLogin` → `login` (GqlAuthor record field — `sga` prefix)
- [x] `sgaUrl` → `url` (GqlAuthor record field — `sga` prefix)
- [x] `sgcBodyHtml` → `bodyHtml` (GqlComment record field — `sgc` prefix)
- [x] `sgcAuthor` → `author` (GqlComment record field — `sgc` prefix)
- [x] `sgcCreatedAt` → `createdAt` (GqlComment record field — `sgc` prefix)
- [x] `sgcnNodes` → `nodes` (GqlCommentsNode record field — `sgcn` prefix)
- [x] `sgdTitle` → `title` (GqlDiscussion record field — `sgd` prefix)
- [x] `sgdComments` → `comments` (GqlDiscussion record field — `sgd` prefix)
- [x] `sgpHasNextPage` → `hasNextPage` (GqlPageInfo record field — `sgp` prefix)
- [x] `sgpEndCursor` → `endCursor` (GqlPageInfo record field — `sgp` prefix)
- [x] `sgdpNodes` → `discussionNodes` (GqlDiscussionsPage record field — `sgdp` prefix — renamed `discussionNodes` not `nodes` to avoid same-module conflict with `GqlCommentsNode.nodes`)
- [x] `sgdpPageInfo` → `pageInfo` (GqlDiscussionsPage record field — `sgdp` prefix)
- [x] `sgrDiscussions` → `discussions` (GqlRepository record field — `sgr` prefix)
- [x] `sgdRepository` → `repository` (GqlData record field — `sgd` prefix)
- [x] `sgeMessage` → `message` (GqlError record field — `sge` prefix)
- [x] `sgrData` → `responseData` (GqlResponse record field — `sgr` prefix)
- [x] `sgrErrors` → `errors` (GqlResponse record field — `sgr` prefix)
- [x] `scAuthor` → `author` (StaticComment record field — `sc` prefix)
- [x] `scAuthorUrl` → `authorUrl` (StaticComment record field — `sc` prefix)
- [x] `scBodyHtml` → `bodyHtml` (StaticComment record field — `sc` prefix)
- [x] `scCreatedAt` → `createdAt` (StaticComment record field — `sc` prefix)

#### StaticGiscus.hs (local variables)

- [x] `idx` → `insertionPoint` (local binding for `findGiscusDiv` result in `injectStaticComments`)
- [x] `mAfter` → `maybeAfterCursor` (parameter in `fetchDiscussionPage` and `fetchAllDiscussions` inner helper)
- [x] `mPage` → `maybePage` (local binding for `fetchDiscussionPage` result in `fetchAllDiscussions`)
- [x] `acc` → `accumulatedDiscussions` (accumulator parameter in `fetchAllDiscussions` inner helper)
- [x] `newAcc` → `updatedDiscussions` (local binding for updated accumulator in `fetchAllDiscussions`)
- [ ] `go` → `paginatedFetch` (inner helper name in `fetchAllDiscussions` — `go` is opaque)

#### BlogPosts.hs

- [x] `bpFilename` → `filename` (BlogPost record field — `bp` prefix)
- [x] `bpDate` → `date` (BlogPost record field — `bp` prefix)
- [x] `bpTitle` → `title` (BlogPost record field — `bp` prefix)
- [ ] `bpBody` → `body` (BlogPost record field — `bp` prefix — requires renaming local `body` variable in BlogPrompt.hs)

#### Frontmatter.hs

- [ ] `fmLines` → `frontmatterLines` (local binding for parsed frontmatter lines in `parseFrontmatter`)

#### InternalLinking.hs

- [ ] `fmLines` → `frontmatterLines` (local binding for parsed frontmatter lines in `updateFrontmatterFields`)
- [ ] `updatedFm` → `updatedFrontmatter` (local binding for updated frontmatter lines in `updateFrontmatterFields`)

#### BlogImage.hs

- [ ] `fmLines` → `frontmatterLines` (local binding for parsed frontmatter lines in `updateFrontmatterFields` and `applyField`)
- [ ] `updatedFm` → `updatedFrontmatter` (local binding for updated frontmatter lines in `updateFrontmatterFields`)

#### ReflectionTitle.hs

- [ ] `fmLines` → `frontmatterLines` (parameter in `updateFmFields` and local binding in `updateContentWithTitle`)
- [ ] `updatedFm` → `updatedFrontmatter` (local binding in `updateContentWithTitle`)
- [ ] `updateFmFields` → `updateFrontmatterFields` (function name — `Fm` abbreviation)

#### SocialPosting/FrontmatterUpdate.hs

- [ ] `fmLines` → `frontmatterLines` (local binding for parsed frontmatter lines)

#### AiFiction.hs

- [ ] `fcModels` → `models` (FictionConfig record field — `fc` prefix)
- [ ] `fcNoteContent` → `noteContent` (FictionConfig record field — `fc` prefix)
- [ ] `frFiction` → `fiction` (FictionResult record field — `fr` prefix)
- [ ] `frModel` → `model` (FictionResult record field — `fr` prefix)
- [ ] `frUpdatedContent` → `updatedContent` (FictionResult record field — `fr` prefix)

#### ReflectionTitle.hs (record field prefixes)

- [ ] `rtcModels` → `models` (ReflectionTitleConfig record field — `rtc` prefix)
- [ ] `rtcNoteContent` → `noteContent` (ReflectionTitleConfig record field — `rtc` prefix)
- [ ] `rtcDate` → `date` (ReflectionTitleConfig record field — `rtc` prefix)
- [ ] `rtcRecentTitles` → `recentTitles` (ReflectionTitleConfig record field — `rtc` prefix)
- [ ] `rtrTitle` → `title` (ReflectionTitleResult record field — `rtr` prefix)
- [ ] `rtrFullTitle` → `fullTitle` (ReflectionTitleResult record field — `rtr` prefix)
- [ ] `rtrModel` → `model` (ReflectionTitleResult record field — `rtr` prefix)
- [ ] `rtrUpdatedContent` → `updatedContent` (ReflectionTitleResult record field — `rtr` prefix)

## Ordering Notes

- 🔤 Local variable renames (Phase 1) are safe and can be done in any order.
- 🏷️ Record field renames (Phase 2) require checking for name clashes within the same module. When a clash exists, move the record type to a dedicated sub-module and import it qualified.
- 🔢 Each step is a separate PR: one name, expanded everywhere in the codebase, with a passing build.
