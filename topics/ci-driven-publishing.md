---
share: true
aliases:
  - 🚀 CI-Driven Publishing
title: 🚀 CI-Driven Publishing
URL: https://bagrounds.org/topics/ci-driven-publishing
Author: "[[bryan-grounds]]"
tags:
---
[Home](../index.md) > [Topics](./index.md)  
  
# 🚀 CI-Driven Publishing  
  
## 🤖 AI Summary  
  
* 📝 High-Level Summary: A proposed architecture shift that moves all content transformation from mobile (Enveloppe plugin) to CI, enabling faster mobile sync and simpler workflow. 🎯  
  
* 🔑 Key Concepts: The goal is to replace heavy on-device processing with a lightweight git sync, then let CI do the transformation work. This should dramatically reduce the time spent waiting on the phone! ⚡📱  
  
---  
  
## 📜 Research: Current System Analysis  
  
### 🏠 Current Architecture  
  
```  
┌─────────────────────────────────────────────────────────────────────────┐  
│                         CURRENT SYSTEM                                   │  
├─────────────────────────────────────────────────────────────────────────┤  
│                                                                          │  
│  📱 MOBILE (Enveloppe Plugin)              ☁️  GITHUB CI (Quartz)       │  
│  ┌─────────────────────────────┐          ┌───────────────────────────┐ │  
│  │ 1. Scan vault for files     │          │ 1. Checkout code          │ │  
│  │ 2. Parse frontmatter       │          │ 2. Build Quartz           │ │  
│  │ 3. Convert wikilinks → md  │          │ 3. Generate HTML          │ │  
│  │ 4. Process embeddings       │          │ 4. Deploy to Pages        │ │  
│  │ 5. Handle dataview queries │          │                           │ │  
│  │ 6. Commit to GitHub        │          │                           │ │  
│  │                             │          │                           │ │  
│  ⚡ SLOW - lots of CPU work    │          │ ⚡ FAST - already optimized│ │  
│  🔋 Battery drain              │          │ 🔌 Unlimited resources    │ │  
│  📶 Network heavy              │          │ 📶 Just fetches code      │ │  
│  └─────────────────────────────┘          └───────────────────────────┘ │  
│                                                                          │  
└─────────────────────────────────────────────────────────────────────────┘  
```  
  
### 🔧 What Enveloppe Currently Does (on mobile)  
  
Based on [Enveloppe documentation](https://github.com/Enveloppe/obsidian-enveloppe):  
  
* 🔗 **Link Conversion**: `[[wikilinks]]` → markdown links  
* 📄 **Frontmatter Processing**: Parses and transforms metadata  
* 🖼️ **Embed Processing**: Handles `![[embed]]` syntax  
* 📊 **Dataview Support**: Processes `dataviewjs`, inline DQL  
* 📁 **Folder Notes**: Renames to `index.md` as needed  
* 🔀 **Repo Management**: Creates branches, PRs, auto-merges  
* 🧹 **File Cleanup**: Removes depublished/deleted files  
  
### 😩 Pain Points  
  
* ⚡ **Mobile is slow**: All transformation happens on phone CPU  
* 🔋 **Battery drain**: Intensive processing on mobile  
* 🐛 **Link bugs**: Has caused broken links (see [2025-06-07](../reflections/2025-06-07.md) - video path issue)  
* 🔧 **Complex config**: Enveloppe settings are extensive  
* 📱 **Platform-specific**: Obsidian-only solution  
  
---  
  
## 🏗️ Proposed Architecture  
  
```  
┌─────────────────────────────────────────────────────────────────────────┐  
│                      PROPOSED SYSTEM                                     │  
├─────────────────────────────────────────────────────────────────────────┤  
│                                                                          │  
│  📱 MOBILE (Simple Git Sync)              ☁️  GITHUB CI               │  
│  ┌─────────────────────────────┐          ┌───────────────────────────┐ │  
│  │ 1. Write/edit note          │          │ 1. Checkout raw content   │ │  
│  │ 2. Save (Obsidian auto-save)│          │ 2. Run Enveloppe CLI      │ │  
│  │ 3. Commit & push raw .md   │          │    (or custom transformer)│ │  
│  │                             │          │ 3. Build Quartz           │ │  
│  │                             │          │ 4. Deploy to Pages        │ │  
│  │                             │          │                           │ │  
│  ⚡ INSTANT - just git push    │          │ ⚡ FAST - optimized CI    │ │  
│  🔋 Minimal battery            │          │ 🔌 Unlimited resources    │ │  
│  📶 Small payload (.md only)   │          │ 📶 Downloads content     │ │  
│  └─────────────────────────────┘          └───────────────────────────┘ │  
│                                                                          │  
└─────────────────────────────────────────────────────────────────────────┘  
```  
  
### ✨ Key Changes  
  
* 📱 **Mobile**: Use simple git sync (Working Copy on iOS, or other git apps)  
    * 🚫 No plugin needed for publishing  
    * 📝 Just push raw Obsidian vault files  
  
* ☁️ **CI**: Add content transformation step before Quartz build  
    * Option A: Run Enveloppe CLI in CI  
    * Option B: Write custom Node.js transformer  
    * Option C: Extend Quartz with link conversion plugin  
  
* 🔗 **Link Strategy**:  
    * Keep wikilinks in Obsidian (`[[note]]`)  
    * Convert to markdown links in CI (`[note](./note.md)`)  
    * This preserves Obsidian usability! 🧡  
  
---  
  
## 📊 Benefits  
  
| Aspect | Current (Enveloppe) | Proposed (CI-Driven) |  
|--------|---------------------|---------------------|  
| Mobile sync time | 30-60s+ | 5-10s |  
| Battery impact | High | Minimal |  
| Link conversion | On-device | In CI |  
| Quartz build | Pre-optimized | Same |  
| Failure mode | Mobile crash | CI failure (retryable) |  
| Offline work | Limited | Full git workflow |  
| Platform coupling | Obsidian-only | Any git-synced content |  
  
---  
  
## 🎯 Implementation Options  
  
### Option A: Enveloppe CLI in CI  
* 👍 **Pros**: Proven transformation logic  
* 👎 **Cons**: May need Docker or Node setup in CI  
  
### Option B: Custom Link Transformer  
* 👍 **Pros**: Full control, minimal deps  
* 👎 **Cons**: Must maintain ourselves  
  
### Option C: Quartz Native + Custom Plugin  
* 👍 **Pros**: Single build pipeline  
* 👎 **Cons**: More Quartz-specific  
  
**Recommended**: Start with Option A or B, preserve Quartz optimization work 🚀  
  
---  
  
## 🛡️ Risk Mitigation  
  
### 🟢 Phase 1: Parallel Run (Low Risk)  
1. Set up CI to process raw content  
2. Keep Enveloppe running on mobile  
3. Compare outputs before switching  
4. Deploy both versions temporarily  
  
### 🟡 Phase 2: Shadow Mode  
1. CI processes content but doesn't deploy  
2. Validate output matches Enveloppe  
3. Fix any discrepancies  
  
### 🔴 Phase 3: Switch  
1. Disable Enveloppe on mobile  
2. Enable CI transformation  
3. Monitor for 1 week  
4. Rollback plan ready  
  
### 🔙 Rollback Plan  
* Re-enable Enveloppe on mobile  
* Revert CI changes  
* No data loss (content in git)! 💾  
  
---  
  
## 📝 Spec for Implementation (For Opus 4.6)  
  
### 📋 Context  
* Repository: `bagrounds/obsidian-github-publisher-sync`  
* Current: Enveloppe plugin does content transformation on mobile  
* Goal: Move transformation to CI for faster mobile workflow  
  
### 📝 Requirements  
  
1. **CI Pipeline Enhancement**  
   * Add a new job or step before Quartz build  
   * Process raw markdown files from `content/` directory  
   * Convert wikilinks (`[[note]]`) to markdown links (`[note](./note.md)`)  
   * Handle internal links with folder paths correctly  
  
2. **Link Conversion Logic**  
   ```javascript  
   // Pseudocode for link conversion  
   const convertWikilinks = (content) => {  
     // [[note]] → [note](./note.md)  
     // [[folder/note]] → [note](./folder/note.md)  
     // [[note|alias]] → [alias](./note.md)  
   }  
   ```  
  
3. **Frontmatter Handling**  
   * Pass through `share: true` files only  
   * Ensure `share: false` files remain unpublished  
  
4. **Compatibility**  
   * Must work with existing Quartz build  
   * Preserve all existing Quartz optimizations (content-hash cache, etc.)  
   * No regression in build time  
  
5. **Testing**  
   * Create test cases for link conversion  
   * Verify output matches Enveloppe's current output  
   * Test with real content from vault  
  
### 🎁 Deliverables  
  
1. Modified `.github/workflows/deploy.yml` with transformation step  
2. New transformation script (either Enveloppe CLI wrapper or custom)  
3. Test file proving correctness  
4. Documentation of the change  
  
### ⚠️ Constraints  
* Keep build time under 2 minutes  
* Don't break existing functionality  
* Maintain backward compatibility with existing content  
  
### ✅ Success Criteria  
* Mobile sync time reduced by 50%+  
* Build output identical to current system  
* No regressions in published site  
  
---  
  
## 🔗 Related  
  
### 📝 Reflections on Blogging & Publishing  
  
* [2024-04-19 | 🎉 I Start Blogging Today!](../reflections/2024-04-19.md) - When it all began  
* [2024-04-21 | ✍️ Blog | 🌋 Obsidian | 🤖 Automation | 🌓 Solarized | 💬 Comments 🪞](../reflections/2024-04-21.md) - Original setup with GitHub Publisher (now Enveloppe) and Quartz  
* [2024-11-20 | 🪄 Let There Be Comments 💬](../reflections/2024-11-20.md) - First commits to the repo  
* [2024-11-21 | 🧱 Refactor RSS & Search](../reflections/2024-11-21.md) - Quartz features exploration  
* [2024-11-23 | 🧑‍🚀 Exploring Quartz Features](../reflections/2024-11-23.md) - Graph, video embeds, build time optimization  
* [2024-11-24 | 💬 Quartz Giscus Comments](../reflections/2024-11-24.md) - Adding comments  
* [2025-03-22 | 🗓️ Blog Anniversary + Quartz Upgrades](../reflections/2025-03-22.md) - Almost a year of blogging, Quartz updates  
* [2025-04-20 | 📈 Graduated to Quartz v4](../reflections/2025-04-20.md) - Major Quartz upgrade  
* [2025-04-22 | 🔗 Graph & Backlinks](../reflections/2025-04-22.md) - More Quartz improvements  
* [2025-06-07 | 🚜 Farm | 💾 Software | 🤕 Trauma | 🤖🐦 AutoTweet ⌨️](../reflections/2025-06-07.md) - Enveloppe link bug (video path issue)  
* [2026-01-03 | 📅 Auto-Updating Index Timestamps](../reflections/2026-01-03.md) - Script to automate index updates  
  
### 🔗 Other Links  
  
* [Today's Reflection](../reflections/2026-03-02.md)  
* [Bug Report: Enveloppe Link Issue](../reflections/2025-06-07.md)  
* [Obsidian](../software/obsidian.md)  
* [Quartz SSG](../software/quartz.md)  
* [Enveloppe Plugin](https://github.com/Enveloppe/obsidian-enveloppe)  
* [Agentic Software Engineering](./agentic-software-engineering.md) (for CI automation ideas)  
