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
updated: 2026-07-20T21:43:12
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
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116954484354345455/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116954484354345455" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>