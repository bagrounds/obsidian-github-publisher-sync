# Tweet Automation: Planning & Implementation Notes

## Planning Process

### 1. Understanding the Existing System

**Repository Analysis:**
- This is a Quartz 4.5.0 digital garden publishing system
- Content lives in `content/` directory as Obsidian-compatible markdown files
- Reflections are daily blog posts at `content/reflections/YYYY-MM-DD.md`
- The site is built with TypeScript/esbuild and deployed via GitHub Pages
- Existing CI/CD: push to `main` → build Quartz → deploy to GitHub Pages

**Key Insight:** The Enveloppe plugin performs **one-way sync** from the user's Obsidian
vault to this GitHub repository. Any changes committed directly to the repo would be
overwritten on the next Enveloppe publish. Therefore, to persist changes to a note, we must
write to the **Obsidian vault** (via the Local REST API), not to the git repository.

**Read vs Write paths:**
- **Reading**: We read the reflection from the checked-out repo (it's the published copy)
- **Writing**: We write the tweet embed to the Obsidian vault via the Local REST API
- The user reviews the change in Obsidian and publishes it to GitHub via Enveloppe

### 2. Analyzing Existing Tweet Embeds

**Pattern Discovery:**
- 80+ reflection files already contain embedded tweets
- Section header: `## 🐦 Tweet` (singular, at end of file)
- Embed format: Standard Twitter blockquote with `data-theme="dark"`
- Always includes the Twitter widgets.js script tag
- Tweet content follows a consistent pattern: title + emoji tags + URL

**Example from 2026-02-05.md:**
```html
## 🐦 Tweet
<blockquote class="twitter-tweet" data-theme="dark"><p lang="en" dir="ltr">
2026-02-05 | 👥 Many ⚔️ Will 🧠 Know 🌪️ Chaos 📚📺

📚 Book Series | 🌌 Sci-Fi Exploration | ⛈️ Leadership in Turmoil
https://t.co/mXLn8dlc56</p>&mdash; Bryan Grounds (@bagrounds)
<a href="https://twitter.com/bagrounds/status/...">February 7, 2026</a>
</blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
```

### 3. API Selection Decisions

#### Twitter/X API
- **Choice:** [`twitter-api-v2`](https://github.com/PLhery/node-twitter-api-v2) npm package with OAuth 1.0a
- **Rationale:** OAuth 1.0a is simpler for single-user bot scenarios (no PKCE flow needed).
  The `twitter-api-v2` package is the most popular Node.js Twitter library with full v2 support.
- **Alternative considered:** Tweepy (Python) — rejected because the project is TypeScript
- **Docs:** [API examples](https://github.com/PLhery/node-twitter-api-v2/blob/master/doc/examples.md)

#### Google Gemini API
- **Choice:** [`@google/generative-ai`](https://github.com/google-gemini/generative-ai-js) official SDK
- **Rationale:** Official Google SDK, well-maintained, TypeScript types included
- **Model:** `gemini-2.0-flash` — fast and cost-effective for short text generation
- **Alternative considered:** OpenAI GPT — rejected because user specified Gemini
- **Docs:** [Gemini API docs](https://ai.google.dev/gemini-api/docs)

#### Tweet Embed Code
- **Choice:** Twitter oEmbed API (`publish.twitter.com/oembed`)
- **Rationale:** No authentication required, returns ready-to-use HTML, official endpoint
- **Fallback:** Generate embed code locally from tweet data (in case oEmbed is unavailable)
- **Docs:** [oEmbed API](https://developer.x.com/en/docs/twitter-for-websites/oembed-api)

#### Vault Write Operations
- **Choice:** [Obsidian Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) plugin
- **Rationale:** Only way to write to the Obsidian vault from an external process. The
  Enveloppe plugin does one-way sync (Obsidian → GitHub), so git commits would be overwritten.
- **Requirements:** Obsidian desktop must be running with the plugin, exposed via a tunnel
- **Docs:** [Interactive API docs](https://coddingtonbear.github.io/obsidian-local-rest-api/)

### 4. Architecture Decisions

**Single Script Design:**
- One TypeScript file (`scripts/tweet-reflection.ts`) handles the entire pipeline
- Functions are modular and independently testable
- The script is invoked by the GitHub Actions workflow via `npx tsx`

**Yesterday's Reflection:**
- We post the previous day's reflection to ensure the note is finalized
- The user may still be editing today's note, so posting yesterday is safer

**Idempotency:**
- The script checks if a `## 🐦 Tweet` section already exists (both in repo and Obsidian)
- If it does, the script skips gracefully (safe to re-run)

**Error Propagation:**
- Errors at any step abort the pipeline (no partial updates)
- Each step's output is required input for the next step
- Clear error messages indicate which step failed and why

### 5. Testing Strategy

**Three-tier approach:**
1. **Unit tests** — Pure function tests, no API calls, always runnable
2. **Property-based tests** — Randomized inputs verify invariants
3. **Integration tests** — Real API calls, gated behind env var, self-cleaning

**Test runner:** Node.js native `node:test` module (matches existing project conventions)

## Implementation Notes

### Challenge: Character Limit

Twitter's 280-character limit is tricky with emoji-heavy titles. The Gemini prompt
explicitly instructs the model to stay within limits, and the script validates the
output length before posting. URLs are always counted as 23 characters by Twitter
(t.co shortening), regardless of actual length.

### Challenge: oEmbed vs Local Generation

The Twitter oEmbed endpoint returns the "official" embed HTML, but:
- It may not be immediately available for just-posted tweets
- It requires the tweet to be publicly accessible
- Network issues could cause failures

Solution: We first try the oEmbed API, then fall back to generating the embed code
ourselves using the tweet ID, text, and author information. The locally-generated
code is structurally identical to what oEmbed returns.

### Challenge: Date Handling & Schedule

The workflow runs at 17:00 UTC and posts the **previous day's** reflection.
- 17:00 UTC = 9:00 AM PST (Nov–Mar) or 10:00 AM PDT (Mar–Nov)
- GitHub Actions cron is UTC-only; Pacific time varies with daylight saving
- Morning Pacific time is good for tweet visibility
- Posting yesterday's note ensures it's finalized

### Challenge: Obsidian API Accessibility

The Obsidian Local REST API runs on the user's desktop machine. For GitHub Actions to
reach it, the user must expose it via a tunnel service:
- **Cloudflare Tunnel** (free): `cloudflared tunnel` maps a public URL to localhost:27124
- **ngrok** (free tier): `ngrok http 27124` creates a public URL
- **Tailscale Funnel**: If using Tailscale VPN, expose via `tailscale funnel`

The user saves the public URL as `OBSIDIAN_API_URL` in GitHub Actions secrets.
Obsidian desktop must be running when the workflow executes (daily at ~9 AM Pacific).

### Challenge: One-Way Sync (Enveloppe)

The Enveloppe plugin syncs Obsidian → GitHub only. Writing directly to the repo would
cause the changes to be overwritten on the next publish. By writing to the Obsidian vault
via the Local REST API, the tweet embed becomes part of the canonical source and flows
through the normal Enveloppe publish pipeline when the user next publishes.

### Twitter OAuth 1.0a Credentials

The X Developer Portal shows multiple credential types that can be confusing:

| Portal Section | Credential | Our Secret Name | Used? |
|---|---|---|---|
| Consumer Keys | API Key | `TWITTER_API_KEY` | ✅ Yes |
| Consumer Keys | API Key Secret | `TWITTER_API_SECRET` | ✅ Yes |
| Authentication Tokens | Access Token | `TWITTER_ACCESS_TOKEN` | ✅ Yes |
| Authentication Tokens | Access Token Secret | `TWITTER_ACCESS_SECRET` | ✅ Yes |
| OAuth 2.0 | Client ID | — | ❌ Not used |
| OAuth 2.0 | Client Secret | — | ❌ Not used |
| Bearer Token | Bearer Token | — | ❌ Not used |

The `twitter-api-v2` package maps these as:
```typescript
new TwitterApi({
  appKey: TWITTER_API_KEY,        // Consumer Key
  appSecret: TWITTER_API_SECRET,  // Consumer Secret
  accessToken: TWITTER_ACCESS_TOKEN,
  accessSecret: TWITTER_ACCESS_SECRET,
})
```

## Lessons Learned

### 1. Vault Access Pattern
The Enveloppe plugin performs one-way sync (Obsidian → GitHub). To persist changes to notes,
we must write to the Obsidian vault via the Local REST API, not commit to git. The repo copy
is read-only for our purposes.

### 2. Tweet Embed Consistency
All 80+ existing tweet embeds follow an identical format. The oEmbed API returns this exact
format, making our automation seamlessly consistent with manually-embedded tweets.

### 3. Project Conventions
- TypeScript with ESNext modules (`"type": "module"` in package.json)
- Tests use Node.js native `node:test` and `node:assert`
- Test runner: `tsx --test` (TypeScript execution without compilation)
- No external test frameworks (Jest, Mocha, etc.)
- Documentation in `docs/` directory with clear structure and metrics

### 4. Twitter t.co URL Shortening
Twitter automatically shortens all URLs to t.co links (23 characters). When calculating
tweet length, we count the URL as 23 characters regardless of actual length. The
existing tweet embeds in the repo show t.co URLs in the embed HTML, confirming this behavior.

### 5. Gemini System Prompts
The system prompt is critical for generating tweets that match the existing style. Key elements:
- Include the reflection title exactly as-is
- Generate emoji-based topic tags (not hashtags)
- Include the URL as the last element
- Stay within 280 characters
- Match the tone: informational, not promotional
