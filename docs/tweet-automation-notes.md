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
write to the **Obsidian vault**, not to the git repository.

**Read vs Write paths:**
- **Reading**: We read the reflection from the checked-out repo (it's the published copy)
- **Writing**: We write the tweet embed to the Obsidian vault via Headless Sync
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
- **Choice:** [Obsidian Headless Sync](https://help.obsidian.md/sync/headless) via
  [`obsidian-headless`](https://github.com/obsidianmd/obsidian-headless) CLI
- **Rationale:** Official, server-side approach. No dependency on the Obsidian desktop app being
  open or a tunnel/proxy from a laptop. Works reliably from CI/CD.
- **Alternative considered:** Obsidian Local REST API — rejected because it requires the
  desktop app running with a tunnel (fragile: laptop could be off, asleep, unplugged)
- **Requirements:** Active Obsidian Sync subscription, Node.js 22+
- **Docs:** [Headless Sync guide](https://help.obsidian.md/sync/headless),
  [GitHub README](https://github.com/obsidianmd/obsidian-headless)

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

### Challenge: Obsidian Vault Access — Evolution of Approach

**v1: Direct git commit** (rejected)
The initial approach was to modify the file in the checked-out repo and commit via
`stefanzweifel/git-auto-commit-action`. However, the Enveloppe plugin does one-way sync
(Obsidian → GitHub), so the commit would be overwritten on the next publish.

**v2: Obsidian Local REST API** (rejected)
The second approach used the [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api)
plugin. This required the Obsidian desktop app to be running, exposed via a tunnel (ngrok,
Cloudflare Tunnel). Fragile: the laptop could be unplugged, restarted, or sleeping when the
workflow fires at 9 AM.

**v3: Obsidian Headless Sync** (current)
The official [`obsidian-headless`](https://github.com/obsidianmd/obsidian-headless) CLI
syncs vaults from the command line. The workflow:
1. Installs `obsidian-headless` globally
2. Uses `OBSIDIAN_AUTH_TOKEN` for non-interactive authentication
3. Runs `ob sync-setup` to connect to the remote vault
4. Runs `ob sync` to pull the vault to a temp directory
5. Modifies the file locally
6. Runs `ob sync` again to push the change
No dependency on a running desktop app or tunnel. Requires an Obsidian Sync subscription.

### Challenge: One-Way Sync (Enveloppe)

The Enveloppe plugin syncs Obsidian → GitHub only. Writing directly to the repo would
cause the changes to be overwritten on the next publish. By writing to the Obsidian vault
via Headless Sync, the tweet embed becomes part of the canonical source and flows through
the normal Enveloppe publish pipeline when the user next publishes.

### Twitter OAuth 1.0a Credentials

The X Developer Portal's **OAuth 1.0 Keys** section shows two entries — **Consumer Key** and
**Access Token** — but each is actually a **pair** (key + secret). When you click
**Regenerate**, the dashboard reveals both values in a dialog. You need all **4 values** total:

| Dashboard Entry | Revealed Values | Our Secret Name | Used? |
|---|---|---|---|
| Consumer Key → Regenerate | API Key | `TWITTER_API_KEY` | ✅ Yes |
| Consumer Key → Regenerate | API Key Secret | `TWITTER_API_SECRET` | ✅ Yes |
| Access Token → Regenerate | Access Token | `TWITTER_ACCESS_TOKEN` | ✅ Yes |
| Access Token → Regenerate | Access Token Secret | `TWITTER_ACCESS_SECRET` | ✅ Yes |
| OAuth 2.0 | Client ID | — | ❌ Not used |
| OAuth 2.0 | Client Secret | — | ❌ Not used |
| App-Only Authentication | Bearer Token | — | ❌ Not used |

> **Why 4 secrets from 2 dashboard entries?** OAuth 1.0a requires two credential pairs:
> the *app credentials* (Consumer Key + Secret identify your app) and the *user credentials*
> (Access Token + Secret authorize acting as `@bagrounds`). The dashboard groups them into
> 2 entries but each Regenerate dialog reveals 2 values.

The `twitter-api-v2` package maps these as:
```typescript
new TwitterApi({
  appKey: TWITTER_API_KEY,        // Consumer Key
  appSecret: TWITTER_API_SECRET,  // Consumer Secret
  accessToken: TWITTER_ACCESS_TOKEN,
  accessSecret: TWITTER_ACCESS_SECRET,
})
```

### Obsidian Headless Sync in CI

The `obsidian-headless` package uses the `OBSIDIAN_AUTH_TOKEN` environment variable for
non-interactive authentication. To obtain the token:

1. Run `ob login` on a machine with a terminal
2. Extract the token from `~/.config/obsidian-headless/` or keychain
3. Save it as a GitHub Actions secret

For E2EE vaults, the vault password must also be provided via `OBSIDIAN_VAULT_PASSWORD`.

The sync flow in CI:
```shell
npm install -g obsidian-headless
ob sync-setup --vault "$OBSIDIAN_VAULT_NAME" --path /tmp/vault
ob sync --path /tmp/vault      # Pull
# ... modify files ...
ob sync --path /tmp/vault      # Push
```

## Lessons Learned

### 1. Vault Access Pattern
The Enveloppe plugin performs one-way sync (Obsidian → GitHub). To persist changes to notes,
we must write to the Obsidian vault, not commit to git. The officially supported approach is
[Obsidian Headless Sync](https://help.obsidian.md/sync/headless), which works reliably from
CI without depending on a running desktop app.

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
