# Tweet Automation: Planning & Implementation Notes

## Planning Process

### 1. Understanding the Existing System

**Repository Analysis:**
- This is a Quartz 4.5.0 digital garden publishing system
- Content lives in `content/` directory as Obsidian-compatible markdown files
- Reflections are daily blog posts at `content/reflections/YYYY-MM-DD.md`
- The site is built with TypeScript/esbuild and deployed via GitHub Pages
- Existing CI/CD: push to `main` → build Quartz → deploy to GitHub Pages

**Key Insight:** The "Obsidian vault" in the problem statement refers to the `content/`
directory in this repository. Since the workflow runs in GitHub Actions, we access the vault
by checking out the repository — no Obsidian REST API needed. The GitHub Publisher plugin
syncs changes from Obsidian to this repo, and our workflow operates on the same files.

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
- **Choice:** `twitter-api-v2` npm package with OAuth 1.0a
- **Rationale:** OAuth 1.0a is simpler for single-user bot scenarios (no PKCE flow needed).
  The `twitter-api-v2` package is the most popular Node.js Twitter library with full v2 support.
- **Alternative considered:** Tweepy (Python) — rejected because the project is TypeScript

#### Google Gemini API
- **Choice:** `@google/generative-ai` official SDK
- **Rationale:** Official Google SDK, well-maintained, TypeScript types included
- **Model:** `gemini-2.0-flash` — fast and cost-effective for short text generation
- **Alternative considered:** OpenAI GPT — rejected because user specified Gemini

#### Tweet Embed Code
- **Choice:** Twitter oEmbed API (`publish.twitter.com/oembed`)
- **Rationale:** No authentication required, returns ready-to-use HTML, official endpoint
- **Fallback:** Generate embed code locally from tweet data (in case oEmbed is unavailable)

#### File Operations
- **Choice:** Direct filesystem access via `node:fs`
- **Rationale:** The workflow runs in GitHub Actions with the repo checked out.
  No need for Obsidian REST API since we're operating on the same markdown files.

### 4. Architecture Decisions

**Single Script Design:**
- One TypeScript file (`scripts/tweet-reflection.ts`) handles the entire pipeline
- Functions are modular and independently testable
- The script is invoked by the GitHub Actions workflow via `npx tsx`

**Idempotency:**
- The script checks if a `## 🐦 Tweet` section already exists
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

### Challenge: Date Handling

The workflow runs at 18:00 UTC. "Today" is determined by UTC date at execution time.
This means:
- For US Pacific time, the tweet is posted at 10:00 AM PST or 11:00 AM PDT
  (varies by daylight saving time)
- The reflection should already exist by this time
- If no reflection exists, the workflow exits gracefully

### Challenge: Git Commit from Actions

The workflow must push changes back to the repository. This requires:
- `contents: write` permission on the workflow
- Git configuration with bot identity
- The default `GITHUB_TOKEN` is sufficient (no PAT needed)
- Commits from the bot don't trigger other workflows (prevents loops)

Wait — actually, we DO want the deploy workflow to trigger. Using the default
`GITHUB_TOKEN` for commits means the deploy workflow won't auto-trigger. We have
two options:
1. Use a PAT instead of `GITHUB_TOKEN` (triggers downstream workflows)
2. Have the tweet workflow also build and deploy

For simplicity, we use the default `GITHUB_TOKEN` and note that the user may want to
switch to a PAT if they want the tweet commit to trigger automatic deployment. For now,
the next regular push to `main` will pick up the tweet embed change.

**Update:** Using `stefanzweifel/git-auto-commit-action` handles the commit/push cleanly,
and by default it uses the workflow's GITHUB_TOKEN. The deploy workflow will be triggered
on the next push to main (from the next Obsidian sync or manual push).

## Lessons Learned

### 1. Vault Access Pattern
The "Obsidian API" in the problem statement maps to direct filesystem access in GitHub Actions.
The Obsidian Local REST API is for local desktop automation, not CI/CD pipelines. The key insight
is that the GitHub Publisher plugin already syncs the vault to this repository.

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
