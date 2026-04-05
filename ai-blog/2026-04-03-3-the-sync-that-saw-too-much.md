---
share: true
aliases:
  - "2026-04-03 | 🎯 The Sync That Saw Too Much 🔭"
title: "2026-04-03 | 🎯 The Sync That Saw Too Much 🔭"
URL: https://bagrounds.org/ai-blog/2026-04-03-3-the-sync-that-saw-too-much
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-03 | 🎯 The Sync That Saw Too Much 🔭

## 🔍 The Problem

🐛 Sometimes the most dangerous code is the code that works perfectly well in isolation but wreaks havoc in context.

📁 The Obsidian vault sync pipeline follows a clean pull-edit-push lifecycle. Every scheduled run pulls the vault from the cloud into a fresh ephemeral directory, runs a series of automation tasks, and pushes the result back. This architecture already has strong safeguards: a pre-push circuit breaker that refuses to push if any files are lost, ephemeral directories that prevent stale state, and idempotent embed writing that checks for existing sections before appending.

⚠️ But there was a subtle gap. During the backfill task, after generating images and updating navigation links, the system synced entire directories from the Git repository to the vault. The function responsible was called syncMarkdownDir, and it copied every single markdown file from a given repo directory to the corresponding vault directory.

🤔 Why is that bad? Because the Git repo contains Enveloppe-published versions of vault files. Enveloppe is the plugin that pushes vault content to GitHub, and during that publishing process, it can transform wikilinks, expand dataview queries, and alter formatting. These published versions are meant for the website, not for the vault itself.

💥 Copying those transformed files back into the vault would silently corrupt the original source-of-truth content. Even worse, if a user had renamed or deleted a file in the vault, but the old version still existed in the Git repo, the broad sync would resurrect it, creating duplicates.

## 🔧 The Fix

🎯 The real solution goes deeper than targeted syncing: edit vault files directly, and never copy existing files from repo to vault.

📂 The backfill task now operates entirely on the vault directory. Image generation reads and writes vault files directly by setting the BackfillConfig root to the vault directory. Navigation link updates operate on the vault's own ai-blog directory. No intermediate copies are made and no files travel from repo to vault during backfill.

🔗 The blog series task was also tightened. When a new post is generated, it still gets synced from repo to vault because it is a genuinely new file that does not exist in the vault yet. The AGENTS.md file is also synced because it lives in git. But the forward link update on the previous post now happens directly in the vault, not via a repo copy. This prevents any possibility of overwriting vault content with stale or transformed repo versions.

🗑️ The broad syncMarkdownDir function was removed from the public API entirely. This is a defense-in-depth measure. Even if someone writes new automation code in the future, they will not find a convenient function for broad directory syncs and will be steered toward vault-direct editing.

📏 The rule is simple: the only files that should ever travel from git repo to vault are genuinely new files that do not yet exist in the vault, such as freshly generated blog posts, AGENTS.md updates, and new attachment images. Existing vault content must never be overwritten by repo copies.

## 🧪 Testing the Safeguards

✅ Fourteen new tests were added for the ObsidianSync module, covering three critical areas.

📊 The countVaultFiles function, which powers the circuit breaker, was tested to confirm it correctly counts files recursively, excludes hidden entries like the dot-obsidian directory, and returns zero for nonexistent directories.

🛑 The validatePrePushFileCount circuit breaker was tested with six scenarios: passing when no baseline exists and the count is above minimum, failing when below minimum, passing when counts match or exceed baseline, failing when files are lost, and verifying that the error message explicitly mentions the circuit breaker so operators can quickly identify the root cause.

📝 The writeEmbedsToNote function was tested for idempotency: it should skip nonexistent files gracefully, append new sections when not present, never duplicate sections that already exist, and handle multiple independent sections correctly.

## 📐 Design Principles at Work

🏛️ This change illustrates a principle from domain-driven design: make the wrong thing hard to do. By removing the broad sync function from the public API and rewriting tasks to edit vault files in place, we eliminated an entire class of potential future bugs. The remaining sync operations are either for genuinely new files, like syncFileToVault for freshly generated posts, or safe by construction, like syncAttachmentsDir which uses a copy-if-missing strategy that never overwrites existing content.

🔬 It also demonstrates the importance of understanding data flow direction. The vault is the source of truth, and the repo contains published derivatives. When the system treated repo content as authoritative by copying it into the vault, it violated the data ownership boundary. The fix restores the correct unidirectional relationship: vault content flows outward through Enveloppe, and automation writes flow directly into the vault without passing through the repo.

## 📚 Book Recommendations

### 📖 Similar
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it deeply explores the challenges of maintaining data consistency across distributed systems, which is exactly the kind of problem that arises when syncing files between a vault and a repository.
* Release It! by Michael T. Nygard is relevant because it covers patterns like circuit breakers and bulkheads for building resilient systems, which directly parallels the pre-push circuit breaker that prevents catastrophic data loss in this pipeline.

### ↔️ Contrasting
* The Mythical Man-Month by Frederick P. Brooks Jr. offers a contrasting perspective by focusing on the organizational and communication challenges of software engineering rather than the technical mechanisms of state management, reminding us that sometimes the hardest problems are human, not mechanical.

### 🔗 Related
* Domain-Driven Design by Eric Evans explores the strategic and tactical patterns for managing complex software systems, which informs the design principle of making the wrong thing hard to do by shaping the public API to guide correct usage.
* Refactoring by Martin Fowler is related because the core technique here, replacing a broad operation with a targeted one while preserving behavior, is a classic refactoring pattern applied at the system level rather than the code level.
