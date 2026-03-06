# Tweet Automation Design Document

## Overview

Automated daily tweet publishing system for the bagrounds.org digital garden. A GitHub Actions
workflow runs on a cron schedule each morning, reads **yesterday's** reflection note from the
repo, uses Google Gemini to generate a tweet, posts it via the Twitter/X API, fetches the embed
HTML, and writes the updated note back to the **Obsidian vault** via the Obsidian Local REST API.

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
                        │  Local REST  │     │  Get Embed   │
                        │  API: Update │     │  HTML        │
                        │  Note        │     └──────────────┘
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
- Model: `gemini-2.0-flash` (fast, cost-effective)

### Step 4: Post Tweet via Twitter API

- Uses Twitter API v2 with OAuth 1.0a authentication
- Posts the generated tweet text
- Returns the tweet ID from the response

### Step 5: Get Embed HTML

- Calls Twitter's oEmbed endpoint: `https://publish.twitter.com/oembed`
- Parameters: tweet URL, dark theme
- Returns HTML blockquote embed code
- Falls back to generating embed code locally if oEmbed API is unavailable

### Step 6: Update Note in Obsidian Vault

- Reads the current note from the Obsidian vault via the **Local REST API**
- Appends `## 🐦 Tweet` section at the end of the note
- Writes the updated note back to Obsidian
- The user reviews the change in Obsidian and publishes to GitHub via Enveloppe

**Why Obsidian API instead of git commit?** The Enveloppe plugin performs one-way sync from
Obsidian → GitHub. If we committed directly to the repo, the next Enveloppe publish would
overwrite our changes. By writing to the Obsidian vault, the change becomes part of the
canonical source and flows through the normal publish pipeline.

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
| `TWITTER_API_KEY` | OAuth 1.0a **Consumer Key** | X Developer Portal → App → Keys and Tokens → Consumer Keys → API Key |
| `TWITTER_API_SECRET` | OAuth 1.0a **Consumer Secret** | X Developer Portal → App → Keys and Tokens → Consumer Keys → API Secret |
| `TWITTER_ACCESS_TOKEN` | OAuth 1.0a **Access Token** | X Developer Portal → App → Keys and Tokens → Authentication Tokens → Access Token |
| `TWITTER_ACCESS_SECRET` | OAuth 1.0a **Access Token Secret** | X Developer Portal → App → Keys and Tokens → Authentication Tokens → Access Token Secret |
| `GEMINI_API_KEY` | Google Gemini API Key | Google AI Studio → API Keys |
| `OBSIDIAN_API_URL` | Obsidian Local REST API base URL | Plugin settings (e.g. `https://your-tunnel.example.com:27124`) |
| `OBSIDIAN_API_KEY` | Obsidian Local REST API key | Plugin settings → Copy API Key |

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

1. Go to [developer.x.com](https://developer.x.com/) and sign in with the `@bagrounds` account
2. Create a new Project and App (or use existing)
3. Set App permissions to **Read and Write**
4. Under the **Keys and Tokens** tab:
   - **Consumer Keys** section:
     - Copy **API Key** → save as `TWITTER_API_KEY`
     - Copy **API Key Secret** → save as `TWITTER_API_SECRET`
   - **Authentication Tokens** section:
     - Click **Generate** under Access Token and Secret (ensure Read+Write permissions)
     - Copy **Access Token** → save as `TWITTER_ACCESS_TOKEN`
     - Copy **Access Token Secret** → save as `TWITTER_ACCESS_SECRET`
5. **Do NOT use** the OAuth 2.0 Client ID/Secret or the Bearer Token — those are for different
   authentication flows and won't work for posting tweets

#### Google Gemini API Key

1. Go to [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Sign in with your Google account
3. Click **Create API Key**
4. Select or create a Google Cloud project
5. Copy the generated key → save as `GEMINI_API_KEY`

#### Obsidian Local REST API

1. In Obsidian desktop, install the **Local REST API** community plugin
   ([GitHub](https://github.com/coddingtonbear/obsidian-local-rest-api))
2. Enable the plugin in Settings → Community Plugins
3. In the plugin settings, copy the **API Key** → save as `OBSIDIAN_API_KEY`
4. The default URL is `https://127.0.0.1:27124`
5. To make it accessible from GitHub Actions, expose it via a tunnel service
   (e.g. Cloudflare Tunnel, ngrok, or Tailscale Funnel)
6. Save the public tunnel URL as `OBSIDIAN_API_URL` (e.g. `https://obsidian.your-domain.com`)
7. Ensure Obsidian desktop is running with the plugin enabled when the workflow executes

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

The embed code follows the exact pattern used in existing reflection files:

```html
## 🐦 Tweet
<blockquote class="twitter-tweet" data-theme="dark"><p lang="en" dir="ltr">{tweet text with HTML entities}</p>&mdash; Bryan Grounds (@bagrounds) <a href="https://twitter.com/bagrounds/status/{tweet_id}?ref_src=twsrc%5Etfw">{date}</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
```

## Error Handling

| Scenario | Behavior |
|---|---|
| No reflection for yesterday | Exit gracefully with info log |
| Reflection already has tweet section | Skip (idempotent) |
| Gemini API failure | Exit with error, no tweet posted |
| Twitter API failure | Exit with error, no Obsidian update |
| oEmbed API failure | Fall back to locally generated embed code |
| Obsidian API unreachable | Exit with error (tweet is already posted; re-run will skip posting and retry Obsidian write) |

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
- **Obsidian integration**: Read and write a test note (if Obsidian API available)

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
- The workflow only needs `contents: read` permission (no write — Obsidian handles updates)
- Twitter OAuth 1.0a tokens are scoped to the specific user account
- Gemini API key has no billing by default (free tier)
- Obsidian API key should be kept secret; the tunnel should use HTTPS

## Libraries & Services Reference

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

### Obsidian Local REST API (plugin)

- **Plugin**: [obsidian-local-rest-api](https://github.com/coddingtonbear/obsidian-local-rest-api)
- **API Docs**: [Interactive API Documentation](https://coddingtonbear.github.io/obsidian-local-rest-api/)
- **Purpose**: Read and write notes in the Obsidian vault from external scripts
- **Key endpoints**: `GET /vault/{path}`, `PUT /vault/{path}`

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
