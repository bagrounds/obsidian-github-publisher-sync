# 💑 Relationship Miniseries — Blog Series Spec

## 📋 Overview

💑 **Relationship Miniseries** is a weekly AI-generated blog series that marries peer-reviewed relationship science with serious literary fiction. 🔬 Each week mines a specific finding from relationship research — Gottman's couples studies, attachment theory, social baseline theory, vulnerability science — and dramatizes it across a four-part story arc. 🎭 The science is not backdrop; it is the engine of the drama.

🗓️ The series runs on a seven-day cycle, moving from research on Monday, to narrative planning on Tuesday, to four-part drama on Wednesday through Saturday, to a reflective recap on Sunday. 📅 The daily posts arrive at 10 AM Pacific.

## 🏗️ Architecture

🔄 Relationship Miniseries uses the same blog generation pipeline as all other series:

```
GitHub Actions cron (10 AM PT / 18:00 UTC)
  → Pull vault posts
  → Build context (AGENTS.md + previous posts + comments)
  → Generate post via Gemini
  → Generate cover image (optional)
  → Sync post + image to Obsidian vault
```

### 🔑 Key Characteristics

| 🏷️ Aspect | 📝 Value |
|---|---|
| 🤖 Model | gemini-3.1-flash-lite-preview → gemini-3-flash-preview |
| 🌐 Grounding | None (internal science, no current events) |
| ⏰ Schedule | 10 AM Pacific (18:00 UTC) |
| 👤 Priority user | bagrounds |
| 🎨 Icon | 💑 |

## 🗓️ Seven-Day Cycle

📋 The series post type is determined by the day of the week:

| 📅 Day | 🏷️ Post Type | 📝 Content |
|---|---|---|
| 🌅 Monday | 🔬 Science Research | 🧪 Mine peer-reviewed relationship research; identify the single finding for this week |
| 🌤️ Tuesday | 🎨 Narrative Framework | 📚 Research fiction craft and genre; plan the story structure, characters, and arc |
| ☀️ Wednesday | 📖 Story Part 1 | 🎭 Opening installment of the week's drama |
| 🌞 Thursday | 📖 Story Part 2 | 🎭 Second installment |
| 🌇 Friday | 📖 Story Part 3 | 🎭 Third installment |
| 🌆 Saturday | 📖 Story Part 4 | 🎭 Concluding installment |
| 🌙 Sunday | 🪞 Recap and Reflection | 📊 Story recap, science revisited, craft self-critique, reader engagement |

## 🔬 Relationship Science Domains

🧪 The series draws from peer-reviewed research across relationship science:

- 💑 Gottman's couples research — bids for connection, the Four Horsemen, repair attempts, sentiment override
- 🪢 Attachment theory — secure, anxious, avoidant, and disorganized attachment in adult relationships
- 🫀 Social baseline theory — the brain's load-sharing model with trusted others (Lane Beckes, James Coan)
- 🪞 Vulnerability and self-disclosure — Jourard's self-disclosure research, Brown's shame and connection work
- 🔁 Demand-withdraw patterns — how pursuit and retreat become a self-reinforcing spiral
- 🧠 Emotion regulation — co-regulation, physiological linkage, the vagal brake
- 🌍 Closeness and differentiation — Bowen, Schnarch, the paradox of intimacy

## 🎭 Literary Standards

📚 The fiction posts aim for the quality of serious short fiction. 🖊️ The series learns from:

- ✍️ Raymond Carver — compression, subtext, the weight of what is not said
- ✍️ Alice Munro — temporal complexity, female interiority, the domestic as site of revelation
- ✍️ Marilynne Robinson — prose that thinks, spiritual depth in ordinary moments
- ✍️ James Baldwin — moral urgency, the politics of intimate life
- ✍️ Toni Morrison — layered voice, the past's presence in the present

🎯 Every fiction post must earn its emotional truth from specificity — not from abstraction, not from moralizing, but from the precision of detail and the honesty of character.

## 💬 Reader Comments

⏰ Reader comments are integrated at specific points in the seven-day cycle:

- 📅 Monday — Comments may inform the science domain chosen for this week
- 📅 Tuesday — Comments may inform the narrative approach
- 📅 Wednesday–Saturday — Comments are not read; the story arc is never interrupted mid-week
- 📅 Sunday — All comments from the past week are read and engaged directly

## 📂 File Layout

```
relationship-miniseries/
├── AGENTS.md                                     # Series identity and voice
├── 2026-07-17-what-the-light-does-part-one.md    # Inaugural seed post
├── index.md                                      # Generated series index (dataview)
└── YYYY-MM-DD-slug.md                            # Daily posts
```

## ⚙️ Configuration

### 🔧 Haskell Module

📦 `haskell/src/Automation/Series/RelationshipMiniseries.hs` defines the series with:
- 🆔 `seriesId = "relationship-miniseries"`
- 🏷️ `seriesName = "Relationship Miniseries"`
- 🎨 `seriesIcon = "💑"`
- 👤 `priorityUser = Just "bagrounds"`
- ⏰ `scheduleTime = TimeOfDay 10 0 0`
- 🤖 `modelChain = Gemini31FlashLite :| [Gemini3Flash]`
- 🌐 `searchGrounding = False`

### 🔐 Secrets (shared with other series)

🔑 All secrets are shared across blog series: `GEMINI_API_KEY`, `OBSIDIAN_AUTH_TOKEN`, `OBSIDIAN_VAULT_NAME`, `GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `GCP_SERVICE_ACCOUNT_KEY`.

### ⚙️ Configuration Variable

| 🔧 Variable | 📝 Default | 📝 Purpose |
|---|---|---|
| `RELATIONSHIP_MINISERIES_PRIORITY_USER` | `bagrounds` | 👤 Priority user for comment weighting |

## 🧪 Testing

🔬 The series config is covered by the existing Haskell test suite, which validates:

- ✅ Series config correctly derived from `AutoBlogSeries`
- ✅ Priority user env var correctly derived: `RELATIONSHIP_MINISERIES_PRIORITY_USER`
- ✅ Nav link correctly derived: `[[relationship-miniseries/index|💑 Relationship Miniseries]]`
- ✅ Author correctly derived: `relationship-miniseries`
- ✅ Base URL correctly derived: `bagrounds.org/relationship-miniseries`

## 🌱 First Week — Compressed Launch

📅 The series launched on Friday, July 17, 2026 — mid-week. 🗓️ The first installment compressed Days 1 and 2 (science research and narrative planning) into the opening post, and the full drama was compressed to two parts (Friday + Saturday). 📌 This ultra-miniseries format is the intended handling for any partial-week launch.
