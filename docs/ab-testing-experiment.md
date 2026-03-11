# A/B Testing Social Media Post Prompts

## Overview

This document describes the A/B testing framework for social media post generation prompts. The system randomly assigns each post one of two prompt variants, tracks which variant was used, and provides tools to analyze engagement differences.

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
├── experiment.ts     # Variant selection, assignment creation, validation
├── prompts.ts        # Versioned prompt builders (A → control, B → treatment)
├── analytics.ts      # Engagement metric fetching + statistical analysis
├── gemini.ts         # Updated to accept variant parameter
└── pipeline.ts       # Updated to resolve and log variant assignments

scripts/
├── analyze-experiment.ts   # CLI: analyze experiment results
└── fetch-metrics.ts        # CLI: fetch engagement from platforms
```

### Data Flow

```
auto-post.ts
    ↓
pipeline.ts → resolveVariant() → "A" or "B"
    ↓
gemini.ts → buildPromptForVariant(variant, reflection)
    ↓
generateTweetWithGemini(..., variant)
    ↓
post to platforms (Mastodon, Bluesky, Twitter)
    ↓
console log: "🧪 Variant B | mastodon | reflections/2026-03-10.md | 2026-03-10T17:00:00Z"
```

### Variant Selection

- **Default:** 50/50 random split using `Math.random()`
- **Override:** Set `AB_TEST_VARIANT=A` or `AB_TEST_VARIANT=B` in environment
- **Deterministic testing:** `selectVariant(0.3, weights)` for reproducible tests

### Statistical Analysis

Uses **Welch's t-test** for comparing engagement between variants:
- Handles unequal sample sizes and variances
- Reports t-statistic, degrees of freedom, approximate p-value
- Significance threshold: α = 0.05

## Usage

### Running the Pipeline (Automatic)

The pipeline automatically selects a variant on each run:
```bash
npx tsx scripts/auto-post.ts
```

### Forcing a Variant

```bash
AB_TEST_VARIANT=A npx tsx scripts/auto-post.ts  # Always use control
AB_TEST_VARIANT=B npx tsx scripts/auto-post.ts  # Always use treatment
```

### Collecting Engagement Data

Create an `experiment-log.json` from pipeline logs, then fetch metrics:
```bash
npx tsx scripts/fetch-metrics.ts --data experiment-log.json
```

### Analyzing Results

```bash
npx tsx scripts/analyze-experiment.ts --data experiment-log.json
```

Example output:
```
📊 A/B Test Experiment Summary
════════════════════════════════════════

Variant A (Control):     n=15, mean engagement=2.40
Variant B (Treatment):   n=13, mean engagement=4.15

Welch's t-statistic:     -2.3456
Degrees of freedom:      24
p-value (approx):        0.0278
Significant (α=0.05):    ✅ YES

🏆 Winner: B (Treatment)
════════════════════════════════════════
```

## Experiment Log Format

```json
[
  {
    "variant": "B",
    "notePath": "reflections/2026-03-10.md",
    "platform": "mastodon",
    "postUrl": "https://mastodon.social/@bagrounds/123456",
    "postId": "123456",
    "timestamp": "2026-03-10T17:00:00Z",
    "metrics": { "likes": 3, "reposts": 1, "replies": 2 }
  }
]
```

## Adding New Variants

1. Define a new `PromptBuilder` function in `prompts.ts`
2. Add the variant to `PROMPT_VARIANTS` with a new key
3. Update `VariantId` type in `experiment.ts` to include the new key
4. Update `VARIANT_IDS` and `DEFAULT_WEIGHTS` accordingly

## Test Coverage

- **experiment.ts:** 34 tests — variant selection, assignment, override, validation
- **prompts.ts:** 15 tests — prompt building, registry completeness, purity
- **analytics.ts:** 32 tests — statistics, t-test, p-value, summary formatting

Total: 81 new tests (442 overall, all passing).
