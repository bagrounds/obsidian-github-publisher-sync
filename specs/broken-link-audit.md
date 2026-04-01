# 🔍 Broken Link Audit

## 🎯 Overview

📋 Samples pages from the live site after deployment and checks for broken internal links.
🔗 Uses the sitemap as the source of truth for live pages.
🎲 Randomly samples a configurable number of pages per audit (default: 30).
🛡️ Non-blocking: audit results are logged but never gate deployments.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🔗 Library | `scripts/lib/broken-link-audit.ts` | 🔧 Sitemap parsing, link extraction, URL checking, random sampling |
| 🧪 Tests | `scripts/lib/broken-link-audit.test.ts` | ✅ 18 tests covering pure functions |
| 🖥️ CLI | `scripts/broken-link-audit.ts` | 📋 Command-line entry point |
| ⚙️ Workflow | `.github/workflows/deploy.yml` | 🔄 Post-deploy audit job (main branch only) |

### 🔄 Data Flow

```
🏗️ runAudit(config)
         ↓
📋 fetchSitemapUrls(siteUrl) → parse sitemap.xml
         ↓
🎲 randomSample(urls, sampleSize) → select pages to audit
         ↓
📄 For each sampled page:
   ├─ 🌐 fetch(pageUrl) → get HTML
   ├─ 🔗 extractInternalLinks(html, siteUrl, pageUrl) → find internal hrefs
   └─ ✅ checkUrl(linkUrl) → HEAD request to verify
         ↓
📊 Report: broken links, failed pages, totals
```

## ⚙️ Configuration

| 🔧 Setting | 📝 Default | 📋 Description |
|---|---|---|
| `siteUrl` | `https://bagrounds.org` | Base URL of the site |
| `sampleSize` | `30` | Number of pages to sample per audit |
| `requestTimeoutMs` | `10000` | Timeout per HTTP request in milliseconds |

## 🔧 Key Functions

### 🧊 Pure Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `parseSitemapUrls(xml)` | 📋 Extract page URLs from sitemap XML |
| `extractInternalLinks(html, siteUrl, pageUrl)` | 🔗 Extract same-domain link hrefs from HTML, resolving relative URLs |
| `randomSample(items, count)` | 🎲 Unbiased Fisher-Yates partial shuffle sampling |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `fetchSitemapUrls(siteUrl, timeout)` | 🌐 Fetch and parse sitemap from live site |
| `checkUrl(url, timeout)` | ✅ HTTP HEAD request to verify URL is reachable |
| `runAudit(config)` | 🔄 Orchestrate full audit pipeline |

## 🚀 Deployment Integration

📋 The audit runs as a separate job in the deploy workflow, after successful deployment.
🔒 Only runs on the main branch (`if: github.ref == 'refs/heads/main'`).
⏱️ Includes a 30-second wait after deployment for propagation.
🛡️ Non-blocking: audit failures do not affect deployment status.
📊 Results are logged to the workflow output for manual review.

## 🧪 Testing

🔬 Tests in `scripts/lib/broken-link-audit.test.ts` with 18 test cases covering:
- 📋 `parseSitemapUrls`: XML parsing, empty sitemaps, index filtering
- 🔗 `extractInternalLinks`: absolute/relative links, external exclusion, anchor/query stripping, deduplication, normalization
- 🎲 `randomSample`: correct size, overflow handling, uniqueness, immutability

## 🐛 Known Broken Link Patterns (RCA 2026-04-01)

### 📂 Category 1: `/content/` prefix in markdown links (~9,170 instances)

🔍 **Symptom**: Links resolve to URLs like `bagrounds.org/books/content/books/spark` (404) instead of `bagrounds.org/books/spark`.

🔗 **Root Cause**: Gemini-generated content (book reports, topic pages, reflections) contains markdown links with filesystem-style `/content/` prefix paths (e.g., `[Home](/content/index.md)`). Quartz's `transformInternalLink()` treats these as relative paths, preserving the spurious `content` segment. The browser then resolves `./content/books/spark` relative to the current page directory, producing a nonexistent URL.

📊 **Scope**: ~9,170 markdown links across books, articles, reflections, topics, and videos directories. Breadcrumb navigation alone accounts for ~1,794 instances.

💡 **Recommended Fix**: Add a Quartz build-time transformer that strips the `/content/` prefix from markdown link targets before CrawlLinks processes them. This fixes all links without modifying the read-only Obsidian vault.

### 🔢 Category 2: Missing sequence number in ai-blog URLs (1 instance)

🔍 **Symptom**: Link to `bagrounds.org/ai-blog/2026-03-29-expanding-haskell-test-coverage` returns 404. Actual page is at `bagrounds.org/ai-blog/2026-03-29-2-expanding-haskell-test-coverage`.

🔗 **Root Cause**: The ai-blog convention strips the daily sequence number from the frontmatter `URL` field to produce cleaner permalinks. However, Quartz generates page slugs from filenames (which include the sequence number), not from the frontmatter URL. Pages linking via the frontmatter URL produce 404s.

💡 **Recommended Fix**: Either include the sequence number in the frontmatter URL, or configure Quartz aliases to redirect from the clean URL to the filename-based slug.
