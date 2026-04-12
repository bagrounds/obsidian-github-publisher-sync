# 📣 Social Posting — Three-Platform Social Media Pipeline

## 🎯 Overview

📋 Posts to Twitter, Bluesky, and Mastodon with platform-specific APIs and embed generation.
🧠 Implements five progressive text-fitting strategies to respect each platform's character limits.
🔗 Extracts OpenGraph metadata for rich link card embeds on Bluesky.
📝 Builds markdown embed sections for each platform to persist in Obsidian notes.

## 🔍 Content Discovery

📋 Content discovery uses a two-phase strategy to find notes that need social media posting.

### 🎯 Phase 1: Prior Day Reflection Priority

⏰ When the current time is past the posting hour (default 17:00 UTC / 9 AM PST), the system checks for yesterday's reflection.
✅ The prior day's reflection is posted if it has a creative title (not just the date) and has not yet been posted to all configured platforms.
🚫 If the reflection has an untitled (date-only) title, it is skipped.

### 🌐 Phase 2: BFS Content Discovery

🔍 When no prior day reflection is available (or it has already been posted), the system uses breadth-first search starting from the most recent reflection.
📊 BFS follows markdown links and Obsidian wiki links to discover linked content notes.
⏳ Reflections from date D are NOT eligible for posting until the posting hour on D+1. Non-reflection content is always eligible.
🚫 Index pages are never eligible for posting but are still traversed to discover linked content.
📋 At most one note is discovered per configured platform per run.
🔗 BFS always follows links from ALL visited nodes, including ineligible or non-postable content. 📄 This ensures that content reachable only through index pages, private notes, or stubs is still discoverable.

### 📏 Content Filters

🛡️ A note is postable only if it meets all of these criteria:
- 📄 Not an index page (filename is not `index.md`)
- 🏷️ Not flagged with `no_social: true` in frontmatter
- 📝 Not an untitled reflection (reflection whose title matches the date)
- 📐 Body content is at least 50 characters after stripping markup
- 🖼️ Not awaiting an image backfill (see below)

### 🖼️ Image Backfill Gate

🔍 Before posting, each candidate note is checked for image readiness using the same logic as the image backfill pipeline.
📂 A note is considered "awaiting image backfill" when all three conditions hold:
- 📁 Its parent directory is one of the configured image backfill content directories (from `imageBackfillContentIds`)
- 📄 Its filename passes `shouldHaveImage` (a markdown file not in the exclusion list)
- 🚫 Its body does not contain an embedded image (checked via `hasEmbeddedImage`)

✅ Notes that already have an image are posted normally.
✅ Notes that would never receive an image (files in directories outside the backfill set, excluded files, or non-markdown files) are posted normally.
⏭️ Notes awaiting an image are skipped, but BFS still follows their links to discover other postable content.
📊 Since image backfill runs at twice the rate of social posting (2 images per hour vs 1 post per 2 hours), the queue of image-ready content grows faster than the posting queue.

### 🔗 URL Validation and Auto-Fix

🌐 Before posting, each candidate note's URL is verified with an HTTP HEAD request via `checkUrlPublished`.
✅ If the URL returns a 2xx status, the note proceeds to posting.
🔧 If the frontmatter URL returns a 404, the system derives the correct URL from the file path using `urlFromFilePath` (format: `https://bagrounds.org/{relative-path-without-.md}`).
🔄 If the file-path-derived URL differs from the frontmatter URL and is live, the frontmatter `URL` property is automatically updated via `updateFrontmatterUrl` and the corrected note proceeds to posting.
🚫 If both the frontmatter URL and the file-path-derived URL return 404, the note is skipped but BFS still follows its links to discover other content.
📋 URL validation is injected into `FindContentConfig` via the optional `fccPublicationChecker` callback.
⚡ URL checks are only performed on notes that pass all other content filters (postable and eligible), avoiding unnecessary HTTP requests during BFS traversal.

## 🤖 Post Text Generation

📝 Post text is generated using a two-step sequential Gemini AI pipeline. 📡 Calls are made sequentially to avoid rate limits.

### ❓ Step 1: Question Generation

🤖 A discussion question is generated using `buildQuestionPrompt` with the question model (default: `gemini-3.1-flash-lite-preview`).
📏 The question budget is calculated to fit within the Bluesky character limit (300) after accounting for the title, URL, prefix, and tag allowance.
🎯 Questions are prefixed with `#AI Q: ` in the final post.

### 🏷️ Step 2: Tags Generation

🤖 Emoji topic tags are generated using `buildTagsPrompt` with the tags model (default: `gemma-3-27b-it`).
📊 Tags use the format: `📚 Topic | 🤖 AI | 🧠 Thinking` with 2-4 concise tags.

### 🔧 Assembly

📝 The question and tags are combined and assembled into the final post structure:
- 📌 Title (from note frontmatter)
- ❓ AI question with `#AI Q: ` prefix (if generated)
- 🏷️ Topic tags (if generated)
- 🔗 URL (from note frontmatter)

✂️ If the assembled post exceeds the Bluesky character limit, the question is automatically shortened via a follow-up LLM call.
📏 The final post is then fitted to each platform's specific character limit using five progressive text-fitting strategies.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🐦 Twitter | `haskell/src/Automation/Platforms/Twitter.hs` | 📤 Twitter v2 API posting with idempotency keys and oEmbed fallback |
| 🦋 Bluesky | `haskell/src/Automation/Platforms/Bluesky.hs` | 📤 AT Protocol posting with rich link cards and thumbnail uploads |
| 🐘 Mastodon | `haskell/src/Automation/Platforms/Mastodon.hs` | 📤 Mastodon REST API posting with iframe embed fallback |
| 🔍 OG Metadata | `haskell/src/Automation/Platforms/OgMetadata.hs` | 🌐 OpenGraph metadata extraction for link card generation |
| 📝 Embed Sections | `haskell/src/Automation/EmbedSection.hs` | 🔧 Higher-order section builders for embed markdown |
| ✂️ Text Fitting | `haskell/src/Automation/Text.hs` | 📏 Unicode-aware text fitting with five progressive strategies |

### 🔄 Data Flow

```
📄 Reflection note content
         ↓
🤖 Gemini generates social post text
         ↓
✂️ fitPostToLimit(text, platformMax)
         ↓
   ├─ 🐦 Twitter path:
   │    ├─ calculateTweetLength() → account for 23-char URL rule
   │    ├─ postTweet() → v2 API with UUID idempotency key
   │    └─ getEmbedHtml() → oEmbed or local blockquote fallback
   │
   ├─ 🦋 Bluesky path:
   │    ├─ fetchOgMetadata() → title, description, imageUrl
   │    ├─ fetchImageAsBuffer() → thumbnail for link card
   │    ├─ postToBluesky() → AT Protocol with RichText facets
   │    └─ getBlueskyEmbedHtml() → oEmbed with retry, placeholder link fallback
   │
   └─ 🐘 Mastodon path:
        ├─ postToMastodon() → REST API public status
        └─ getMastodonEmbedHtml() → oEmbed or iframe fallback
         ↓
📝 createSectionBuilder(header)(content, embedHtml)
         ↓
💾 Append embed sections to Obsidian note
```

## 🐦 Twitter Integration

📤 Posts via the Twitter v2 API using OAuth 1.0a credentials with four keys: apiKey, apiSecret, accessToken, and accessSecret.
🔑 Each request includes a UUID-based `X-Idempotency-Key` header to prevent duplicate tweets on retry after transient 503 errors.
🔄 Retries up to 3 times with a 1000ms base delay on failure.
🖼️ Embed generation tries the oEmbed API first with a dark theme, then falls back to a locally generated blockquote HTML.
📏 URLs always count as 23 characters regardless of actual length due to Twitter's t.co shortening rule.

## 🦋 Bluesky Integration

📤 Posts via the AT Protocol API with automatic RichText facet detection for clickable links and mentions.
🖼️ Supports rich link card embeds with title, description, and optional thumbnail image upload.
🔗 Extracts DID and post ID from AT Protocol URIs using pure parsing functions.
⏳ Embed retrieval includes a propagation delay retry with up to 3 attempts and a 3-second initial and retry delay, since new posts may not be immediately available via oEmbed.
🔗 When oEmbed fails after all retries, a placeholder link to the Bluesky post is stored instead of a broken local embed.
🔄 On each social posting run, the system scans the vault for Bluesky sections containing placeholder links and attempts to regenerate them into proper oEmbed HTML.
📝 Local embed generation function (`generateLocalEmbed`) is retained for testing and potential manual use, but is no longer used as the automatic fallback.

## 🐘 Mastodon Integration

📤 Posts via the Mastodon REST API with Bearer token authentication.
🌐 Instance-agnostic design extracts the instance URL from post URLs for API calls.
📝 Creates public, English-language statuses with JSON body containing status, visibility, and language fields.
🔁 Uses UUID-based Idempotency-Key headers for retry safety against duplicate posts.
🖼️ Embed generation tries the instance's oEmbed endpoint first, then falls back to an iframe-based embed.
🔧 Pure URL parsing functions extract instance URL, status ID, and username from post URLs.
🏗️ The `haskell/src/Automation/Platforms/Mastodon.hs` module follows the same error handling patterns as the Twitter module, using `Either Text` return types and `HttpCodeException` for transient failure retry.
🔌 All IO functions accept a `Manager` parameter for HTTP connection pooling.

## 🔍 OpenGraph Metadata Extraction

🌐 `fetchOgMetadata` fetches a URL via HTTPS and decodes the response body as UTF-8 using `decodeUtf8Lenient` for robust handling of non-UTF-8 bytes.
🔍 `extractOgProperty` parses `<meta property="og:*">` tags to extract title, description, and image URL by searching for `property="og:{name}" content="` markers.
🛡️ Returns partial results on incomplete metadata (`Nothing` for missing properties).
📷 `fetchImageAsBuffer` retrieves images as lazy ByteString buffers for blob uploads.
🏷️ `detectContentType` infers MIME type from the image URL extension (webp, png, gif, svg) with jpeg as the default fallback. Used by the Bluesky blob upload to set the correct `Content-Type` header.

## 📝 Embed Section Builders

🔧 `createSectionBuilder` is a higher-order function that returns a pure function for building markdown sections with a given header.
📝 Three platform-specific builders are created from this factory: `buildTweetSection`, `buildBlueskySection`, and `buildMastodonSection`.
🔧 `createSectionAppender` is a parallel higher-order function that returns an effectful function for appending sections to files with idempotency checks.
🛡️ Appenders skip writing if the section header already exists in the file content.
📏 Separator logic intelligently adds single or double newlines based on whether the existing content already ends with a newline.

## ✂️ Text Fitting Strategies

📏 The `fitPostToLimit` function implements five progressive strategies to fit text within a platform's character limit.

🔢 The strategies are applied in order, stopping as soon as the text fits.

1️⃣ Strategy one removes pipe-separated topic tags from right to left, trimming the least important tags first.
2️⃣ Strategy two removes the entire topic line and its preceding blank line.
3️⃣ Strategy three strips the subtitle from the title by removing everything after the first colon.
4️⃣ Strategy four removes the title entirely along with its following blank line.
5️⃣ Strategy five truncates the remaining content with an ellipsis while always preserving the URL line.

📏 `countGraphemes` uses the `Intl.Segmenter` API for Unicode-aware character counting where complex emoji like family sequences and flag pairs each count as one grapheme.
📐 `calculateTweetLength` accounts for Twitter's t.co URL shortening rule where every URL counts as exactly 23 characters regardless of actual length.
✅ `validateTweetLength` checks against Twitter's 280-character limit using the t.co-adjusted length.

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `countGraphemes(text)` | 📏 Count Unicode grapheme clusters using Intl.Segmenter |
| `truncateToGraphemeLimit(text, max)` | ✂️ Truncate text to grapheme limit with ellipsis |
| `calculateTweetLength(text)` | 📐 Calculate tweet length with 23-char URL rule |
| `validateTweetLength(text)` | ✅ Validate text against 280-char Twitter limit |
| `fitPostToLimit(text, max)` | 🎯 Apply five progressive strategies to fit text |
| `extractBlueskyPostId(uri)` | 🔗 Extract post ID from AT Protocol URI |
| `extractBlueskyDid(uri)` | 🔗 Extract DID from AT Protocol URI |
| `buildBlueskyPostUrl(did, postId)` | 🔗 Construct Bluesky profile post URL |
| `buildPlaceholderLink(postUrl)` | 🔗 Generate a placeholder link for failed oEmbed |
| `isPlaceholderLink(section)` | 🔍 Detect whether a Bluesky section contains a placeholder link |
| `replacePlaceholderWithEmbed(content, embedHtml)` | 🔄 Replace a placeholder link with oEmbed HTML in file content |
| `extractMastodonInstanceUrl(postUrl)` | 🌐 Extract instance URL from Mastodon post URL |
| `extractMastodonStatusId(postUrl)` | 🔗 Extract status ID from Mastodon post URL |
| `extractMastodonUsername(postUrl)` | 👤 Extract username from Mastodon post URL |
| `generateLocalEmbed(tweetId, text, date)` | 🖼️ Generate local Twitter blockquote HTML |
| `generateLocalBlueskyEmbed(uri, text, date, handle, cid?)` | 🖼️ Generate local Bluesky blockquote HTML |
| `generateLocalMastodonEmbed(postUrl, text, date)` | 🖼️ Generate local Mastodon iframe HTML |
| `createSectionBuilder(header)` | 🔧 Factory for pure embed section builders |
| `buildTweetSection(content, html)` | 📝 Build tweet embed markdown section |
| `buildBlueskySection(content, html)` | 📝 Build Bluesky embed markdown section |
| `buildMastodonSection(content, html)` | 📝 Build Mastodon embed markdown section |
| `urlFromFilePath(relativePath)` | 🔗 Derive canonical URL from relative file path |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `checkUrlPublished(url)` | 🌐 HTTP HEAD request to verify a URL returns 2xx status |
| `validateNoteUrl(checker, note)` | 🔧 Validate note URL, auto-fix stale frontmatter if file-path URL is live |
| `updateFrontmatterUrl(filePath, newUrl)` | 📝 Update or insert the URL property in a note's YAML frontmatter |
| `postTweet(text, credentials)` | 🐦 Post tweet via v2 API with idempotency key |
| `deleteTweet(tweetId, credentials)` | 🗑️ Delete tweet by ID |
| `fetchOEmbed(tweetUrl, options?)` | 🖼️ Fetch Twitter oEmbed HTML |
| `getEmbedHtml(tweetId, text, date)` | 🖼️ Get Twitter embed with oEmbed-to-local fallback |
| `postToBluesky(text, credentials, linkCard?)` | 🦋 Post to Bluesky with optional rich link card |
| `deleteBlueskyPost(uri, credentials)` | 🗑️ Delete Bluesky post by URI |
| `fetchBlueskyOEmbed(postUrl)` | 🖼️ Fetch Bluesky oEmbed HTML |
| `getBlueskyEmbedHtml(uri)` | 🖼️ Get Bluesky embed with propagation retry, placeholder link fallback |
| `postToMastodon(text, credentials)` | 🐘 Post to Mastodon via REST API |
| `deleteMastodonPost(statusId, credentials)` | 🗑️ Delete Mastodon status |
| `fetchMastodonOEmbed(postUrl)` | 🖼️ Fetch Mastodon oEmbed HTML |
| `getMastodonEmbedHtml(postUrl, text, date)` | 🖼️ Get Mastodon embed with oEmbed-to-iframe fallback |
| `regenerateBlueskyEmbeds(manager, vaultDir)` | 🔄 Scan vault for Bluesky placeholder links and regenerate oEmbed HTML |
| `fetchOgMetadata(url)` | 🔍 Extract OpenGraph metadata from URL via UTF-8 decoded HTTP response |
| `extractOgProperty(property, html)` | 🔍 Pure extraction of a single OG property from HTML text |
| `fetchImageAsBuffer(imageUrl)` | 📷 Fetch image as lazy ByteString buffer |
| `detectContentType(imageUrl)` | 🏷️ Infer MIME type from image URL extension |
| `createSectionAppender(header)` | 📝 Factory for effectful section appenders with idempotency |

## 🧪 Testing

🔬 Tests in `haskell/test/Automation/TextTest.hs` with 29 test cases covering:
- 📏 `countGraphemes`: ASCII, emoji, flags, mixed, family emoji, accented characters
- ✂️ `truncateToGraphemeLimit`: unchanged, at limit, truncation with ellipsis, emoji edge cases
- 📐 `calculateTweetLength`: plain text, single URL, multiple URLs, empty input
- ✅ `validateTweetLength`: short text, at 280, over 280
- 🎯 `fitPostToLimit`: unchanged, tag removal, URL preservation, full strategy cascade

🔬 Tests in `haskell/test/Automation/EmbedSectionTest.hs` with 9 test cases covering:
- 🔧 `createSectionBuilder`: header inclusion, newline handling
- 📝 Platform builders: correct header assignment for all three platforms
- 🛡️ `createSectionAppender`: file append and idempotency check
- 🏭 Factory consistency: factory-created builders match direct builders

🔬 Tests in `haskell/test/Automation/OgMetadataTest.hs` with 16 test cases covering:
- 🔍 `extractOgProperty`: title, description, image, URL extraction from HTML
- 🚫 Missing properties, empty HTML, large HTML offsets
- 🎵 Emoji and special character handling in OG content
- 🔗 Real-world Quartz HTML structure with CSS/JS interleaved
- 🏷️ `detectContentType`: webp, png, gif, svg, jpeg fallback, case insensitivity
- 🎲 Property-based tests for roundtripping and MIME type validity
