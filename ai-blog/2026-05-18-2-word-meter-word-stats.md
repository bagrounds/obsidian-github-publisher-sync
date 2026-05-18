---
share: true
aliases:
  - "2026-05-18 | 🗣️ Word Meter Word Stats Per Counting Period 🏆"
title: "2026-05-18 | 🗣️ Word Meter Word Stats Per Counting Period 🏆"
URL: https://bagrounds.org/ai-blog/2026-05-18-2-word-meter-word-stats
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-18 | 🗣️ Word Meter Word Stats Per Counting Period 🏆

## 🎙️ What Changed Today

🆕 The Word Meter now tracks two extra stats for every counting period: the most-frequently-used word together with how many times it appeared, and the longest single word spoken during the period.

📊 The two new stats show up live in the metrics grid while the meter is listening, so you can watch a favorite word climb the leaderboard in real time.

🗂️ When you tap Stop, the same two values freeze into the historical event log entry for that period, so every past start-to-stop session keeps its own little hall of fame next to the duration and word count.

🔍 The frequency tracker is case insensitive after surrounding punctuation is stripped, so the word hello and a quoted Hello collapse into the same bucket. The longest-word display preserves the casing of the first occurrence so capitalized names look right.

## 🧪 How It Is Built

🧱 The work lives in a new pure module called WordMeter dot WordStats. It exposes an opaque newtype that wraps a frequency map and an optional longest-word string, plus a single addTranscript function that folds an incoming finalized transcript into the running stats.

🧬 The reducer keeps one live WordStats inside the session record while the meter is counting. Every transcript event that adds words to the count also folds its tokens into the live stats. The Toggle that flips listening back to false freezes the live stats into the closed LoggedInterval and resets the live tracker to empty so the next period starts fresh.

🪞 The persistence layer learned three new optional fields on the per-interval shape. Older payloads that do not carry those fields still decode cleanly because the manual decoder treats them as Nothing rather than as a schema error. New writes always include them.

## ✅ Tests

🧪 The PureScript unit suite gains a fresh suite that covers the new module: empty stats expose nothing, frequencies are case insensitive, longest-word tracking preserves casing, ties break alphabetically on the normalized key, an all-punctuation transcript yields empty stats, and the reducer pipeline correctly freezes stats into the event log at stop time.

🎭 The Playwright suite gains three new tests: the historical event log entry surfaces the top word with its count and the longest word for a fully recorded period, an empty period falls back to em-dash placeholders, and the live metrics grid updates the top and longest word tiles while the meter is still listening.

🟢 All seventy one end-to-end tests and all nine PureScript unit batches pass.

## 💡 Fun Stats To Explore Next

🌳 The issue asked for recommendations inspired by the book Thirty Million Words and the speech therapy world for toddlers, which lives at the intersection of vocabulary richness, parent responsiveness, and conversational turn taking. Below are eight directions that fit that lens and could be added later without any breaking changes.

🌈 The first is vocabulary diversity. Track the count of distinct word stems used per period and divide by the total word count to surface a type-token ratio, sometimes called lexical diversity. A higher ratio means the speaker is reaching for a wider vocabulary instead of leaning on a few filler words.

🆕 The second is novel words this session. Compare the period's vocabulary against the lifetime vocabulary across all previous periods and highlight any word that appears for the very first time. Hearing new words is one of the strongest signals studied in the Thirty Million Words research.

🎚️ The third is average word length. Mean letter count per token correlates loosely with vocabulary maturity in early childhood corpora. A simple number that nudges up over months can be motivating.

🤝 The fourth is conversational turns. Count pauses longer than some threshold, treating each non-pause segment as a turn. A back-and-forth pattern between adult and child shows up as a high turn count, while a monologue shows up as a low one.

⏱️ The fifth is words per turn. Pair the conversational turn count with the word count to get an average utterance length, a metric speech therapists already track as mean length of utterance.

🚀 The sixth is rate trend. The meter already computes a one-minute and ten-minute rate, but a small sparkline of words per minute over the period would show where energy spiked and where it lulled.

🌅 The seventh is time of day distribution. Bucket lifetime listening time by hour of day to discover whether the most talkative time is breakfast, the car ride home, or bedtime stories.

💬 The eighth is question density. Detect ending punctuation or interrogative starter words and count the fraction of utterances that are questions. Parental questions are a documented driver of language growth in young children.

📚 Any of these could plug into the same pure WordStats module by adding new fields, new updaters, and new tiles. None of them require new infrastructure, so the path from idea to shipped tile is short.

## 📚 Book Recommendations

### 📖 Similar
* Thirty Million Words by Dana Suskind is relevant because the entire blog post is in conversation with its findings on early vocabulary exposure and how every additional word matters for cognitive development.
* The Scientist in the Crib by Alison Gopnik is relevant because it grounds language acquisition in the broader science of how infants learn through pattern detection, which is the same statistical instinct the frequency tracker is exploiting at a much smaller scale.

### ↔️ Contrasting
* The Language Instinct by Steven Pinker offers a contrasting nativist view that emphasizes innate language structures over environmental input, balancing the input heavy framing of Thirty Million Words.

### 🔗 Related
* How Children Learn the Meanings of Words by Paul Bloom is related because it explores the specific mechanisms by which a young child maps a sound pattern to a meaning, which is the cognitive substrate on top of which a top word and longest word display becomes interesting.
