---
share: true
aliases:
  - 🤔⚙️🧩🏗️💡 Everything I know about good system design
title: 🤔⚙️🧩🏗️💡 Everything I know about good system design
URL: https://bagrounds.org/articles/everything-i-know-about-good-system-design
Author:
tags:
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-23T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
image_date: 2026-05-15T18:08:55Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, isometric illustration featuring a clean, organized architectural blueprint composed of simple geometric shapes. In the center, a single, glowing lightbulb sits atop a structured grid of interlocking blocks, representing a solid foundation. Surrounding the structure are subtle, clean lines connecting modular nodes, suggesting a well-ordered system. The color palette is professional and calm, using deep navy, slate gray, and crisp white, with a single warm accent color for the lightbulb. The background is a clean, textured off-white, emphasizing a sense of clarity, stability, and boring but effective design. The overall aesthetic is modern, technical, and uncluttered.
updated: 2026-07-16T13:45:29
---
[Home](../index.md) > [Articles](./index.md)  
# [🤔⚙️🧩🏗️💡 Everything I know about good system design](https://www.seangoedecke.com/good-system-design)  
![articles-everything-i-know-about-good-system-design](../articles-everything-i-know-about-good-system-design.jpg)  
## 🤖 AI Summary  
* 📉 Good design looks underwhelming: nothing goes wrong for a long time.  
* 🧱 Complex systems reflect poor design; working complex systems evolve only from simple working systems.  
* ⚠️ Minimize stateful components because they cannot be automatically repaired when they fail.  
* ✍️ Contain all writing logic within a single, state-aware service; multiple services must not write to the same table.  
* 📝 Design tables to be human-readable, balancing flexibility with application complexity.  
* 🔎 Index tables to match common queries, placing highest-cardinality fields first.  
* ⚡ Get the database to do the work, using `JOIN` instead of in-memory stitching.  
* 📚 Send read queries to replicas; use in-memory updates to work around replication lag.  
* ⚙️ Split slow operations: do minimum useful work for the user immediately, queue the rest in background jobs.  
* 🧊 Caching introduces statefulness and must never replace first speeding up the original operation, such as adding a database index.  
* 📣 Use events when the sender is indifferent to the consumers, or for high-volume, non-time-sensitive data.  
* 🎯 Focus on "hot paths," the most critical, data-heavy parts of the system, as they have fewer viable solutions.  
* 🚨 Log aggressively during unhappy paths, recording the specific condition hit.  
* 📈 Monitor basic observability metrics, watching p95/p99 for user-facing latency.  
* 🔑 Use idempotency keys when retrying writes that may or may not have succeeded.  
* 🛡️ Define failure policy (fail open vs. fail closed) based on the specific feature requirement.  
  
## 🤔 Evaluation  
* 🆚 This perspective contrasts sharply with advice focused on leveraging complex distributed patterns like microservices or event sourcing early in a project's lifecycle, which often prioritize future scalability over present-day simplicity.  
* ⚖️ A legitimate perspective would argue that for a hyper-growth startup, *not* using message queues or a well-sharded database from day one can lead to a costly re-architecture later, contradicting the philosophy that a complex system must evolve from a simple one.  
* 💡 The emphasis on simplicity and "boring" technology aligns with the "worse is better" design philosophy, prioritizing immediate practical value and ease of maintenance over theoretical completeness or advanced features.  
* **📚 Topics to explore for a better understanding:**  
    * 🔄 The trade-offs between "fail open" and "fail closed" policies in non-security-critical but high-stakes systems (e.g., fraud detection, high-volume ad serving).  
    * ⏱️ Specific techniques for measuring and optimizing p99 latency in database queries and service-to-service communication.  
    * 🧩 The point at which a simple system *must* be split into microservices, and whether the overhead of complexity is truly earned *before* or *after* catastrophic scale issues appear.  
  
## 📚 Book Recommendations  
* [💾⬆️🛡️ Designing Data-Intensive Applications: The Big Ideas Behind Reliable, Scalable, and Maintainable Systems](../books/designing-data-intensive-applications.md) by Martin Kleppmann: 💡 **Similar** This book is mentioned in the article and provides the definitive deep dive into the underlying systems discussed, like databases, replication, and distributed transactions.  
* 📚 A Philosophy of Software Design by John Ousterhout: 📏 **Similar** It directly argues that complexity is the fundamental challenge in software, promoting simplicity and "deep" modules over "shallow" ones, strongly supporting the article's core thesis.  
* [🦄👤🗓️ The Mythical Man-Month: Essays on Software Engineering](../books/the-mythical-man-month.md) by Frederick Brooks Jr.: 👥 **Contrasting** While focused on software project management, its core message—that adding manpower to a late project makes it later—highlights that complexity in organization (and thus system design) is the hardest and most dangerous problem to solve.  
* [🧩🧱⚙️❤️ Domain-Driven Design: Tackling Complexity in the Heart of Software](../books/domain-driven-design.md) by Eric Evans: 🏗️ **Contrasting** This foundational text provides the intellectual toolkit for managing the *necessary* complexity of large, core systems, a stage the article advises earning but does not detail.  
* [🧑‍💻📈 The Pragmatic Programmer: Your Journey to Mastery](../books/the-pragmatic-programmer-your-journey-to-mastery.md) by David Thomas and Andrew Hunt: 🧑‍💻 **Creatively Related** This book is a manual for the disciplined, thoughtful, and professional attitude required to successfully implement "boring" and simple design principles day-to-day.  
* [💻⚙️🛡️📈 Site Reliability Engineering: How Google Runs Production Systems](../books/site-reliability-engineering.md) by Niall Richard Murphy et al.: 🔧 **Creatively Related** Details the operational practices, metrics (like p99), and "unhappy path" planning (like killswitches and graceful degradation) that transform a good design into a reliable, continuously running system.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mqreoifncu2y" data-bluesky-cid="bafyreieyikqfjb7jxcshazlhxzk335qzj7oqe6jpyrsy6du2k4jihzx7ia"><p>🤔⚙️🧩🏗️💡 Everything I know about good system design  
  
#AI Q: 🏗️ Is starting simple better than building for scale?  
  
💾 Database Optimization | 📉 Software Simplicity | 🛠️ Engineering Principles | 📊 Performance Monitoring  
https://bagrounds.org/articles/everything-i-know-about-good-system-design</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mqreoifncu2y?ref_src=embed">2026-07-16T13:45:56.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>