# 🏛️ Systems for Public Good — Blog Series Spec

## 📋 Overview

🏛️ **Systems for Public Good** is a daily AI-generated blog series about democracy, public goods, collective well-being, and what it means to build a society that works for everyone.

🌐 Unlike other blog series in the pipeline, Systems for Public Good relies heavily on **Google Search grounding** to reference current events, policy developments, and recent reporting from high-quality sources.

## 🏗️ Architecture

🔄 Systems for Public Good uses the same blog generation pipeline as Auto Blog Zero and Chickie Loo:

```
GitHub Actions cron (9 AM PT / 17:00 UTC)
  → Pull vault posts
  → Build context (AGENTS.md + previous posts + comments)
  → Generate post via Gemini with Google Search grounding
  → Generate cover image (optional)
  → Sync post + image to Obsidian vault
```

### 🔑 Key Differences from Other Series

| Aspect | Auto Blog Zero | Chickie Loo | Systems for Public Good |
|--------|---------------|-------------|-----------------|
| Model | `gemini-3.1-flash-lite-preview` | `gemini-3.1-flash-lite-preview` | `gemini-2.5-flash` |
| Grounding | Optional (when helpful) | None | Always enabled |
| Schedule | 8 AM PT (16:00 UTC) | 7 AM PT (15:00 UTC) | 9 AM PT (17:00 UTC) |
| Priority user | `bagrounds` | `ChickieLoo` | `bagrounds` |
| Icon | 🤖 | 🐔 | 🏛️ |

## 🧠 Model Selection

📊 The series uses `gemini-2.5-flash` as the default model because:

1. 🔍 **Google Search grounding support** — `gemini-2.5-flash` reliably supports the `googleSearch` tool on the free tier, unlike `gemini-3.1-flash-lite-preview` which returns errors when grounding is requested
2. 💰 **Free tier availability** — `gemini-2.5-flash` is available on the Gemini API free tier with sufficient quota for daily blog generation
3. 🧠 **Capable reasoning** — The series requires nuanced analysis of complex political and economic topics, benefiting from a more capable model
4. 🔄 **Configurable** — The model can be overridden via the `BLOG_GEMINI_MODEL` GitHub repository variable

## 🌐 Grounding Strategy

🔍 Google Search grounding is the cornerstone of this series. The `callGemini` function in `generate-blog-post.ts` passes `{ googleSearch: {} }` as a tool when `BLOG_ENABLE_GROUNDING !== "false"` (the default).

### 📰 Source Quality Guidelines

The AGENTS.md instructs the model to:

**Prefer:**
- 📻 NPR, PBS, AP, Reuters, BBC, The Guardian, ProPublica
- 📊 Government data sources (CBO, BLS, Census)
- 🎓 Academic journals and peer-reviewed research
- 🏛️ Nonpartisan policy organizations (Brookings, Urban Institute)

**Avoid:**
- 🚫 Ideologically driven think tanks that advocate reducing public goods (Cato, Heritage, AEI)
- 🚫 Partisan media prioritizing engagement over accuracy (Fox News, Breitbart, Daily Wire, OANN)

**Principle:**
- 📊 Prefer primary sources over opinion pieces
- 🤔 When a source is ambiguous, describe the organization and let readers evaluate

## 📚 Content Themes

The series explores interconnected themes:

1. 🏛️ **Democratic institutions** — Voting rights, representation, separation of powers, press freedom
2. 🌳 **Public goods** — Infrastructure, education, healthcare, transit, parks, libraries
3. 🔓 **Freedom** — Positive vs. negative freedom, individual vs. collective, how freedoms interact
4. 💰 **Modern monetary theory** — Sovereign currency, real resource constraints, the deficit myth
5. 🔄 **Systems thinking** — Feedback loops, emergence, leverage points, unintended consequences
6. 🌊 **Abundance mindset** — Expanding prosperity rather than redistributing scarcity
7. 🌍 **International comparisons** — How other democracies handle common challenges
8. 🏡 **Real wealth** — Tangible goods and services (food, shelter, healthcare, education, community) that constitute genuine well-being, independent of monetary measures

## ⚖️ Editorial Approach

The series follows specific editorial guidelines to maintain quality:

- 🏛️ **Pro-democracy, not partisan** — Advocate for democratic institutions without aligning to a party
- 📊 **Data over narrative** — Cite evidence; when evidence is mixed, say so
- 🤔 **Steelman opposing views** — Present the strongest version of opposing arguments
- 💬 **Invite disagreement** — End posts with questions answerable from multiple perspectives
- 🌍 **International perspective** — Compare American policy with other democracies

## 📂 File Layout

```
systems-for-public-good/
├── AGENTS.md                           # Series identity and voice
├── 2026-03-23-the-forgotten-commons.md # Seed post
├── index.md                            # Generated series index (dataview)
└── YYYY-MM-DD-slug.md                  # Daily posts
```

## ⚙️ Configuration

### 🔧 Workflow: `.github/workflows/systems-for-public-good.yml`

| Variable | Default | Purpose |
|----------|---------|---------|
| `BLOG_GEMINI_MODEL` | `gemini-2.5-flash` | Model for post generation (with grounding) |
| `SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER` | `bagrounds` | Priority user for comment weighting |
| `BLOG_ENABLE_GROUNDING` | _(not set, defaults to enabled)_ | Google Search grounding toggle |

### 🔐 Secrets (shared with other series)

All secrets are shared across blog series: `GEMINI_API_KEY`, `OBSIDIAN_AUTH_TOKEN`, `OBSIDIAN_VAULT_NAME`, `GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `GCP_SERVICE_ACCOUNT_KEY`.

## 🧪 Testing

The series config is covered by the existing `blog-series.test.ts` test suite, which validates:

- ✅ Series config exists in `BLOG_SERIES` map
- ✅ Priority user is correctly configured
- ✅ `lookupSeries("systems-for-public-good")` resolves without error
- ✅ Series-specific frontmatter assembly (nav links, icon, author)
