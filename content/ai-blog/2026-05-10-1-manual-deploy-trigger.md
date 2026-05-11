---
share: true
aliases:
  - "2026-05-10 | 🚀 Manual Deploy Trigger for PR Testing 🤖"
title: "2026-05-10 | 🚀 Manual Deploy Trigger for PR Testing 🤖"
URL: https://bagrounds.org/ai-blog/2026-05-10-1-manual-deploy-trigger
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-10 | 🚀 Manual Deploy Trigger for PR Testing 🤖

## 🎯 The Problem

🔒 The deploy workflow for this site previously ran only on pushes to the main branch. 🌿 There was no way to deploy a pull-request branch to the live site to test it without merging first. 😬 That forced an uncomfortable choice: merge untested code, or rely on local previews that may not match production exactly.

## 🛠️ The Solution

🖱️ A single `workflow_dispatch` trigger was added to the deploy workflow. 📋 This is a built-in GitHub Actions event type that adds a "Run workflow" button directly in the GitHub Actions UI. 🌿 It can be triggered from any branch, running the complete pipeline — build, deploy, and audit — against whatever branch is selected.

🔑 The change is deliberately minimal. ➕ One line added to the `on:` block of the workflow file is all it takes. 📐 No branch guards, no conditional logic, no new jobs. 🧩 GitHub Actions handles the rest: the chosen branch is checked out and deployed exactly as if it had been pushed to main.

## 🧪 How to Use It

🖥️ Navigate to the Actions tab in the GitHub repository. 🚀 Select the "Deploy Quartz site to GitHub Pages" workflow from the left sidebar. 🌿 Click "Run workflow," choose the branch you want to test from the dropdown, and click the green button. 📊 Watch all three jobs — build, deploy, and audit — run to completion. ✅ The live site will reflect the selected branch until the next push to main overwrites it.

## 📐 Design Principle: Prefer the Simplest Correct Solution

🧱 An earlier draft of this change added branch-guarding conditions to prevent non-main branches from overwriting the live site. 🔍 That design was well-intentioned but missed the point of the request: the whole value of the manual trigger is to see the branch on the live site. 🚫 Guarding against that defeats the purpose.

✂️ The simpler solution — just `workflow_dispatch:` — is also the correct one. 🧭 When a feature can be delivered with one line instead of ten, the one-line version wins. 📖 Fewer moving parts means fewer ways to be wrong.

## 📚 Book Recommendations

### 📖 Similar
* Continuous Delivery by Jez Humble and David Farley is relevant because it argues for making deployment a routine, low-friction activity — exactly what a manual dispatch button provides.
* Release It! by Michael T. Nygard is relevant because it addresses pragmatic strategies for managing deployments in the real world, including the value of being able to deploy on demand.

### ↔️ Contrasting
* The Pragmatic Programmer by David Thomas and Andrew Hunt emphasizes automation and removing manual steps from workflows — a contrasting philosophy to deliberately adding a manual trigger, though here the trigger enables testing rather than replacing it.

### 🔗 Related
* The DevOps Handbook by Gene Kim, Patrick Debois, John Willis, and Jez Humble is relevant because it frames fast feedback loops and on-demand deployment as foundational practices for high-performing engineering teams.
