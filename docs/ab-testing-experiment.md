# A/B Testing Social Media Post Prompts

## Overview

This document describes the A/B testing framework for social media post generation prompts. The system independently assigns each platform post one of two prompt variants (independent coin flip per platform), automatically persists experiment records to the Obsidian vault, and runs incremental statistical analysis on every pipeline execution.

## Hypotheses

Based on research into social media engagement on decentralized platforms (Mastodon, Bluesky):

1. **H1 (Replies):** Posts with a concise discussion question will receive more replies than pure announcement-style posts.
2. **H2 (Likes):** Posts with a discussion question will receive more likes/favorites than announcement posts.
3. **H3 (Platform Effect):** The discussion question effect will be stronger on Mastodon (community-driven culture) than on Bluesky (broadcast-oriented).

## Prompt Variants

### Variant A (Control)
The existing prompt style. Produces posts in this format:
```
Title with emojis

📚 Topic1 | 🤖 Topic2 | 🧠 Topic3
https://bagrounds.org/reflections/YYYY-MM-DD
```

### Variant B (Treatment)
Adds a concise AI-generated discussion question — always a 2nd-person question designed to spark engagement. Never a statement, insight, or reflection:
```
Title with emojis

🤖❓ AI Discussion Prompt: 🤔 Ever trusted a machine more than your gut?

📚 Topic1 | 🤖 Topic2
https://bagrounds.org/reflections/YYYY-MM-DD
```

The question follows Strunk & White principles: minimal word count, no fake personality, no personal pronouns, no quotation marks or hyphens. It should be relatable, easy to answer with an opinion, and appropriate for a public forum.

## Architecture

### Module Structure

```
scripts/lib/
├── experiment.ts     # Variant selection, assignment creation, record persistence
├── prompts.ts        # Prompt builders + deterministic post assemblers per variant
├── analytics.ts      # Engagement metric fetching + statistical analysis
├── gemini.ts         # Calls model for creative parts, then assembles post deterministically
└── pipeline.ts       # Per-platform variant resolution, record writing

scripts/
├── auto-post.ts            # Runs incremental analysis after posting
├── analyze-experiment.ts   # CLI: analyze experiment results
└── fetch-metrics.ts        # CLI: fetch engagement from platforms

vault/data/ab-test/         # Experiment records (auto-created, synced to Obsidian)
```

### Data Flow

```
auto-post.ts
    ↓
pipeline.ts
    ↓ (for each platform independently)
    resolveVariant() → "A" or "B"  (independent coin flip)
    ↓
    generateTweetWithGemini(reflection, ..., variant)
      ↓ Variant A: one model call → prompt A → tags
      ↓ Variant B: two model calls → prompt A → tags, prompt B → question
      ↓ assemblePostForVariant() → deterministic template: title + creative + URL
    ↓
    post to platform
    ↓
    writeExperimentRecord(vaultDir, record)  → data/ab-test/{timestamp}_{platform}_{note}.json
    ↓
pushObsidianVault()  (records synced to Obsidian)
    ↓
auto-post.ts → readExperimentRecords() → runAnalysis()  (incremental)
```

### Deterministic Post Assembly

The model generates ONLY creative content. Everything deterministic is handled in code:

| Component | Source | Variant A | Variant B |
|-----------|--------|-----------|-----------|
| Title | Code (from note metadata) | ✅ | ✅ |
| Question | Model (prompt B, question-only) | — | ✅ (with `🤖❓` prefix added by code) |
| Topic tags | Model (prompt A, reused for both) | ✅ | ✅ |
| URL | Code (from note metadata) | ✅ | ✅ |
| Formatting | Code (template string) | ✅ | ✅ |

**Key design:** Variant B reuses prompt A for topic tags. This means when comparing A vs B for the same content, the only difference is the additional discussion question. Tags are identical.

### Per-Platform Independent Coin Flips

Each platform gets its own independent variant selection. For the same blog post, Bluesky might receive variant A (announcement) while Mastodon receives variant B (discussion question). This enables:

- **Cross-platform comparison:** Same content, different variants, different platforms
- **Richer data:** More observations per post
- **Interaction detection:** Platform × variant effects (H3)

### Automated Data Collection

Experiment records are persisted as individual JSON files in `data/ab-test/` within the Obsidian vault. Files use `.json.md` extension so Obsidian sync handles them:

```
data/ab-test/
├── 2026-03-10T17-00-00-000Z_mastodon_reflections_2026-03-10.json.md
├── 2026-03-10T17-00-00-100Z_bluesky_reflections_2026-03-10.json.md
└── ...
```

Records are written **before** the vault push, so they're automatically synced to Obsidian. Legacy `.json` files are automatically migrated to `.json.md` on the next pipeline run. The auto-post script runs incremental analysis after every posting run.

### Platform Length Limits

Each platform enforces its own character/grapheme limits via `fitPostToLimit()`:
- **Twitter:** 280 characters (via `calculateTweetLength`)
- **Bluesky:** 300 graphemes (via `countGraphemes`)
- **Mastodon:** 500 characters

Posts that exceed a platform's limit are progressively truncated — first removing topic tags, then the topic line, then content. This happens in each platform's posting task, not during generation.

### Variant Selection

- **Default:** 50/50 random split using `Math.random()`, independently per platform
- **Override:** Set `AB_TEST_VARIANT=A` or `AB_TEST_VARIANT=B` in environment (forces all platforms)
- **Deterministic testing:** `selectVariant(0.3, weights)` for reproducible tests

### Statistical Analysis

Uses **Welch's t-test** for comparing engagement between variants:
- Handles unequal sample sizes and variances
- Reports t-statistic, degrees of freedom, approximate p-value
- Significance threshold: α = 0.05

## Usage

### Running the Pipeline (Automatic)

The pipeline automatically selects variants, posts, logs records, and analyzes results:
```bash
npx tsx scripts/auto-post.ts
```

### Forcing a Variant

```bash
AB_TEST_VARIANT=A npx tsx scripts/auto-post.ts  # Always use control (all platforms)
AB_TEST_VARIANT=B npx tsx scripts/auto-post.ts  # Always use treatment (all platforms)
```

### Analyzing Results from Vault

```bash
npx tsx scripts/analyze-experiment.ts --vault /path/to/vault
```

### Analyzing Results from Legacy JSON

```bash
npx tsx scripts/analyze-experiment.ts --data experiment-log.json
```

### Fetching Engagement Metrics

```bash
npx tsx scripts/fetch-metrics.ts --data experiment-log.json
```

## Experiment Record Format

Each record is a standalone JSON file in `data/ab-test/`:

```json
{
  "variant": "B",
  "notePath": "reflections/2026-03-10.md",
  "platform": "mastodon",
  "timestamp": "2026-03-10T17:00:00.000Z",
  "postUrl": "https://mastodon.social/@bagrounds/123456",
  "postId": "123456"
}
```

## Adding New Variants

1. Define a new `PromptBuilder` and `PostAssembler` function in `prompts.ts`
2. Add the variant to `VARIANT_CONFIGS` with a new key
3. Update `VariantId` type in `experiment.ts` to include the new key
4. Update `VARIANT_IDS` and `DEFAULT_WEIGHTS` accordingly

## Test Coverage

- **experiment.ts:** 50 tests — variant selection, assignment, override, validation, record persistence, migration (.json → .json.md), backward-compat reading
- **prompts.ts:** 36 tests — prompt building, deterministic assembly, question-only prompt B, tag reuse, parser, registry completeness, purity
- **analytics.ts:** 32 tests — statistics, t-test, p-value, summary formatting

Total: 118 new tests (482 overall, all passing).
