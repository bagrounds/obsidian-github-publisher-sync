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
