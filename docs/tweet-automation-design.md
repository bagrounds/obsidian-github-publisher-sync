# Tweet Automation Design Document

## Overview

Automated daily tweet publishing system for the bagrounds.org digital garden. A GitHub Actions
workflow runs on a cron schedule each morning, reads **yesterday's** reflection note from the
repo, uses Google Gemini to generate a tweet, posts it via the Twitter/X API, fetches the embed
HTML, and writes the updated note back to the **Obsidian vault** via
[Obsidian Headless Sync](https://help.obsidian.md/sync/headless).

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

### Step 6: Update Note in Obsidian Vault via Headless Sync

- Installs [`obsidian-headless`](https://github.com/obsidianmd/obsidian-headless) globally
- Authenticates using `OBSIDIAN_AUTH_TOKEN` environment variable
- Runs `ob sync-setup` to connect to the remote vault
- Runs `ob sync` to pull the latest vault content to a temp directory
- Reads the reflection note from the synced vault
- Appends `## 🐦 Tweet` section at the end of the note
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
| `TWITTER_API_KEY` | OAuth 1.0a **Consumer Key** | X Developer Portal → App → Keys and Tokens → Consumer Keys → API Key |
| `TWITTER_API_SECRET` | OAuth 1.0a **Consumer Secret** | X Developer Portal → App → Keys and Tokens → Consumer Keys → API Secret |
| `TWITTER_ACCESS_TOKEN` | OAuth 1.0a **Access Token** | X Developer Portal → App → Keys and Tokens → Authentication Tokens → Access Token |
| `TWITTER_ACCESS_SECRET` | OAuth 1.0a **Access Token Secret** | X Developer Portal → App → Keys and Tokens → Authentication Tokens → Access Token Secret |
| `GEMINI_API_KEY` | Google Gemini API Key | Google AI Studio → API Keys |
| `OBSIDIAN_AUTH_TOKEN` | Obsidian account auth token | Run `ob login` locally, then extract from credentials file |
| `OBSIDIAN_VAULT_NAME` | Remote vault name or ID | Run `ob sync-list-remote` to see vault names |

### Optional Secrets

| Secret Name | Description | When Needed |
|---|---|---|
| `OBSIDIAN_VAULT_PASSWORD` | E2EE vault password | Only if vault uses end-to-end encryption |

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
| Obsidian Sync failure | Exit with error (tweet is already posted; re-run will skip posting and retry sync) |

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
