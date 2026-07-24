---
share: true
aliases:
  - 🚫🚢🧪 Don't Ship Skills Without Evals - Philipp Schmid, Google DeepMind
title: 🚫🚢🧪 Don't Ship Skills Without Evals - Philipp Schmid, Google DeepMind
URL: https://bagrounds.org/videos/dont-ship-skills-without-evals-philipp-schmid-google-deepmind
Author:
Platform:
Channel: AI Engineer
tags:
youtube: https://youtu.be/0vphxNt4wyk
---
[Home](../index.md) > [Videos](./index.md)  
# 🚫🚢🧪 Don't Ship Skills Without Evals - Philipp Schmid, Google DeepMind  
![Don't Ship Skills Without Evals - Philipp Schmid, Google DeepMind](https://youtu.be/0vphxNt4wyk)  
  
## 🤖 AI Summary  
  
* 🚫 \[[00:23](https://www.youtube.com/watch?v=0vphxNt4wyk&t=23)] Almost no AI coding skills have evaluations, leading to unverified failures in production.  
* 👥 \[[01:21](https://www.youtube.com/watch?v=0vphxNt4wyk&t=81)] Consumer-facing built agents require model-invoked skills because customers lack awareness of underlying skills compared to engineers using local tools.  
* 📦 \[[02:30](https://www.youtube.com/watch?v=0vphxNt4wyk&t=150)] Skills utilize progressive disclosure, transitioning from basic metadata descriptions to comprehensive skill files and external reference documents.  
* 🛠️ \[[03:10](https://www.youtube.com/watch?v=0vphxNt4wyk&t=190)] Capability skills temporarily teach models missing functionalities, while preference skills durably enforce specific team styles or domain requirements.  
* 📈 \[[04:17](https://www.youtube.com/watch?v=0vphxNt4wyk&t=257)] Benchmarks confirm skills improve average performance by roughly 15%, though human-written skills outperform AI-generated variations.  
* 📝 \[[07:02](https://www.youtube.com/watch?v=0vphxNt4wyk&t=422)] Effective skill descriptions require explicit directives detailing the why and how rather than vague essays or passive information.  
* 🎯 \[[09:34](https://www.youtube.com/watch?v=0vphxNt4wyk&t=574)] Skills should define goals and constraints instead of rigid step-by-step workflows better handled by executable scripts.  
* 🧪 \[[10:36](https://www.youtube.com/watch?v=0vphxNt4wyk&t=636)] Developers must implement small-scale evaluations encompassing both positive happy-path scenarios and negative cases to prevent over-triggering.  
* 🗑️ \[[11:49](https://www.youtube.com/watch?v=0vphxNt4wyk&t=709)] Continuous evaluation enables engineering teams to identify when model updates render a skill obsolete so it can be retired.  
* 📉 \[[21:11](https://www.youtube.com/watch?v=0vphxNt4wyk&t=1271)] Ablation testing via evaluations with and without loaded skills remains the only reliable method to verify performance impact.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 🤖 Q: What distinguishes capability skills from preference skills in AI development?  
  
🤖 A: Capability skills temporarily bridge temporary model limitations until underlying foundation models improve, whereas preference skills permanently enforce distinct company styles, workflows, and domain-specific requirements.  
  
### 🔍 Q: Why do AI-generated skill files often require human intervention or optimization?  
  
🔍 A: AI-generated skills frequently accumulate non-operational instructions that consume valuable token costs without altering agent behavior, making human curation and strict evaluation essential.  
  
### 📊 Q: How can developers measure the true effectiveness of an AI agent skill?  
  
📊 A: Developers must execute automated evaluations across multiple trial runs comparing performance metrics with and without the specific skill enabled.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
  
* 📖 Building Micro-Frontends by Luca Mezzalira explores architectural modularity and progressive design principles relevant to structuring scalable software components.  
  
### 🆚 Contrasting  
  
* 📖 Design Patterns: Elements of Reusable Object-Oriented Software by Erich Gamma, Richard Helm, Ralph Johnson, and John Vlissides emphasizes deterministic programmatic structures over probabilistic agent prompts.  
  
### 🎨 Creatively Related  
  
* 📖 Atomic Habits by James Clear examines how clear systems, environmental design, and continuous small adjustments drive long-term reliability and performance.