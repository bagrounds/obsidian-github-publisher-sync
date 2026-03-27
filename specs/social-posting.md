# 📣 Social Posting — Three-Platform Social Media Pipeline

## 🎯 Overview

📋 Posts to Twitter, Bluesky, and Mastodon with platform-specific APIs and embed generation.
🧠 Implements five progressive text-fitting strategies to respect each platform's character limits.
🔗 Extracts OpenGraph metadata for rich link card embeds on Bluesky.
📝 Builds markdown embed sections for each platform to persist in Obsidian notes.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🐦 Twitter | `scripts/lib/platforms/twitter.ts` | 📤 Twitter v2 API posting with idempotency keys and oEmbed fallback |
| 🦋 Bluesky | `scripts/lib/platforms/bluesky.ts` | 📤 AT Protocol posting with rich link cards and thumbnail uploads |
| 🐘 Mastodon | `scripts/lib/platforms/mastodon.ts` | 📤 Mastodon REST API posting with iframe embed fallback |
| 🔍 OG Metadata | `scripts/lib/platforms/og-metadata.ts` | 🌐 OpenGraph metadata extraction for link card generation |
| 📝 Embed Sections | `scripts/lib/embed-section.ts` | 🔧 Higher-order section builders for embed markdown |
| ✂️ Text Fitting | `scripts/lib/text.ts` | 📏 Unicode-aware text fitting with five progressive strategies |

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
   │    └─ getBlueskyEmbedHtml() → oEmbed with propagation retry
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
⏳ Embed retrieval includes a propagation delay retry with up to 2 attempts and a 2-second retry delay, since new posts may not be immediately available via oEmbed.
📝 Local embed fallback generates blockquote HTML with `data-bluesky-uri` and `data-bluesky-cid` attributes.

## 🐘 Mastodon Integration

📤 Posts via the Mastodon REST API with Bearer token authentication.
🌐 Instance-agnostic design extracts the instance URL from post URLs for API calls.
📝 Creates public, English-language statuses with JSON body containing status, visibility, and language fields.
🔁 Uses UUID-based Idempotency-Key headers for retry safety against duplicate posts.
🖼️ Embed generation tries the instance's oEmbed endpoint first, then falls back to an iframe-based embed.
🔧 Pure URL parsing functions extract instance URL, status ID, and username from post URLs.
🏗️ Haskell implementation in `haskell/src/Automation/Platforms/Mastodon.hs` follows the same error handling patterns as the Twitter module, using `Either Text` return types and `HttpCodeException` for transient failure retry.
🔌 All IO functions accept a `Manager` parameter for HTTP connection pooling.

## 🔍 OpenGraph Metadata Extraction

🌐 `fetchOgMetadata` parses `<meta property="og:*">` tags from any URL to extract title, description, and image URL.
🔄 Handles both attribute orders: `property` before `content` and `content` before `property`.
⏱️ Uses a 10-second fetch timeout with `AbortSignal.timeout` to prevent hanging.
🛡️ Returns partial results on incomplete metadata and an empty object on complete failure.
📷 `fetchImageAsBuffer` retrieves images as Uint8Array buffers with MIME type detection from Content-Type headers.

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

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `postTweet(text, credentials)` | 🐦 Post tweet via v2 API with idempotency key |
| `deleteTweet(tweetId, credentials)` | 🗑️ Delete tweet by ID |
| `fetchOEmbed(tweetUrl, options?)` | 🖼️ Fetch Twitter oEmbed HTML |
| `getEmbedHtml(tweetId, text, date)` | 🖼️ Get Twitter embed with oEmbed-to-local fallback |
| `postToBluesky(text, credentials, linkCard?)` | 🦋 Post to Bluesky with optional rich link card |
| `deleteBlueskyPost(uri, credentials)` | 🗑️ Delete Bluesky post by URI |
| `fetchBlueskyOEmbed(postUrl)` | 🖼️ Fetch Bluesky oEmbed HTML |
| `getBlueskyEmbedHtml(uri, text, date, handle, cid?)` | 🖼️ Get Bluesky embed with propagation retry |
| `postToMastodon(text, credentials)` | 🐘 Post to Mastodon via REST API |
| `deleteMastodonPost(statusId, credentials)` | 🗑️ Delete Mastodon status |
| `fetchMastodonOEmbed(postUrl)` | 🖼️ Fetch Mastodon oEmbed HTML |
| `getMastodonEmbedHtml(postUrl, text, date)` | 🖼️ Get Mastodon embed with oEmbed-to-iframe fallback |
| `fetchOgMetadata(url)` | 🔍 Extract OpenGraph metadata from URL |
| `fetchImageAsBuffer(imageUrl)` | 📷 Fetch image as Uint8Array buffer with MIME type |
| `createSectionAppender(header)` | 📝 Factory for effectful section appenders with idempotency |

## 🧪 Testing

🔬 Tests in `scripts/lib/text.test.ts` with 29 test cases covering:
- 📏 `countGraphemes`: ASCII, emoji, flags, mixed, family emoji, accented characters
- ✂️ `truncateToGraphemeLimit`: unchanged, at limit, truncation with ellipsis, emoji edge cases
- 📐 `calculateTweetLength`: plain text, single URL, multiple URLs, empty input
- ✅ `validateTweetLength`: short text, at 280, over 280
- 🎯 `fitPostToLimit`: unchanged, tag removal, URL preservation, full strategy cascade

🔬 Tests in `scripts/lib/embed-section.test.ts` with 9 test cases covering:
- 🔧 `createSectionBuilder`: header inclusion, newline handling
- 📝 Platform builders: correct header assignment for all three platforms
- 🛡️ `createSectionAppender`: file append and idempotency check
- 🏭 Factory consistency: factory-created builders match direct builders
