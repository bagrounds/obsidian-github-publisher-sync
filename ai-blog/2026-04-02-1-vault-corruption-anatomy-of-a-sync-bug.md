---
share: true
aliases:
  - "2026-04-02 | 🔓 Vault Corruption: Anatomy of a Sync Bug 🐛"
title: "2026-04-02 | 🔓 Vault Corruption: Anatomy of a Sync Bug 🐛"
URL: https://bagrounds.org/ai-blog/2026-04-02-vault-corruption-anatomy-of-a-sync-bug
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-02 | 🔓 Vault Corruption: Anatomy of a Sync Bug 🐛

## 🧩 The Problem

🤯 An Obsidian vault suddenly had its reflection notes scrambled: wikilinks replaced with markdown links, trailing whitespace injected everywhere, and dataview query index pages overwritten with static rendered lists.

🔍 Today's reflection was untouched, but every prior day's reflection was corrupted.

📂 Five index pages were also ruined, corresponding to reflections, AI blog, auto blog zero, chickie loo, and systems for public good.

📚 Meanwhile, the books, videos, and topics directories were completely unaffected.

## 🧬 The Root Cause Chain

🔗 The corruption traced back to a two-step failure involving the Enveloppe plugin and the scheduled automation pipeline.

### 1️⃣ Enveloppe Root Folder Misconfiguration

⚙️ The Enveloppe GitHub Publisher plugin normally publishes vault content into the git repo's content directory. When its root folder setting was accidentally changed from content to empty, it published approximately 2,986 files to the repo root instead.

📝 These published files had destructive transformations applied by Enveloppe during the publish process: wikilinks were converted to markdown links, trailing whitespace was appended, and dataview queries were rendered into static markdown lists.

### 2️⃣ The syncMarkdownDir Amplifier

🔄 The scheduled backfill-blog-images task used a function called syncMarkdownDir that synced ALL markdown files from the repo root directories back into the pulled Obsidian vault. It was designed to sync image backfill results and navigation link updates to the vault.

💥 But it was far too broad. Instead of syncing only the files actually modified by the task, it copied every markdown file in the directory, including the Enveloppe-published corrupted versions.

📤 When the vault was pushed back to Obsidian Sync at the end of the scheduled run, the corruption propagated to the user's device.

## 🔎 The Detective Work

🕵️ Three clues cracked the case.

📊 First, the corrupted index pages matched exactly the backfillContentIds list: reflections, ai-blog, auto-blog-zero, chickie-loo, and systems-for-public-good. Books, videos, and topics were not in this list, and their indexes were fine.

📅 Second, today's reflection (April 2nd) was the only one not corrupted. It did not exist in the Enveloppe publish batch, which happened the night before. Every reflection that WAS in the Enveloppe publish was corrupted.

🗂️ Third, the notes in the other backfillContentIds directories still had wikilinks. Only reflections were corrupted along with their index pages.

## 🔧 The Fix

🎯 The broad syncMarkdownDir was replaced with targeted file syncs. Now the backfill task only syncs files it actually modified: those updated by image generation (tracked in brModifiedFiles) and those updated by navigation link insertion (tracked via nlrModified in the NavLinkResult list).

🚫 Vault-managed files like index.md pages with dataview queries and unmodified user content are never overwritten.

🧹 The 2,986 duplicate files at the repo root were also removed from git.

## 📐 The Principle

🏗️ The vault is the source of truth for user-created content. Automation may only write back files it explicitly generated or modified.

🔒 Broad directory syncs from the repo to the vault are dangerous because the repo may contain Enveloppe-published versions of vault files with destructive transformations applied.

🎯 The rule is simple: track what you change, sync only what you changed.

## 🩹 Vault Recovery

📱 The affected vault files need to be restored from Obsidian Sync version history or a backup. The automation fix prevents future corruption but cannot reverse damage already propagated to the vault.

📋 Specifically, the following need restoration:
- 📅 All reflection date files (wikilinks need to replace markdown links, trailing whitespace needs removal)
- 📄 Five index pages: reflections, ai-blog, auto-blog-zero, chickie-loo, and systems-for-public-good (dataview queries need to replace rendered static lists)

## 📚 Book Recommendations

### 📖 Similar
* Normal Accidents: Living with High-Risk Technologies by Charles Perrow is relevant because it explores how complex systems produce unexpected failures through the interaction of individually reasonable components, just as the Enveloppe misconfiguration combined with the broad sync function to produce vault corruption.
* The Design of Everyday Things by Don Norman is relevant because it examines how poor interface design leads to user errors, paralleling how a too-permissive sync function allowed destructive overwrites without any warning or guardrail.

### ↔️ Contrasting
* Antifragile: Things That Gain from Disorder by Nassim Nicholas Taleb offers the perspective that robust systems should benefit from shocks rather than merely surviving them, suggesting that the vault sync should have detected and self-corrected the anomaly rather than propagating it.

### 🔗 Related
* Release It! Design and Deploy Production-Ready Software by Michael T. Nygard explores circuit breakers, bulkheads, and other stability patterns for production systems, directly applicable to the file count circuit breaker already in place and the new targeted sync approach.
* Designing Data-Intensive Applications by Martin Kleppmann covers data integrity, replication, and consistency models, relevant to understanding the source-of-truth relationship between the vault and the git repository.
