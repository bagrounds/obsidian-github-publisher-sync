# Tweet Automation Design Document

## Overview

Automated daily tweet publishing system for the bagrounds.org digital garden. A GitHub Actions
workflow runs on a cron schedule, reads today's reflection note, uses Google Gemini to generate a
tweet, posts it via the Twitter/X API, and updates the reflection file with the embedded tweet.

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  GitHub Actions  │────▶│  Read Today's│────▶│  Gemini API  │────▶│  Twitter API │
│  Cron Trigger    │     │  Reflection  │     │  Generate    │     │  Post Tweet  │
│  (daily)         │     │  File        │     │  Tweet Text  │     │              │
└─────────────────┘     └──────────────┘     └──────────────┘     └──────┬───────┘
                                                                         │
┌─────────────────┐     ┌──────────────┐     ┌──────────────┐           │
│  Git Commit &   │◀────│  Update      │◀────│  oEmbed API  │◀──────────┘
│  Push           │     │  Reflection  │     │  Get Embed   │
│                 │     │  File        │     │  HTML        │
└─────────────────┘     └──────────────┘     └──────────────┘
```

## Data Flow

### Step 1: Trigger & Checkout

- GitHub Actions cron trigger fires daily at 18:00 UTC (configurable)
- Workflow checks out the repository with full history
- Also supports manual dispatch (`workflow_dispatch`) for testing

### Step 2: Read Today's Reflection

- Script reads `content/reflections/YYYY-MM-DD.md` where date = today (UTC)
- Parses YAML frontmatter to extract: `title`, `URL`, `tags`
- Extracts markdown body content (sections, book references, topics, AI fiction)
- If no reflection exists for today, the workflow exits gracefully

### Step 3: Generate Tweet with Gemini

- Sends reflection title, URL, and content summary to Google Gemini API
- System prompt instructs Gemini to generate a tweet that:
  - Includes the reflection title
  - Includes relevant emoji tags/hashtags summarizing the topics
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
- Parameters: tweet URL, dark theme, omit script tag (we add it ourselves)
- Returns HTML blockquote embed code
- Falls back to generating embed code locally if oEmbed API is unavailable

### Step 6: Update Reflection File

- Appends `## 🐦 Tweet` section at the end of the reflection file
- Inserts the embed HTML with `data-theme="dark"` attribute
- Includes the Twitter widgets.js script tag
- Format matches existing tweet embeds in the repository

### Step 7: Commit & Push

- Configures git with bot identity
- Commits the updated reflection file
- Pushes to the `main` branch
- This triggers the existing deploy workflow to rebuild and publish the site

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
| `TWITTER_API_KEY` | Twitter/X API Key (Consumer Key) | Twitter Developer Portal → App → Keys & Tokens |
| `TWITTER_API_SECRET` | Twitter/X API Secret (Consumer Secret) | Twitter Developer Portal → App → Keys & Tokens |
| `TWITTER_ACCESS_TOKEN` | Twitter/X Access Token | Twitter Developer Portal → App → Keys & Tokens |
| `TWITTER_ACCESS_SECRET` | Twitter/X Access Token Secret | Twitter Developer Portal → App → Keys & Tokens |
| `GEMINI_API_KEY` | Google Gemini API Key | Google AI Studio → API Keys |

### How to Set GitHub Actions Secrets

1. Navigate to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Enter the **Name** (e.g., `TWITTER_API_KEY`) and **Value**
5. Click **Add secret**
6. Repeat for each secret listed above

### How to Obtain Credentials

#### Twitter/X API Credentials

1. Go to [developer.x.com](https://developer.x.com/) and sign in
2. Create a new Project and App (or use existing)
3. Set App permissions to **Read and Write**
4. Under **Keys and Tokens** tab:
   - Copy **API Key** → `TWITTER_API_KEY`
   - Copy **API Key Secret** → `TWITTER_API_SECRET`
   - Generate **Access Token and Secret** (with Read/Write permissions)
   - Copy **Access Token** → `TWITTER_ACCESS_TOKEN`
   - Copy **Access Token Secret** → `TWITTER_ACCESS_SECRET`
5. Ensure the app is associated with the `@bagrounds` Twitter account

#### Google Gemini API Key

1. Go to [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Sign in with your Google account
3. Click **Create API Key**
4. Select or create a Google Cloud project
5. Copy the generated key → `GEMINI_API_KEY`

## Tweet Format

The generated tweet follows the pattern observed in existing reflections:

```
{Title with emojis}

{Emoji tags summarizing topics}
{Reflection URL}
```

Example:
```
2026-03-06 | 🕵️ Fugitive 🤖 Telemetry 📚

🕵️ Mystery | 🤖 Sci-Fi | 📚 Book Series
https://bagrounds.org/reflections/2026-03-06
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
| No reflection file for today | Exit gracefully with info log |
| Reflection already has tweet section | Skip (idempotent) |
| Gemini API failure | Exit with error, no tweet posted |
| Twitter API failure | Exit with error, no file update |
| oEmbed API failure | Fall back to locally generated embed code |
| Git push failure | Exit with error (will retry on next run) |

## Testing Strategy

### Unit Tests (run without credentials)

- **File reading**: Parse reflection markdown, extract frontmatter and body
- **Tweet text generation**: Validate format, character limits, URL inclusion
- **Embed code generation**: Validate HTML structure, data-theme attribute
- **File update**: Verify correct placement of tweet section
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
  - cron: "0 18 * * *"  # Daily at 6:00 PM UTC
```

This ensures the reflection for the day has been written before the tweet is generated.
The schedule can be adjusted via the workflow file.

## Security Considerations

- All API credentials stored as GitHub Actions secrets (encrypted at rest)
- Secrets never logged or exposed in workflow output
- The workflow only has `contents: write` permission (minimum required)
- Twitter OAuth 1.0a tokens are scoped to the specific user account
- Gemini API key has no billing by default (free tier)
