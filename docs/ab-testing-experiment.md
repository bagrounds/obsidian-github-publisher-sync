# A/B Testing Social Media Post Prompts

## Overview

This document describes the A/B testing framework for social media post generation prompts. The system independently assigns each platform post one of two prompt variants (independent coin flip per platform), automatically persists experiment records to the Obsidian vault, and runs incremental statistical analysis on every pipeline execution.

## Hypotheses

Based on research into social media engagement on decentralized platforms (Mastodon, Bluesky):

1. **H1 (Replies):** Posts with a conversational hook (question or insight) will receive more replies than pure announcement-style posts.
2. **H2 (Likes):** Posts with a conversational hook will receive more likes/favorites than announcement posts.
3. **H3 (Platform Effect):** The conversational hook effect will be stronger on Mastodon (community-driven culture) than on Bluesky (broadcast-oriented).

## Prompt Variants

### Variant A (Control)
The existing prompt style. Produces posts in this format:
```
Title with emojis

📚 Topic1 | 🤖 Topic2 | 🧠 Topic3
https://bagrounds.org/reflections/YYYY-MM-DD
```

### Variant B (Treatment)
Adds a conversational hook — a thought-provoking question or genuine insight drawn from the content:
```
Title with emojis

What happens when an AI learns to lie about its own existence?

📚 Topic1 | 🤖 Topic2
https://bagrounds.org/reflections/YYYY-MM-DD
```

## Architecture

### Module Structure

```
scripts/lib/
├── experiment.ts     # Variant selection, assignment creation, record persistence
├── prompts.ts        # Versioned prompt builders (A → control, B → treatment)
├── analytics.ts      # Engagement metric fetching + statistical analysis
├── gemini.ts         # Accepts variant parameter, delegates to prompt registry
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
    ↓
    post to platform
    ↓
    writeExperimentRecord(vaultDir, record)  → data/ab-test/{timestamp}_{platform}_{note}.json
    ↓
pushObsidianVault()  (records synced to Obsidian)
    ↓
auto-post.ts → readExperimentRecords() → runAnalysis()  (incremental)
```

### Per-Platform Independent Coin Flips

Each platform gets its own independent variant selection. For the same blog post, Bluesky might receive variant A (announcement) while Mastodon receives variant B (conversational hook). This enables:

- **Cross-platform comparison:** Same content, different variants, different platforms
- **Richer data:** More observations per post
- **Interaction detection:** Platform × variant effects (H3)

### Automated Data Collection

Experiment records are persisted as individual JSON files in `data/ab-test/` within the Obsidian vault:

```
data/ab-test/
├── 2026-03-10T17-00-00-000Z_mastodon_reflections_2026-03-10.json
├── 2026-03-10T17-00-00-100Z_bluesky_reflections_2026-03-10.json
└── ...
```

Records are written **before** the vault push, so they're automatically synced to Obsidian. The auto-post script runs incremental analysis after every posting run.

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

1. Define a new `PromptBuilder` function in `prompts.ts`
2. Add the variant to `PROMPT_VARIANTS` with a new key
3. Update `VariantId` type in `experiment.ts` to include the new key
4. Update `VARIANT_IDS` and `DEFAULT_WEIGHTS` accordingly

## Test Coverage

- **experiment.ts:** 45 tests — variant selection, assignment, override, validation, record persistence
- **prompts.ts:** 15 tests — prompt building, registry completeness, purity
- **analytics.ts:** 32 tests — statistics, t-test, p-value, summary formatting

Total: 92 new tests (453 overall, all passing).
