# Social Post Automation Design Document

## Overview

Automated daily social posting system for the bagrounds.org digital garden. A GitHub Actions
workflow runs on a cron schedule each morning, reads **yesterday's** reflection note from the
repo, uses Google Gemini to generate a post, publishes it to **Twitter/X** and **Bluesky**,
fetches the embed HTML, and writes the updated note back to the **Obsidian vault** via
[Obsidian Headless Sync](https://help.obsidian.md/sync/headless).

Both social platforms are optional — the script posts to whichever platforms have credentials
configured. Platform failures are logged but don't crash the pipeline.

The user reviews the change in Obsidian (e.g. on their phone) and publishes it to this repo via
the Enveloppe plugin, at which point the deploy workflow rebuilds and publishes the site.

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  GitHub Actions  │────▶│  Read        │────▶│  Gemini API  │────▶│  Twitter API │
│  Cron Trigger    │     │  Yesterday's │     │  Generate    │     │  Post Tweet  │
│  (9 AM Pacific)  │     │  Reflection  │     │  Tweet Text  │     │              │
└─────────────────┘     └──────────────┘     └──────────────┘     └──────┬───────┘
                                                                         │
                        ┌──────────────┐     ┌──────────────┐           │
                        │  Obsidian    │◀────│  oEmbed API  │◀──────────┘
                        │  Headless    │     │  Get Embed   │
                        │  Sync: Pull, │     │  HTML        │
                        │  Update,     │     └──────────────┘
                        │  Push        │
                        └──────┬───────┘
                               │
                        ┌──────▼───────┐     ┌──────────────┐
                        │  User Reviews│────▶│  Enveloppe   │
                        │  in Obsidian │     │  Plugin:     │
                        │  (phone)     │     │  Publish to  │
                        └──────────────┘     │  GitHub      │
                                             └──────────────┘
```

## Data Flow

### Step 1: Trigger & Checkout

- GitHub Actions cron fires daily at **17:00 UTC** (9:00 AM PST / 10:00 AM PDT)
- Workflow checks out the repository so we can read the reflection file
- Also supports manual dispatch (`workflow_dispatch`) with a custom date and dry-run mode

### Step 2: Read Yesterday's Reflection

- Script reads `content/reflections/YYYY-MM-DD.md` where date = **yesterday** (UTC)
- We post the previous day's reflection so it's finalized (no risk of mid-day edits)
- Parses YAML frontmatter to extract: `title`, `URL`, `tags`
- Extracts markdown body content (sections, book references, topics, AI fiction)
- If no reflection exists for that date, the workflow exits gracefully

### Step 3: Generate Tweet with Gemini

- Sends reflection title, URL, and content summary to Google Gemini API
- System prompt instructs Gemini to generate a tweet that:
  - Includes the reflection title
  - Includes relevant emoji tags summarizing the topics
  - Includes the reflection URL
  - Stays within Twitter's 280-character limit
  - Matches the style of existing tweets (title on first line, tags on second, URL last)
- Model: configurable via `GEMINI_MODEL` env var (default: `gemma-3-27b-it` — generous free tier)

### Step 4a: Post Tweet via Twitter API (optional)

- Uses Twitter API v2 with OAuth 1.0a authentication
- Posts the generated text
- Returns the tweet ID from the response
- **Non-fatal**: If Twitter fails (e.g. persistent 503), logs the error and continues
- Uses `X-Idempotency-Key` header for safe retries on 503

### Step 4b: Post to Bluesky via AT Protocol API (optional)

- Uses the `@atproto/api` package with app password authentication
- Posts the same generated text to Bluesky
- Uses `RichText.detectFacets()` to auto-detect URLs and mentions in the text, generating proper facet annotations so links are rendered as clickable hyperlinks in Bluesky clients
- Attaches an `app.bsky.embed.external` embed (link card) with the reflection's URL, title, and description so Bluesky renders a website preview card below the post
- Returns the post URI and CID from the response
- **Non-fatal**: If Bluesky fails, logs the error and continues

### Step 5: Get Embed HTML

- For successful Twitter posts: calls Twitter's oEmbed endpoint `https://publish.twitter.com/oembed`
- For successful Bluesky posts: calls Bluesky's oEmbed endpoint `https://embed.bsky.app/oembed`
- Falls back to generating embed code locally if oEmbed APIs are unavailable

### Step 6: Update Note in Obsidian Vault via Headless Sync

- Installs [`obsidian-headless`](https://github.com/obsidianmd/obsidian-headless) globally
- Authenticates using `OBSIDIAN_AUTH_TOKEN` environment variable
- Runs `ob sync-setup` to connect to the remote vault
- Kills any lingering `ob` processes and removes stale `.sync.lock` (prevents "Another sync instance" errors)
- Runs `ob sync` to pull the latest vault content to a temp directory
- Reads the reflection note from the synced vault
- Appends `## 🐦 Tweet` section (if Twitter succeeded) and/or `## 🦋 Bluesky` section (if Bluesky succeeded)
- Kills lingering processes and removes lock again before push
- Runs `ob sync` again to push the change back to Obsidian Sync
- The user sees the update on their phone (or any Obsidian device) and reviews it

**Why Obsidian Headless Sync instead of git commit?** The Enveloppe plugin performs one-way
sync from Obsidian → GitHub. If we committed directly to the repo, the next Enveloppe publish
would overwrite our changes. By writing to the Obsidian vault via Headless Sync, the change
becomes part of the canonical source and flows through the normal publish pipeline.

**Why Headless Sync instead of the Local REST API?** The Local REST API requires the Obsidian
desktop app to be running with a tunnel (ngrok/Cloudflare) — fragile if the laptop is
unplugged, restarted, etc. Headless Sync is the official, server-side approach that works
reliably from CI without any dependency on a running desktop machine.

## File Structure

```
scripts/
  tweet-reflection.ts       # Main automation script
  tweet-reflection.test.ts  # Unit, property-based, and integration tests
.github/
  workflows/
    tweet-reflection.yml    # GitHub Actions cron workflow
docs/
  tweet-automation-design.md     # This document
  tweet-automation-notes.md      # Planning & implementation notes
```

## Environment Variables & Secrets

### Required GitHub Actions Secrets

| Secret Name | Description | How to Obtain |
|---|---|---|
| `GEMINI_API_KEY` | Google Gemini API Key | Google AI Studio → API Keys |
| `OBSIDIAN_AUTH_TOKEN` | Obsidian account auth token | Run `ob login` locally, then extract from credentials file |
| `OBSIDIAN_VAULT_NAME` | Remote vault name or ID | Run `ob sync-list-remote` to see vault names |

### Optional Secrets (Social Platforms)

At least one social platform should be configured. Each platform requires all of its secrets to be set.

| Secret Name | Description | How to Obtain |
|---|---|---|
| `TWITTER_API_KEY` | OAuth 1.0a **Consumer Key** | X Developer Portal → App → Keys and Tokens → Consumer Keys → API Key |
| `TWITTER_API_SECRET` | OAuth 1.0a **Consumer Secret** | X Developer Portal → App → Keys and Tokens → Consumer Keys → API Secret |
| `TWITTER_ACCESS_TOKEN` | OAuth 1.0a **Access Token** | X Developer Portal → App → Keys and Tokens → Authentication Tokens → Access Token |
| `TWITTER_ACCESS_SECRET` | OAuth 1.0a **Access Token Secret** | X Developer Portal → App → Keys and Tokens → Authentication Tokens → Access Token Secret |
| `BLUESKY_IDENTIFIER` | Bluesky handle or DID | Your Bluesky handle (e.g. `bagrounds.bsky.social`) |
| `BLUESKY_APP_PASSWORD` | Bluesky App Password | Bluesky Settings → App Passwords → Add App Password |

### Optional Secrets

| Secret Name | Description | When Needed |
|---|---|---|
| `OBSIDIAN_VAULT_PASSWORD` | E2EE vault password | Only if vault uses end-to-end encryption |

### Optional Environment Variables

These are non-secret configuration values. Set them as **repository variables** (Settings → Secrets and variables → Actions → Variables tab).

| Variable Name | Description | Default |
|---|---|---|
| `GEMINI_MODEL` | Google AI model name | `gemma-3-27b-it` |

### How to Set GitHub Actions Secrets

1. Navigate to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Enter the **Name** (e.g., `TWITTER_API_KEY`) and **Value**
5. Click **Add secret**
6. Repeat for each secret listed above

### How to Obtain Credentials

#### Twitter/X API Credentials (OAuth 1.0a)

> **Important:** We use OAuth **1.0a** credentials — NOT OAuth 2.0, and NOT the Bearer Token.
> The X Developer Portal shows multiple credential types; make sure you use the right ones.

The dashboard's **OAuth 1.0 Keys** section shows two entries — **Consumer Key** and
**Access Token** — but each is actually a **pair** (key + secret). When you click
**Regenerate**, the dashboard reveals both values. You need all **4 values** total:

1. Go to [developer.x.com](https://developer.x.com/) and sign in with the `@bagrounds` account
2. Navigate to your App → **Keys and Tokens** tab
3. Under **OAuth 1.0 Keys**:
   - **Consumer Key** — click **Regenerate**. The dialog shows two values:
     - **API Key** → save as `TWITTER_API_KEY`
     - **API Key Secret** → save as `TWITTER_API_SECRET`
   - **Access Token** — click **Regenerate** (ensure Read+Write permissions first). The dialog shows two values:
     - **Access Token** → save as `TWITTER_ACCESS_TOKEN`
     - **Access Token Secret** → save as `TWITTER_ACCESS_SECRET`
4. **Do NOT use** the OAuth 2.0 Client ID/Secret or the Bearer Token — those are for different
   authentication flows and won't work for posting tweets

> **Why 4 secrets?** OAuth 1.0a requires two credential pairs: the *app credentials*
> (Consumer Key + Secret identify your app) and the *user credentials* (Access Token + Secret
> authorize acting as `@bagrounds`). The `twitter-api-v2` library needs all four to sign
> requests. The dashboard groups them into 2 entries but each contains 2 values.

#### Google Gemini API Key

1. Go to [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Sign in with your Google account
3. Click **Create API Key**
4. Select or create a Google Cloud project
5. Copy the generated key → save as `GEMINI_API_KEY`

#### Bluesky Credentials (App Password)

> **Note:** Bluesky uses app passwords for API access — simpler than OAuth. No developer
> portal or app registration needed.

1. Log in to [bsky.app](https://bsky.app/) with your account
2. Go to **Settings** → **Privacy and Security** → **App Passwords**
3. Click **Add App Password**
4. Give it a name (e.g. "GitHub Actions Bot")
5. Copy the generated password → save as `BLUESKY_APP_PASSWORD`
6. Your handle (e.g. `bagrounds.bsky.social`) → save as `BLUESKY_IDENTIFIER`

> **Why app passwords?** App passwords are scoped credentials that can be revoked
> independently without affecting your main account password. They're the recommended
> approach for bots and automation on Bluesky.

#### Obsidian Headless Sync Credentials

> **Prerequisites:**
> - An active [Obsidian Sync subscription](https://obsidian.md/sync)
> - Node.js **22 or later** (required by obsidian-headless)

1. Install obsidian-headless:
   ```shell
   npm install -g obsidian-headless
   ```
2. Log in to your Obsidian account:
   ```shell
   ob login
   ```
3. List your remote vaults to get the vault name:
   ```shell
   ob sync-list-remote
   ```
   Save the vault name as `OBSIDIAN_VAULT_NAME`
4. Extract your auth token. After `ob login`, the token is stored in your system keychain
   or in `~/.config/obsidian-headless/`. You can also use the `OBSIDIAN_AUTH_TOKEN`
   environment variable — run `ob login` interactively once, then check the
   [Obsidian forum thread on extracting the token](https://forum.obsidian.md/t/headless-sync-how-to-get-obsidian-auth-token-variable/111740)
   for the exact steps for your OS. Save the token value as `OBSIDIAN_AUTH_TOKEN`
5. If your vault uses end-to-end encryption, save the password as `OBSIDIAN_VAULT_PASSWORD`

For more details see the [Obsidian Headless docs](https://help.obsidian.md/headless) and
the [Headless Sync guide](https://help.obsidian.md/sync/headless).

## Tweet Format

The generated tweet follows the pattern observed in existing reflections:

```
{Title with emojis}

{Emoji tags summarizing topics}
{Reflection URL}
```

Example:
```
2026-03-05 | 😴🧠💤 Tired 🤖 Murderbot 📺

😴 Mental Health | 🤖 Sci-Fi | 📺 Video Essays
https://bagrounds.org/reflections/2026-03-05
```

## Embed Code Format

### Twitter Embed

The embed code follows the exact pattern used in existing reflection files:

```html
## 🐦 Tweet
<blockquote class="twitter-tweet" data-theme="dark"><p lang="en" dir="ltr">{tweet text with HTML entities}</p>&mdash; Bryan Grounds (@bagrounds) <a href="https://twitter.com/bagrounds/status/{tweet_id}?ref_src=twsrc%5Etfw">{date}</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
```

### Bluesky Embed

The Bluesky embed code follows the pattern used in existing content:

```html
## 🦋 Bluesky
<blockquote class="bluesky-embed" data-bluesky-uri="at://{did}/app.bsky.feed.post/{post_id}" data-bluesky-embed-color-mode="system"><p lang="en">{post text}</p>&mdash; Bryan Grounds (<a href="https://bsky.app/profile/{did}?ref_src=embed">@bagrounds.bsky.social</a>) <a href="https://bsky.app/profile/{did}/post/{post_id}?ref_src=embed">{date}</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>
```

## Error Handling

| Scenario | Behavior |
|---|---|
| No reflection for yesterday | Exit gracefully with info log |
| Reflection already has both embed sections | Skip (idempotent) |
| Gemini API failure | Exit with error, no posts made |
| Twitter API 5xx (e.g. 503) | Log error (non-fatal), retry v2 up to 3× with 1s exponential backoff using `X-Idempotency-Key`, continue to Bluesky |
| Twitter API 4xx (auth/bad request) | Log error (non-fatal), no retry, continue to Bluesky |
| Twitter credentials not configured | Skip Twitter, continue to Bluesky |
| Bluesky API failure | Log error (non-fatal), continue |
| Bluesky credentials not configured | Skip Bluesky, continue |
| Bluesky oEmbed 404 on fresh post | Wait 3s for propagation, retry once after 5s, fall back to local embed |
| oEmbed API failure (either platform) | Fall back to locally generated embed code |
| Obsidian Sync "already running" lock | Kill lingering `ob` processes + remove `.sync.lock` before each sync, retry on lock contention |
| Obsidian Sync failure | Exit with error (posts already made; re-run will skip posting and retry sync) |

### Architecture: Parallel Platform Posting

Social platform posts (Twitter + Bluesky) run in **parallel** using `Promise.allSettled`.
Each platform's posting task includes the API post call and embed HTML generation.
Failures on one platform don't affect the other. Results are collected after all tasks settle.

### 5 Whys: Bluesky oEmbed 404 on Fresh Posts

1. **Why did oEmbed return 404?** The Bluesky oEmbed API at `embed.bsky.app/oembed` didn't recognize the post URL.
2. **Why wasn't the post recognized?** Bluesky uses a decentralized architecture (AT Protocol); freshly created posts need time to propagate to the public embedding service.
3. **Why does propagation take time?** Read-after-write consistency isn't guaranteed across federated services — the post exists on the PDS but the oEmbed indexer hasn't processed it yet.
4. **Why didn't we account for this?** The oEmbed call was made immediately after posting, with no delay for propagation.
5. **Why was the fallback embed slightly different?** The local embed generator didn't include the `data-bluesky-cid` attribute present in oEmbed responses.

**Fix:** Added a 3-second delay before the first oEmbed attempt, retry after 5s on 404, and improved local embed generation to include the CID attribute from the post response. The local fallback now closely matches the format used in existing content files.

### 5 Whys: Obsidian Sync "Another Instance Already Running"

1. **Why did the sync fail?** The `ob sync` command reported "Another sync instance is already running for this vault."
2. **Why did it think another instance was running?** The `ob` CLI checks for both a `.sync.lock` file/directory AND running `ob` processes. Even after removing the lock file, a lingering process from `sync-setup` or a previous `sync` still holds the lock at the OS level.
3. **Why is there a lingering `ob` process?** `ob sync-setup` and `ob sync` may spawn background workers or keep file watchers alive. When called via Node's `execFile`, the parent resolves after stdout/stderr close, but child/grandchild processes may linger as orphans.
4. **Why doesn't `execFile` kill child processes on completion?** `execFile` only waits for the main process; it doesn't track or kill grandchild/orphan processes. The `ob` tool's internal architecture may fork workers that outlive the main CLI process.
5. **Why did the retry-after-5s approach also fail?** The 5s delay removed the lock file but didn't kill the lingering process. The orphaned `ob` process was still alive and still holding the lock when the retry fired. Simply removing the file was necessary but not sufficient.

**Fix:** Added `ensureSyncClean()` which combines two cleanup strategies: (a) `killObProcesses()` finds and terminates all lingering `ob` processes via `process.kill(pid, SIGTERM)`, and (b) `removeSyncLock()` removes the `.sync.lock` file/directory. This is called before BOTH pull and push operations, and again on retry after lock contention errors. The dual approach handles both file-based locks and process-based locks. See [obsidianmd/obsidian-headless#4](https://github.com/obsidianmd/obsidian-headless/issues/4).

**Research sources:**
- [Obsidian Headless Sync docs](https://help.obsidian.md/sync/headless) — `ob sync` is one-shot by default; `--continuous` keeps running
- [obsidianmd/obsidian-headless#4](https://github.com/obsidianmd/obsidian-headless/issues/4) — stale `.sync.lock` after hard kill blocks future syncs
- [Obsidian Forum: Use sync from a headless server](https://forum.obsidian.md/t/use-sync-from-a-headless-server/75006) — community advice on serializing sync and managing locks

### 5 Whys: Bluesky Links Not Rendered as Hyperlinks

1. **Why weren't URLs clickable in Bluesky posts?** The Bluesky client rendered them as plain text, not hyperlinks.
2. **Why does Bluesky not auto-detect links in plain text?** Unlike Twitter, Bluesky uses the AT Protocol's rich text model where links must be explicitly declared as "facets" (metadata marking substring ranges as links).
3. **Why weren't we sending facets?** The `agent.post({ text })` call only sent plain text without any facet annotations.
4. **Why does the AT Protocol require explicit facets?** The protocol separates content (text) from presentation (facets) to support structured, verifiable rich text across federated servers — there's no server-side link detection.
5. **Why didn't we notice earlier?** The post text was correct and the oEmbed embed displayed fine, but the actual Bluesky post (viewed on bsky.app) showed the URL as non-clickable plain text.

**Fix:** Added `RichText` from `@atproto/api` to detect facets before posting. The `detectFacets()` method scans the text for URLs and mentions, generating the correct byte-offset facet annotations that Bluesky clients need to render clickable links. See [Bluesky Rich Text docs](https://docs.bsky.app/docs/advanced-guides/post-richtext).

### 5 Whys: Bluesky Posts Missing Website Preview Card

1. **Why didn't the post show a website preview (link card)?** Bluesky displayed the URL as a text link but no preview card with title/description.
2. **Why didn't Bluesky auto-generate a preview?** Unlike Twitter, Bluesky does NOT auto-fetch OpenGraph metadata from URLs. The AT Protocol requires the client to explicitly provide link card data as an `app.bsky.embed.external` embed.
3. **Why doesn't Bluesky auto-fetch metadata?** This is a deliberate design decision for privacy and security reasons — Bluesky avoids making server-side requests to arbitrary URLs. The poster is responsible for supplying preview metadata.
4. **Why weren't we sending an embed?** The `agent.post()` call only included `text` and `facets` (for clickable links) but not the `embed` field needed for website card previews.
5. **Why does the external embed require title/description?** The `app.bsky.embed.external` schema requires `uri`, `title`, and `description` fields; `thumb` (image) is optional. This gives the poster full control over what appears in the card.

**Fix:** Added a `linkCard` parameter to `postToBluesky()` that creates an `app.bsky.embed.external` embed with the reflection's URL, title, and a description. The link card is now populated from the page's actual OpenGraph metadata via `fetchOgMetadata()` — this fetches `og:title`, `og:description`, and `og:image` from the reflection URL. If an `og:image` exists, it's downloaded, uploaded as a blob via `agent.uploadBlob()`, and included as the `thumb` field for a richer preview card with a thumbnail image. Falls back to reflection data if OG fetch fails. See [Bluesky Website Card Embeds](https://docs.bsky.app/docs/advanced-guides/posts#website-card-embeds).

## Testing Strategy

### Unit Tests (run without credentials)

- **File reading**: Parse reflection markdown, extract frontmatter and body
- **Tweet text generation**: Validate format, character limits, URL inclusion
- **Embed code generation**: Validate HTML structure, data-theme attribute
- **File update**: Verify correct placement of tweet section (local file operations)
- **Idempotency**: Verify skip when tweet already exists
- **Edge cases**: Missing file, empty content, special characters

### Property-Based Tests (run without credentials)

- Random reflection content → generated embed code is always valid HTML
- Random titles → tweet text always under 280 characters
- Random dates → file paths always resolve correctly

### Integration Tests (require credentials, self-cleaning)

- **End-to-end test**: Create temporary reflection, generate tweet, post to Twitter,
  verify embed, clean up (delete tweet)
- **Gemini integration**: Send prompt, verify response format
- **Twitter integration**: Post and delete test tweet
- **oEmbed integration**: Fetch embed for known tweet

Integration tests are gated behind the `RUN_INTEGRATION_TESTS` environment variable
and clean up all created resources (tweets, file modifications) after completion.

## Cron Schedule

```yaml
schedule:
  - cron: "0 17 * * *"  # Daily at 5:00 PM UTC = 9:00 AM PST / 10:00 AM PDT
```

The workflow posts the **previous day's** reflection. This ensures:
- The note is finalized (no risk of mid-day edits overwriting the tweet)
- The tweet goes out at a good time for visibility (morning Pacific time)

Note: GitHub Actions cron uses UTC. Because of daylight saving time, the Pacific time
varies: 9:00 AM PST (Nov–Mar) or 10:00 AM PDT (Mar–Nov).

## Security Considerations

- All API credentials stored as GitHub Actions secrets (encrypted at rest)
- Secrets never logged or exposed in workflow output
- The workflow only needs `contents: read` permission (no git write)
- Twitter OAuth 1.0a tokens are scoped to the specific user account
- Gemini API key has no billing by default (free tier)
- Obsidian auth token grants access to vault content — keep it secret
- `OBSIDIAN_VAULT_PASSWORD` (if used) protects E2EE vault decryption

## Libraries & Services Reference

### @atproto/api (npm)

- **Package**: [`@atproto/api`](https://www.npmjs.com/package/@atproto/api)
- **GitHub**: [bluesky-social/atproto](https://github.com/bluesky-social/atproto)
- **Docs**: [AT Protocol docs](https://atproto.com/), [Bluesky API docs](https://docs.bsky.app/)
- **Purpose**: Post to Bluesky via the AT Protocol API using app password authentication
- **Key methods**: `agent.login()`, `agent.post({ text })`, `agent.deletePost(uri)`

### twitter-api-v2 (npm)

- **Package**: [`twitter-api-v2`](https://www.npmjs.com/package/twitter-api-v2)
- **GitHub**: [PLhery/node-twitter-api-v2](https://github.com/PLhery/node-twitter-api-v2)
- **Docs**: [API examples](https://github.com/PLhery/node-twitter-api-v2/blob/master/doc/examples.md)
- **Purpose**: Post tweets via X/Twitter API v2 using OAuth 1.0a authentication
- **Key methods**: `client.v2.tweet(text)`, `client.v2.deleteTweet(id)`

### @google/generative-ai (npm)

- **Package**: [`@google/generative-ai`](https://www.npmjs.com/package/@google/generative-ai)
- **GitHub**: [google-gemini/generative-ai-js](https://github.com/google-gemini/generative-ai-js)
- **Docs**: [Gemini API docs](https://ai.google.dev/gemini-api/docs)
- **Purpose**: Generate tweet text from reflection content using Gemini 2.0 Flash
- **Key methods**: `genAI.getGenerativeModel()`, `model.generateContent()`

### obsidian-headless (npm)

- **Package**: [`obsidian-headless`](https://www.npmjs.com/package/obsidian-headless)
- **GitHub**: [obsidianmd/obsidian-headless](https://github.com/obsidianmd/obsidian-headless)
- **Docs**: [Headless Sync guide](https://help.obsidian.md/sync/headless),
  [Obsidian Headless overview](https://help.obsidian.md/headless)
- **Purpose**: Sync vault content from the command line without the desktop app
- **Key commands**: `ob login`, `ob sync-setup`, `ob sync`, `ob sync-list-remote`
- **Auth**: `OBSIDIAN_AUTH_TOKEN` env var for non-interactive CI use
- **Requires**: Node.js 22+, active [Obsidian Sync](https://obsidian.md/sync) subscription

### Bluesky oEmbed API

- **Endpoint**: `https://embed.bsky.app/oembed?url={post_url}`
- **Docs**: [Bluesky oEmbed](https://docs.bsky.app/docs/advanced-guides/oembed)
- **Purpose**: Fetch official embed HTML for a posted Bluesky post (no authentication required)

### Twitter oEmbed API

- **Endpoint**: `https://publish.twitter.com/oembed?url={tweet_url}`
- **Docs**: [X oEmbed](https://developer.x.com/en/docs/twitter-for-websites/oembed-api)
- **Purpose**: Fetch official embed HTML for a posted tweet (no authentication required)

### X/Twitter API v2

- **Docs**: [X API v2 Reference](https://developer.x.com/en/docs/twitter-api)
- **Auth guide**: [OAuth 1.0a](https://developer.x.com/en/docs/authentication/oauth-1-0a)
- **Purpose**: Post and manage tweets programmatically

### Obsidian Enveloppe Plugin

- **GitHub**: [Enveloppe/obsidian-enveloppe](https://github.com/Enveloppe/obsidian-enveloppe)
- **Purpose**: One-way sync from Obsidian vault → this GitHub repository
- **Note**: This is why we write to Obsidian (not to git) — Enveloppe would overwrite git changes

### Obsidian Sync

- **Docs**: [Obsidian Sync](https://help.obsidian.md/obsidian-sync/introduction)
- **Pricing**: [Plans and storage limits](https://help.obsidian.md/plans-and-billing/plans-and-storage-limits)
- **Purpose**: Cloud sync service that powers both the desktop app and Headless Sync
