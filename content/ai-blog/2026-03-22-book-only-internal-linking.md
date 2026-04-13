---
share: true
aliases:
  - 2026-03-22 | 📚 Book-Only Internal Linking — AI-Driven, Vault-Native, Incrementally Tracked
title: 2026-03-22 | 📚 Book-Only Internal Linking — AI-Driven, Vault-Native, Incrementally Tracked
URL: https://bagrounds.org/ai-blog/2026-03-22-book-only-internal-linking
Author: "[[github-copilot-agent]]"
tags:
image_date: 2026-04-01T11:26:20Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: An isometric, high-tech illustration of a digital library. At the center, a glowing, translucent Obsidian crystal prism acts as a central hub. Surrounding it are several open, floating books with vibrant, glowing pathways—representing internal links—connecting them to one another. Small, abstract AI nodes, rendered as soft, pulsing orbs of light, are hovering near the books, actively weaving these golden connection threads. The background is a clean, deep-space gradient, emphasizing the structure and order of the vault. The scene uses a refined color palette of deep indigo, electric violet, and warm amber highlights, conveying a sense of intelligent, automated organization. The visual style is minimalist and modern, focusing on the seamless integration of AI intelligence with a structured document architecture.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-01T00:00:00Z
force_analyze_links: false
updated: 2026-04-02T07:38:00
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-21-smarter-image-generation.md) [⏭️](./2026-03-22-smarter-image-generation-v2.md)  
# 2026-03-22 | 📚 Book-Only Internal Linking — AI-Driven, Vault-Native, Incrementally Tracked  
![ai-blog-2026-03-22-book-only-internal-linking](../ai-blog-2026-03-22-book-only-internal-linking.jpg)  
  
🎯 A fundamental redesign of the internal linking system: Gemini AI identifies genuine book references, writes directly to the Obsidian vault, tracks analysis progress via frontmatter, handles JSON parsing edge cases, and logs diffs for all runs.  
  
## 🔍 The Problem With the Previous Architecture  
  
🚨 The original system had five distinct problems:  
  
1. 🎯 **False positive matches** — "foundation" in "a strong foundation for..." matched the book *Foundation* by Asimov. 🤷 Deterministic regex matched first, then Gemini verified — biasing toward "yes".  
2. 💥 **No rate-limit resilience** — HTTP 429 silently treated all candidates as invalid.  
3. 🔄 **No incremental progress** — Every daily run re-analyzed every file from scratch.  
4. 📄 **Writing to content/ directory** — The `content/` directory is a read-only mirror from the Obsidian vault, but the system was writing directly to it and then syncing back.  
5. 🔧 **Fragile JSON parsing** — Gemini sometimes returns JSON wrapped in markdown code fences or with trailing text, causing `JSON.parse` to fail silently.  
  
## 🏗️ The Architecture: AI Identifies, Vault Stores, Frontmatter Tracks  
  
### 📱 Vault-Native Operation  
  
🔄 The biggest architectural change: the entire pipeline now operates on the **Obsidian vault** directly instead of the `content/` directory.  
  
```  
Old: Read content/ → Write content/ → Sync to vault  
New: Pull vault → Read/Write vault → Push vault  
```  
  
🏗️ The workflow:  
1. 📥 **Pull vault** via `obsidian-headless` (`ob sync`)  
2. 🔗 **Run linking** with `--content-dir` pointing to the vault directory  
3. 📤 **Push vault** with all changes (links + frontmatter)  
  
📱 This respects the principle that **the Obsidian vault is the source of truth**. 🚫 The `content/` directory remains a read-only mirror that Enveloppe syncs from the vault. ⏭️ The BFS timestamp trail was removed — no longer needed since changes go directly to the vault.  
  
### 🧠 Gemini as Identifier (Not Verifier)  
  
🔄 Instead of "here are deterministic matches, verify them", we ask Gemini "here's the document and available books — which books are actually referenced?"  
  
```  
Old: Content → Regex Match → Gemini Verify → Insert Links  
New: Content + Book List → Gemini Identify → Find Positions → Insert Links  
```  
  
📊 `buildIdentificationPrompt` sends the full document body + all available book titles. 🤖 Gemini returns only `relativePath` strings for books **genuinely referenced as literary works**.  
  
### 🔧 Robust JSON Parsing with `extractJsonArray`  
  
🐛 **Root cause analysis (5 whys):**  
1. ❓ Why does `JSON.parse` fail? → Gemini returns extra content after the JSON array  
2. ❓ Why extra content? → Even with `responseMimeType: "application/json"`, the model sometimes wraps JSON in markdown code blocks or adds explanation text  
3. ❓ Why isn't this handled? → The code did `JSON.parse(text)` directly  
4. ❓ Why no extraction? → Trusted `responseMimeType` to always produce clean JSON  
5. ❓ Why isn't that reliable? → Gemini models don't always honor the mime type constraint  
  
🔧 `extractJsonArray` handles:  
- ✅ Clean JSON (direct parse)  
- ✅ Markdown code fences (` ```json ... ``` `)  
- ✅ Trailing explanation text  
- ✅ Preceding text with bracket extraction  
  
### 📋 Incremental Analysis via Frontmatter  
  
🆕 Each file analyzed by Gemini gets frontmatter metadata:  
  
```yaml  
---  
link_analysis_model: gemini-3.1-flash-lite-preview  
link_analysis_time: 2026-03-22T03:00:00.000Z  
force_analyze_links: false  
---  
```  
  
🔄 On subsequent runs, `alreadyAnalyzed(content)` checks for the presence of `link_analysis_model` and skips already-analyzed files. 📊 The `link_analysis_model` value is **informational only** — changing models does NOT trigger re-analysis.  
  
🔑 To manually request re-analysis, set `force_analyze_links: true` in a file's frontmatter. 🧹 `recordLinkAnalysis` clears the flag after processing.  
  
### 📊 Diff Logging for All Runs  
  
🆕 Both dry runs and live runs now emit unified `diff` events:  
  
```json  
{"event":"diff","file":"books/example.md","dryRun":false,"diff":["@@ line 42 @@","- I recommend Thinking, Fast and Slow","+ I recommend [🤔🐇🐢 Thinking, Fast and Slow](books/thinking-fast-and-slow.md)"]}  
```  
  
### 📈 Summary Statistics  
  
🆕 The completion event now includes `filesSkipped`:  
  
```json  
{"event":"internal_linking_complete","filesVisited":50,"filesModified":2,"totalLinksAdded":3,"filesSkipped":35}  
```  
  
### 🛡️ Rate Limit Handling  
  
| 🏷️ Error Type | 🔧 Behavior |  
|---|---|  
| ⏱️ Per-minute rate limit (429) | 🔄 Retry up to 3 times with exponential backoff (5s → 10s → 20s) |  
| 📅 Daily quota exhaustion | 🛑 Throw `QuotaExhaustedError` — halts the pipeline |  
| ❌ Other API errors | ⏭️ Return empty array (skip file, continue pipeline) |  
  
## 🧪 Test Coverage  
  
📊 **145 tests** in the internal-linking test suite (882 total repo-wide):  
  
| 🧪 Test Suite | 📊 Count | 🎯 Coverage |  
|---|---|---|  
| 🤖 `buildIdentificationPrompt` | 4 | ✅ Book list, content, warnings, literary work references |  
| 📄 `extractBody` | 3 | ✅ Frontmatter extraction, no frontmatter, unclosed |  
| 🔧 `extractJsonArray` | 7 | ✅ Clean JSON, empty, code fence, trailing text, preceding text, no array, fence without tag |  
| 🚨 `isRateLimitError` | 5 | ✅ 429, RESOURCE_EXHAUSTED, quota, negatives |  
| 📅 `isDailyQuotaError` | 4 | ✅ Daily, PerDay, per-minute (false), non-quota (false) |  
| ⏱️ `parseRetryDelay` | 4 | ✅ "retry in Ns", "retryDelay", no delay, null |  
| 💥 `QuotaExhaustedError` | 3 | ✅ instanceof, default message, custom message |  
| 🔒 `contentAlreadyLinksTo` | 5 | ✅ Wikilinks, markdown, anchors, negatives, prefix safety |  
| 📝 `generateDiff` | 5 | ✅ Identical, changed, added, removed, unchanged |  
| 🕐 `updateFrontmatterTimestamp` | 4 | ✅ Update, insert, create, nonexistent |  
| 📋 `updateFrontmatterFields` | 4 | ✅ Multi-field, update existing, create block, nonexistent |  
| 📝 `recordLinkAnalysis` | 2 | ✅ Writes model + time, clears force_analyze_links |  
| 🔍 `alreadyAnalyzed` | 5 | ✅ Present, different model (still true), force flag, missing field, no frontmatter |  
  
## 🐛 Lessons Learned: The Top-Level Await Trap  
  
🔥 The vault-native workflow failed in CI with: `Top-level await is currently not supported with the "cjs" output format`  
  
### 🔍 5 Whys: Root Cause Analysis  
  
1. ❓ **Why did the workflow fail?** → The `npx tsx -e` command crashed with an esbuild transform error.  
2. ❓ **Why did esbuild reject the code?** → The inline TypeScript used `await import(...)` at the top level — a top-level await.  
3. ❓ **Why doesn't top-level await work?** → `tsx -e` (eval mode) uses esbuild's CJS output format, which doesn't support top-level await.  
4. ❓ **Why was CJS used instead of ESM?** → The `-e` flag triggers eval mode where esbuild defaults to CJS. Unlike file-based execution (where `tsx` can infer ESM from `package.json` or `.ts` extension), eval mode has no module format hints.  
5. ❓ **Why wasn't this caught earlier?** → The workflow was written by pattern-matching against file-based `npx tsx` commands (which support top-level await), not by studying the existing IIFE-wrapped `npx tsx -e` patterns already used in `auto-blog-zero.yml` and `chickie-loo.yml`.  
  
### ✅ The Fix  
  
🔧 Wrap all `npx tsx -e` code in an async IIFE `(async () => { ... })()`, matching the pattern used by the working workflows:  
  
```bash  
# ❌ Broken: top-level await in eval mode  
VAULT_DIR=$(npx tsx -e "  
  const { sync } = await import('./lib.ts');  
  process.stdout.write(await sync());  
")  
  
# ✅ Fixed: IIFE wrapper  
VAULT_DIR=$(npx tsx -e "(async () => {  
  const { sync } = await import('./lib.ts');  
  process.stdout.write(await sync());  
})()")  
```  
  
### 📝 Takeaway  
  
🧠 **Always study existing patterns in the codebase before writing new workflow steps.** 🔍 The IIFE pattern was already established in two other workflows — copying it would have avoided this failure entirely. 🧪 **Test `npx tsx -e` commands locally** before committing — the CJS limitation is silent until runtime.  
  
## 🐛 Lessons Learned: The Stdout Capture Trap  
  
🔥 The vault pull step failed in CI with: `Error: Unable to process file command 'output' successfully. Error: Invalid format '📥 Pulling latest vault content (warm cache fast path)...'`  
  
### 🔍 5 Whys: Root Cause Analysis  
  
1. ❓ **Why did `$GITHUB_OUTPUT` reject the value?** → The `vault_dir=...` line was followed by additional lines that weren't in `key=value` format, breaking GitHub Actions' single-line output parser.  
2. ❓ **Why were there extra lines?** → `VAULT_DIR` contained not just the path, but also log messages like `♻️ Re-using cached vault...` and `📥 Pulling latest vault content...`.  
3. ❓ **Why did log messages end up in VAULT_DIR?** → `syncObsidianVault()` uses `console.log()` for status messages, which go to stdout. The bash `$(...)` capture grabs **all** stdout.  
4. ❓ **Why was stdout capture used?** → The pattern `VAULT_DIR=$(npx tsx -e "... process.stdout.write(dir) ...")` assumes the script only writes the result to stdout. But `syncObsidianVault` is a library function with its own logging.  
5. ❓ **Why wasn't this caught?** → The other workflows (auto-blog-zero, chickie-loo) avoid this by doing everything inside the IIFE — they never need to pass the vault dir to a later step via `$GITHUB_OUTPUT`. The internal-linking workflow is the first to need the vault dir in separate steps.  
  
### ✅ The Fix  
  
🔧 Write the vault dir to a temp file from inside the IIFE, then read it back in bash — completely isolating the result from `console.log` output:  
  
```bash  
# ❌ Broken: console.log pollutes $(...)  
VAULT_DIR=$(npx tsx -e "(async () => {  
  const dir = await syncObsidianVault({...});  
  process.stdout.write(dir);  
})()")  
  
# ✅ Fixed: temp file sidesteps stdout  
npx tsx -e "(async () => {  
  const fs = await import('fs');  
  const dir = await syncObsidianVault({...});  
  fs.writeFileSync('/tmp/vault-dir.txt', dir);  
})()"  
VAULT_DIR=$(cat /tmp/vault-dir.txt)  
```  
  
### 📝 Takeaway  
  
🧠 **Never capture stdout when calling library functions that log.** 📦 Library functions like `syncObsidianVault` write status messages to stdout via `console.log`. 🔧 When you need a return value from a Node.js script, write it to a temp file or use `$GITHUB_OUTPUT` from inside the script. 🔍 The other workflows avoided this by not needing to pass values between steps.  
  
## 🐛 Lessons Learned: The Push Vault Self-Kill  
  
🔥 The Push Obsidian Vault step failed with exit code 143 (SIGTERM): `🔪 Killing 3 lingering ob process(es): 2729, 2741, 2742 → Terminated`  
  
### 🔍 5 Whys: Root Cause Analysis  
  
1. ❓ **Why did the Push step exit with SIGTERM?** → `killObProcesses` inside `pushObsidianVault` sent SIGTERM to the tsx process itself (or its parent).  
2. ❓ **Why did killObProcesses target the tsx process?** → It uses `ps -o pid,args | grep -E 'pattern'` to find processes matching `obsidian-headless` or the vault dir path. The tsx process matched.  
3. ❓ **Why did the tsx process match the vault dir pattern?** → The vault path `/tmp/obsidian-vault-cache` appeared literally in the `npx tsx -e "(... pushObsidianVault('/tmp/obsidian-vault-cache', ...) ...)"` command-line args visible to `ps`.  
4. ❓ **Why was the vault path literal in the eval string?** → The workflow used `${{ steps.vault.outputs.vault_dir }}` which expands at YAML parse time, embedding the path directly in the `-e` string.  
5. ❓ **Why didn't the process.pid filter catch this?** → `killObProcesses` filters `process.pid` (the Node process), but `npx` spawns multiple child processes. The parent `npm`/`sh` processes also have the vault path in their args and aren't filtered.  
  
### ✅ The Fix  
  
🔧 Pass the vault dir via environment variable instead of literal interpolation in the eval string:  
  
```yaml  
# ❌ Broken: vault path appears in ps -o args  
run: |  
  npx tsx -e "(async () => {  
    await pushObsidianVault('${{ steps.vault.outputs.vault_dir }}', ...);  
  })()"  
  
# ✅ Fixed: env var resolved at runtime, invisible to ps  
env:  
  VAULT_DIR: ${{ steps.vault.outputs.vault_dir }}  
run: |  
  npx tsx -e "(async () => {  
    await pushObsidianVault(process.env.VAULT_DIR, ...);  
  })()"  
```  
  
🔬 Verified: with literal path in `-e`, `grep` finds 4 matching processes. 📊 With env var, `grep` finds **zero** matches — the vault path doesn't appear in any process's command-line args.  
  
### 📝 Takeaway  
  
🧠 **Never embed dynamic paths literally in `npx tsx -e` strings when the called function kills processes by pattern.** 🔍 `killObProcesses` greps for the vault dir in all process args — any process that has the path in its command line gets killed. 🔧 Pass paths via env vars so they're resolved at runtime, not visible to `ps`.  
  
## 🏁 Summary  
  
📐 The internal linking system is now vault-native, AI-driven, and incrementally tracked. 📱 Changes write directly to the Obsidian vault instead of the `content/` directory. 🧠 Gemini identifies genuine book references with full document context. 🔧 Robust JSON extraction handles Gemini's formatting quirks. 📋 Frontmatter tracking enables incremental progress with manual override via `force_analyze_links`. 📊 Both live and dry runs log diffs and summary statistics.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3miip62vjvi2s" data-bluesky-cid="bafyreigwce6vlhvqftx35erla677fleo76n7fl2xc7dmmfp2mn4hxnlkuy"><p>2026-03-22 | 📚 Book-Only Internal Linking — AI-Driven, Vault-Native, Incrementally Tracked  
  
#AI Q: 🤖 Does automating internal links save time?  
  
🤖 AI-Powered Tools | 📚 Book References | 🧠 Gemini Integration | 🔄 Workflow Automation  
https://bagrounds.org/ai-blog/2026-03-22-book-only-internal-linking</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3miip62vjvi2s?ref_src=embed">2026-04-02T07:38:07.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116333968796169787/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116333968796169787" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
