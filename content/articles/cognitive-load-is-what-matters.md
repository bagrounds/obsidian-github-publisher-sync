---
share: true
aliases:
  - 🧠📈🔑 Cognitive load is what matters
title: 🧠📈🔑 Cognitive load is what matters
URL: https://bagrounds.org/articles/cognitive-load-is-what-matters
Author:
tags:
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-23T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
image_date: 2026-05-15T15:02:01Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, high-contrast illustration featuring a stylized human silhouette centered against a soft, neutral background. Inside the silhouette’s head, a tangled, chaotic cluster of glowing, multi-colored geometric shapes—representing complex, shallow code modules—is being streamlined into a single, clean, glowing line that flows smoothly outward. The aesthetic is modern and clean, utilizing a muted color palette of slate blue, charcoal, and soft white, with the central streamlined path highlighted in a vibrant, warm amber to signify clarity and reduced cognitive effort. The composition emphasizes the transition from mental clutter to straightforward, logical flow.
updated: 2026-07-21T01:51:47
---
[Home](../index.md) > [Articles](./index.md)  
# [🧠📈🔑 Cognitive load is what matters](https://minds.md/zakirullin/cognitive#long)  
![articles-cognitive-load-is-what-matters](../articles-cognitive-load-is-what-matters.jpg)  
## 🤖 AI Summary  
* 🧠 **Cognitive load** is how much a developer needs to think in order to complete a task.  
* 🧐 The **average person** can hold roughly four chunks of information in working memory; cognitive overload occurs once this threshold is passed.  
* 🌟 Focus must be placed on reducing **extraneous cognitive load**, which is created by the way information is presented, rather than the intrinsic load, which is the inherent difficulty of the task.  
* 💡 Use **intermediate variables with meaningful names** to break down complex conditionals.  
* ↩️ Employ **early returns** to focus on the happy path, thus freeing working memory from precondition checks.  
* 🧱 **Prefer composition over inheritance** to avoid an inheritance nightmare where functionality is scattered across multiple classes.  
* 📚 **Deep modules** are superior to shallow modules because they provide powerful functionality yet have a simple interface, maximizing information hiding.  
* 🗃️ **Information hiding** is paramount, and shallow modules do not effectively hide complexity.  
* 👥 The **Single Responsibility Principle** means a module should be responsible to one, and only one, user or stakeholder, not just performing "one thing."  
* 🛑 Too many **shallow microservices** lead to a distributed monolith, causing debugging issues and unacceptably high time to market and cognitive load.  
* ⚙️ Limit the number of choices and reduce cognitive load by using **language features** that are orthogonal to each other.  
* 📈 The mindset "Wow, this architecture sure feels good!" is misleading; a far better approach is to observe the long-term consequences, like ease of debugging and new developer onboarding time.  
* 😴 The best code is often **boring and straightforward**, not the most elegant or sophisticated.  
  
## 🤔 Evaluation  
* 🛡️ While this philosophy champions simplicity, **Clean Code** and **Domain-Driven Design (DDD)** advocate for structured complexity and rigorous separation of concerns.  
* ⚔️ **Clean Code** often encourages many small functions and classes, which this article labels as shallow modules that ultimately increase cognitive load by forcing developers to mentally untangle numerous interactions.  
* 🧩 **DDD** aims to manage intrinsic complexity by aligning code with the business domain's ubiquitous language, which could arguably reduce *future* cognitive load, even if the initial learning curve of the mental models is steep.  
* 🔑 **Identify topics** to explore for a better understanding.  
* 🔬 Further exploration is needed into the **scientific definition of cognitive load** (intrinsic, extraneous, and germane) to better match the informal application in software engineering contexts.  
* 📏 The concepts of **"Deep" vs. "Shallow" modules** require practical, domain-agnostic metrics beyond mere line count to guide architects on optimal component and service boundary delineation.  
* 🧑‍💻 Research into the **onboarding timelines** of new engineers in well-crafted monoliths versus distributed systems would provide empirical data to conclusively support the argument against overly granular microservices.  
  
## 📚 Book Recommendations  
* 💡 **Similar**  
    * A Philosophy of Software Design: 📘 Reinforces the concepts of deep modules and complexity reduction through principles like information hiding and simple interfaces.  
    * [🧑‍🤝‍🧑⚙️➡️ Team Topologies: Organizing Business and Technology Teams for Fast Flow](../books/team-topologies-organizing-business-and-technology-teams-for-fast-flow.md): 🗺️ Provides a better framework for splitting cognitive load across teams by defining clear team interaction patterns and service boundaries, contrasting with the ambiguity of some DDD principles.  
* 🥊 **Contrasting**  
    * [🧼💾 Clean Code: A Handbook of Agile Software Craftsmanship](../books/clean-code.md): 📖 Advocates for many of the practices the article labels as harmful, such as extremely short functions and classes, which the author argues lead to mentally taxing shallow modules.  
    * [🧩🧱⚙️❤️ Domain-Driven Design: Tackling Complexity in the Heart of Software](../books/domain-driven-design.md): 🏰 Focuses on managing the *intrinsic* complexity of a domain through modeling, potentially increasing *extraneous* cognitive load initially, but promising long-term clarity within bounded contexts.  
* 🔭 **Creatively Related**  
    * [🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md): 🧠 Explores the two systems of thought in the brain, providing a psychological basis for why code should be designed to minimize effortful, high cognitive load (System 2) thinking.  
    * [💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md): 🛠️ Discusses how good design minimizes the cognitive effort required to use physical objects, a principle directly applicable to designing software interfaces and codebases for human consumption.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mqx7p2tvth24" data-bluesky-cid="bafyreicgzyurobxzpikim3da6boil6u7fjbq4gbdnlqophdlnriumg7pgq"><p>🧠📈🔑 Cognitive load is what matters  
  
#AI Q: 🧠 Is boring and straightforward code always better than elegant complexity?  
  
💻 Software Engineering | 🧠 Working Memory | 🏗️ Architecture Design | 🛠️ Programming Best Practices  
https://bagrounds.org/articles/cognitive-load-is-what-matters</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mqx7p2tvth24?ref_src=embed">2026-07-18T21:32:46.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116955461712468408/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116955461712468408" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>