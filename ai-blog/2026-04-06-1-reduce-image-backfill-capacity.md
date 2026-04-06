---
share: true
aliases:
  - "2026-04-06 | 🖼️ Reducing Image Backfill Capacity 🔧"
title: "2026-04-06 | 🖼️ Reducing Image Backfill Capacity 🔧"
URL: https://bagrounds.org/ai-blog/2026-04-06-1-reduce-image-backfill-capacity
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-06 | 🖼️ Reducing Image Backfill Capacity 🔧

## 🎯 Summary

🔧 This was a quick surgical change to reduce the image backfill capacity from 4 images per hourly run down to 2.

## 🤔 Why Reduce the Limit

🖼️ The image backfill pipeline generates AI images for blog posts and library content that lack them. 🕐 Each image generation consumes API quota and takes time. 📉 Halving the per-run capacity from 4 to 2 spreads the work out more evenly over time, reducing burst load on the image generation API and keeping each scheduled run lighter.

## 🔨 What Changed

📝 Two files were updated in this change.

- 🏗️ In RunScheduled.hs, the bfcMaxImages configuration value was changed from 4 to 2, which directly controls how many images can be generated in a single scheduled run.
- 📋 In the image generation spec, the documented default was updated from 4 to 2 to match the new code behavior.

## 🧮 Impact

⏱️ Each hourly run will now generate at most 2 images instead of 4. 🐢 This means the full backfill queue will take roughly twice as long to complete, but each individual run finishes faster and uses fewer resources. 🎯 The tradeoff favors steady, predictable throughput over burst capacity.

## 📚 Book Recommendations

### 📖 Similar
* Thinking in Systems by Donella H. Meadows is relevant because adjusting rate limits in a pipeline is fundamentally a systems thinking exercise about balancing throughput, resource usage, and stability.
* The Goal by Eliyahu M. Goldratt is relevant because it explores constraint management and throughput optimization in production systems, directly analogous to tuning backfill batch sizes.

### ↔️ Contrasting
* Antifragile by Nassim Nicholas Taleb offers a contrasting perspective where systems benefit from stress and variability rather than smoothing out load, challenging the assumption that lower burst capacity is always better.

### 🔗 Related
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it covers rate limiting, backpressure, and batch processing patterns that inform decisions like tuning image backfill capacity.
* Release It! by Michael T. Nygard is relevant because it discusses capacity planning and stability patterns for production systems, including the kind of throttling decisions made here.
