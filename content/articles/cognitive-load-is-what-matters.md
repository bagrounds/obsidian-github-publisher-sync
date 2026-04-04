---
share: true
aliases:
  - 🧠📈🔑 Cognitive load is what matters
title: 🧠📈🔑 Cognitive load is what matters
URL: https://bagrounds.org/articles/cognitive-load-is-what-matters
Author:
tags:
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-03T00:00:00Z
force_analyze_links: false
---
[Home](../index.md) > [Articles](./index.md)  
# [🧠📈🔑 Cognitive load is what matters](https://minds.md/zakirullin/cognitive#long)  
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