# 📊 Google Analytics Integration

## 🎯 Overview

📈 Automatically fetches Google Analytics data and adds a daily statistics section to reflection notes.
🤖 Uses the GA4 Data API to retrieve yesterday's metrics each day at 10 PM Pacific time.
🔗 Integrates with the existing daily reflection system — no manual work required.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `haskell/src/Automation/GoogleAnalytics.hs` | 🔧 Pure functions for GA4 API request building, response parsing, and reflection section formatting |
| 🔐 Auth | `haskell/src/Automation/GcpAuth.hs` | 🔑 GCP service account authentication with RSA key parsing and JWT creation |
| 🧪 Tests | `haskell/test/Automation/GoogleAnalyticsTest.hs` | ✅ Tests covering formatting, section insertion, and response parsing |
| 🧪 Tests | `haskell/test/Automation/GcpAuthTest.hs` | ✅ Tests covering PKCS#8 key parsing and service account JSON parsing |
| 🔌 Integration | `haskell/app/RunScheduled.hs` | 📝 `runDailyAnalytics` task runner |
| ⏰ Schedule | `haskell/src/Automation/Scheduler.hs` | 🕐 `DailyAnalytics` task scheduled at 22:00 PT |
| ⚙️ Workflow | `.github/workflows/scheduled.yml` | 🤖 Passes GA_PROPERTY_ID and GCP_SERVICE_ACCOUNT_KEY env vars |

### 🔄 Data Flow

```
🕐 Scheduler (hour 22 PT, at-or-after)
         ↓
🔑 Check for GA_PROPERTY_ID + GCP_SERVICE_ACCOUNT_KEY
         ↓ (if available)
🔐 Parse service account key & obtain OAuth2 access token
         ↓
📊 Fetch yesterday's summary metrics from GA4 Data API
📊 Fetch yesterday's top 5 pages from GA4 Data API
         ↓
📝 Check if today's reflection exists and needs analytics
         ↓ (if needed)
📎 Insert or update ## 📊 Google Analytics section
         ↓
☁️ Obsidian vault sync handles persistence
```

## 📐 Analytics Section Format

### 📊 Section Header

```
## 📊 Google Analytics
```

### 📈 Metrics Displayed

The daily analytics section includes yesterday's metrics:

- 👥 Active Users — unique visitors who engaged with the site
- 🔄 Sessions — total number of visits
- 📄 Page Views — total page views across the site
- 🆕 New Users — first-time visitors
- ⏱️ Avg Session — average time spent per visit

### 🏆 Top Pages

When available, the top 5 pages by page views are listed below the summary metrics.

### 📄 Example Output

```markdown
## 📊 Google Analytics

- 👥 Active Users: 42
- 🔄 Sessions: 67
- 📄 Page Views: 185
- 🆕 New Users: 15
- ⏱️ Avg Session: 2m 34s

### 🏆 Top Pages

- /ai-blog/some-post — 23 views
- / — 12 views
- /chickie-loo/another-post — 8 views
```

## 📌 Section Insertion Rules

1. ✅ If the analytics section already exists, skip (idempotent on first insert)
2. 🆕 If the section does not exist, insert it before trailing sections
3. ⬆️ Analytics section is inserted BEFORE: AI Fiction, Updates, social media embeds
4. 🔄 The section is added once per day and not updated on subsequent runs

## 🔑 Authentication

### 🔐 GCP Service Account

The integration uses a GCP service account with the Google Analytics Data API enabled. Authentication uses:

1. PKCS#8 RSA private key parsing (from the service account JSON key file)
2. JWT (JSON Web Token) creation with RS256 signing
3. OAuth2 token exchange at Google's token endpoint

### 🔧 Required Environment Variables

| 🔧 Variable | 📝 Description |
|---|---|
| `GA_PROPERTY_ID` | GA4 property ID (numeric, e.g., `123456789`) |
| `GCP_SERVICE_ACCOUNT_KEY` | Full JSON content of the service account key file |

Both must be set as GitHub repository secrets. When either is missing, the task silently skips.

## 🕐 Schedule

- ⏰ Runs at 22:00 Pacific time (10 PM), using at-or-after semantics
- 📅 Fetches data for yesterday (the most recent complete day)
- 🛡️ Idempotent: skips if analytics section already present in the reflection

## 🧪 Testing

🔬 43 new tests across 2 test modules covering:

### GoogleAnalytics Tests
- 📊 Constants and section header validation
- ⏱️ Duration formatting (zero, padding, large values)
- ✅ Reflection needs-analytics detection
- 📝 Analytics section building (with and without top pages)
- 📎 Section insertion (before fiction, updates, embeds)
- 🔄 Section replacement (updating existing analytics)
- 📨 Summary response parsing (valid and empty)
- 📨 Top pages response parsing
- 🔧 Request body structure validation
- 🏗️ Property-based tests (idempotency, format invariants)

### GcpAuth Tests
- 🔑 Service account JSON parsing (valid, empty fields, missing fields)
- 🔐 RSA private key parsing (empty, invalid, truncated, valid PKCS#8)
- 🔧 OAuth scope constant validation

## 💡 Future Ideas

See the brainstorm section at the bottom for 20+ ideas that leverage Google Analytics.

### 📊 Analytics Enhancement Ideas

1. 🔥 Trending content detection — identify posts gaining momentum
2. 📈 Week-over-week growth comparison in reflection notes
3. 🎯 Goal tracking — monitor specific page visit milestones
4. 🌍 Geographic visitor map summary in reflections
5. 📱 Device breakdown (mobile vs desktop) for content optimization
6. 🔍 Search query analysis — what terms bring visitors
7. 🚪 Top landing pages — which content attracts new visitors
8. 📉 Bounce rate trends — which content needs improvement
9. ⏰ Time-of-day engagement patterns — optimal posting times
10. 🔗 Referral source tracking — where visitors come from
11. 📚 Content series performance comparison
12. 🏆 Monthly top posts digest in a dedicated note
13. 📊 Real-time visitor count in blog sidebar
14. 🎨 Blog post cover image A/B testing based on engagement
15. 📧 Email digest of weekly analytics highlights
16. 🤖 AI-generated content recommendations based on popular topics
17. 📈 Engagement scoring for posts (views × duration × return rate)
18. 🔄 Social media ROI — correlate social posts with traffic spikes
19. 📊 Content freshness index — flag outdated popular content for updates
20. 🎯 Audience segmentation — new vs returning visitor content preferences
21. 📈 SEO performance tracking — organic search traffic trends
22. 🔍 404 error monitoring — find broken links from analytics
23. 📊 Reading depth estimation — how far visitors scroll
24. 🤖 Auto-generate weekly analytics blog post
