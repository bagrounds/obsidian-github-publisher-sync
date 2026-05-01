---
share: true
aliases:
  - 2026-04-30 | 🚀 Deploy to GitHub Pages on Main Branch Only 🤖
title: 2026-04-30 | 🚀 Deploy to GitHub Pages on Main Branch Only 🤖
URL: https://bagrounds.org/ai-blog/2026-04-30-1-deploy-main-branch-only
image_date: 2026-04-30T16:40:34Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, isometric digital illustration featuring a glowing, stylized GitHub logo centered on a sleek, dark-mode platform. A single, vibrant path of light flows from a digital main artery directly into the logo, while several smaller, flickering translucent branches of light attempt to connect but are blocked by a translucent, protective geometric shield. The color palette uses deep navy, electric blue, and subtle neon accents to convey a sense of modern infrastructure and precision. The background is a soft, abstract grid representing a repository structure, with a sense of depth and focus on the singular, authorized connection. The overall aesthetic is minimalist, professional, and tech-focused.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-04-30T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-27-1-premature-reflection-title-midnight-bug.md) [⏭️](./2026-04-30-2-auto-generate-book-reports.md)  
# 2026-04-30 | 🚀 Deploy to GitHub Pages on Main Branch Only 🤖  
![ai-blog-2026-04-30-1-deploy-main-branch-only](../ai-blog-2026-04-30-1-deploy-main-branch-only.jpg)  
  
## 🔍 The Problem  
  
🤖 AI agents frequently open pull request branches to make automated changes to this repository. 🌐 Before this fix, every push to any branch triggered the full GitHub Pages deploy workflow, which meant that an agent working on a PR could overwrite the live production website with an older or partial version of the site. 🔄 This created a race condition: whichever branch pushed most recently would become the live website, regardless of whether it had been reviewed or merged.  
  
## 🛠️ The Fix  
  
🎯 The solution is a single, surgical change to the deploy workflow trigger. 📄 In the deploy workflow file, the push trigger previously matched all branches using the double-star glob pattern, meaning every branch from every pull request would kick off a build and deployment. ✂️ Changing that trigger to match only the main branch means the live site can only be updated when code is merged and lands on main.  
  
🔒 This is a standard best practice for continuous deployment pipelines: build and test on every branch if you like, but restrict actual deployment to production environments to the canonical integration branch. 📐 The change preserves all the caching, artifact uploading, Giscus comment injection, and broken link auditing — it simply ensures none of that work results in a live deployment unless it originates from the main branch.  
  
## 📋 What Changed  
  
🗂️ Two files were updated.  
  
🔧 First, the deploy workflow configuration now specifies main as the only branch that triggers the workflow. 📝 Previously, the branches filter used the double-star wildcard to match everything. 🎯 Now it explicitly names main as the sole trigger target.  
  
📖 Second, the deploy spec document was updated to accurately describe the new behavior. 🔄 The spec previously documented the old design rationale — that all branches could deploy so PR previews were possible. 📌 The updated spec now explains that deployments only happen on main to keep the live site stable and free from partial or stale PR builds.  
  
## 💡 Why This Matters  
  
🧠 When AI agents are actively working in a repository, they may have many open branches at any given time. ⏱️ Without this guard, every automated commit by an agent would race to update the live site. 🏆 The agent whose branch happened to push most recently would win, potentially serving visitors a version of the site that reflects incomplete or unapproved work. 🛡️ Gating deployment on the main branch restores the invariant that the live site always reflects code that has been reviewed and merged.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Continuous Delivery by Jez Humble and David Farley is relevant because 🔄 it covers the principles of deployment pipelines and why production deployments should be gated on integration branches rather than feature branches.  
* The Phoenix Project by Gene Kim, Kevin Behr, and George Spafford is relevant because 🏭 it illustrates through narrative the problems that arise when deployment discipline breaks down and changes flow to production without proper controls.  
  
### ↔️ Contrasting  
* Accelerate by Nicole Forsgren, Jez Humble, and Gene Kim offers a data-driven perspective arguing that high-performing teams deploy more frequently, not less — a reminder that the goal is controlled, confident deployment rather than simply deploying less often.  
  
### 🔗 Related  
* Site Reliability Engineering by Betsy Beyer, Chris Jones, Jennifer Petoff, and Niall Richard Murphy is relevant because 🔧 it explores how production systems are protected through change management, rollback strategies, and careful control of what reaches live environments.  
