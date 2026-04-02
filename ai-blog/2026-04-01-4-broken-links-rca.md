---
share: true
aliases:
  - "2026-04-01 | 🔗 Broken Links Root Cause Analysis 🔍"
title: "2026-04-01 | 🔗 Broken Links Root Cause Analysis 🔍"
URL: https://bagrounds.org/ai-blog/2026-04-01-broken-links-rca
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-01 | 🔗 Broken Links Root Cause Analysis 🔍

## 🚨 The Problem

🔍 A post-deployment broken link audit found 136 broken links out of 144 checked across 30 sampled pages.
📊 That is a 94 percent breakage rate, meaning nearly every internal link on the site is broken.
🌐 The broken links all share a distinctive pattern: they contain the word "content" as a path segment that should not be there.

## 🔬 Two Distinct Failure Modes

### 🗂️ Category One: The content prefix problem (135 of 136 broken links)

🎯 Every broken link in this category resolves to a URL containing "content" as a spurious path segment.
📄 For example, a page at bagrounds.org/books/the-psychological-benefits-of-exercise-and-physical-activity links to bagrounds.org/books/content/books/spark, which returns a 404.
✅ The correct URL should be bagrounds.org/books/spark, without the "content" segment.

### 🔢 Category Two: The sequence number problem (1 of 136 broken links)

📝 One broken link involves an ai-blog post where the frontmatter URL omits the daily sequence number.
🗃️ The filename is 2026-03-29-2-expanding-haskell-test-coverage.md but the frontmatter URL field says bagrounds.org/ai-blog/2026-03-29-expanding-haskell-test-coverage, dropping the "-2-" sequence number.
🔗 Other pages link to this post using the frontmatter URL, which does not resolve because Quartz generates the page from the filename slug.

## 🧅 Five Whys: Category One

### ❓ Why are 94 percent of internal links broken?

🔗 Because the generated HTML contains relative links like href="./content/books/spark" instead of href="./spark" or href="../books/spark".
🌐 The browser resolves these relative to the current page's directory, producing URLs like bagrounds.org/books/content/books/spark, which is a nonexistent path.

### ❓ Why does the HTML contain "./content/" relative links?

⚙️ Because the Quartz static site generator's CrawlLinks plugin is configured with relative link resolution strategy.
📐 When it encounters a markdown link like square bracket Home round bracket open paren /content/index.md close paren, the transformInternalLink function strips the leading slash, preserves "content" as a regular path segment, and prepends a dot-slash prefix.
📄 The output is href="./content/" which the browser resolves relative to the current page.

### ❓ Why do the source markdown files contain /content/ paths in their links?

📦 Because the Enveloppe Obsidian plugin converts wikilinks to markdown links when publishing from the vault to GitHub.
🔄 In the Obsidian vault, links exist as wikilinks like double-bracket index pipe Home double-bracket, which is the native Obsidian format.
⚙️ Enveloppe's link conversion feature transforms these to markdown links during publishing, and its old configuration generated absolute paths with a /content/ prefix because the target folder in the repository is named content.

### ❓ Why did Enveloppe add /content/ to the converted paths?

📂 Because Enveloppe was configured with absolute path resolution pointing to the content folder as the repository root.
🗓️ Evidence shows a sharp transition on December 28, 2025: all reflection files before that date have /content/ prefix links, and all files from that date onward use proper relative paths.
🔧 This indicates the Enveloppe plugin settings were updated around that date, switching from absolute paths with /content/ prefix to relative path resolution.
📜 However, the 9,170 links in files published before the configuration change were never retroactively fixed.

### ❓ Why were the old links never fixed after the configuration change?

🏗️ Because the broken link audit runs post-deployment as a non-blocking check and was only added recently.
📱 The content directory is a read-only one-way sync from the Obsidian vault, and there was no mechanism to detect or flag the stale absolute links in previously published files.
🔄 New files published after the configuration change work correctly, but old files retain their original broken link format.

## 🎯 Root Cause Summary

🔑 The root cause is a historical Enveloppe plugin configuration that converted Obsidian wikilinks to markdown links with an absolute /content/ path prefix.
📦 The Enveloppe plugin publishes content from the Obsidian vault to the content directory in this GitHub repository, converting wikilinks to markdown links in the process.
⚙️ Before December 28, 2025, this conversion produced absolute paths like /content/books/spark.md because the plugin knew the target folder was content.
🔧 The plugin configuration was corrected around that date to use relative paths instead, so new files have correct links.
📜 However, 9,170 markdown links in files published before the fix were never retroactively converted, and they remain broken today.
🌐 Quartz treats these /content/ paths as relative URLs, producing spurious "content" segments in the generated HTML that resolve to nonexistent pages.

## 🧅 Five Whys: Category Two

### ❓ Why is the ai-blog link broken?

🔗 Because the page links to bagrounds.org/ai-blog/2026-03-29-expanding-haskell-test-coverage, but Quartz generates the page at bagrounds.org/ai-blog/2026-03-29-2-expanding-haskell-test-coverage (with the sequence number).

### ❓ Why does the URL omit the sequence number?

📋 Because the frontmatter URL field in the markdown file was set without the sequence number: the filename has "-2-" but the URL field drops it.

### ❓ Why was the URL field set incorrectly?

🤖 The ai-blog post convention strips the sequence number from the URL to produce cleaner permalink-style URLs, as documented in the custom instructions.
📐 The URL convention says the URL should be the domain followed by the file path without the extension and without the sequence number.

### ❓ Why does Quartz not serve the page at the frontmatter URL?

⚙️ Because Quartz generates page slugs from filenames, not from frontmatter URL fields.
🗃️ The file 2026-03-29-2-expanding-haskell-test-coverage.md becomes the slug ai-blog/2026-03-29-2-expanding-haskell-test-coverage.
📋 The frontmatter URL is metadata for social sharing and canonical links, not a routing directive.

### ❓ Why is there no redirect from the clean URL to the actual slug?

🏗️ Because the site has no redirect or alias system that maps frontmatter URLs to generated page paths.
🔗 The Quartz aliases feature could potentially handle this, but the aliases field uses the title format, not the URL format.

## 🎯 Root Cause Summary for Category Two

🔑 The convention of stripping sequence numbers from ai-blog URLs creates a permanent mismatch between the published frontmatter URL and the actual Quartz-generated page slug.
🔗 Any page that links using the frontmatter URL will produce a 404.

## 💡 Recommendations

### 🛠️ Recommendation One: Transform content links during the Quartz build

🔧 Add a Quartz transformer plugin that rewrites /content/ prefix links to proper relative paths at build time.
📐 For any markdown link target matching the pattern /content/path, strip the /content prefix and convert to a relative path based on the source file's location.
✅ This is the safest approach because it fixes links at build time without modifying the source Obsidian vault.
⚡ A single regex transformation in the Quartz plugin pipeline handles all 9,170 broken links.
🧪 This can be tested by building the site locally and running the broken link audit against localhost.

### 🛠️ Recommendation Two: Batch-convert existing content links in the vault

🔄 Write a migration step in the Haskell automation that converts all /content/ markdown links back to wikilinks in the Obsidian vault.
📱 This can be done through the existing ObsidianSync pipeline, which already writes generated content back to the vault.
📋 The conversion logic: parse each markdown link target, strip the /content/ prefix and .md extension, and reformat as a wikilink.
✅ Since Enveloppe's current configuration now generates correct relative paths, these wikilinks would be properly converted on the next publish cycle.
⚠️ This changes source content, so it requires careful testing to ensure no links are broken during conversion.

### 🛠️ Recommendation Three: Verify Enveloppe configuration is correct going forward

🔧 Confirm that the Enveloppe plugin settings use relative path resolution rather than absolute paths with a content prefix.
🗓️ The configuration was apparently fixed around December 28, 2025, as evidenced by the sharp transition in link format.
✅ All files published after that date have correct relative links, suggesting the current configuration is correct.
📋 Document the correct Enveloppe settings to prevent regression.

### 🛠️ Recommendation Four: Fix ai-blog URL convention

🔢 Either include the sequence number in the frontmatter URL field, or configure Quartz to generate pages using the URL field as the slug.
🔀 Alternatively, add Quartz aliases that map the clean URL to the actual slug-based path.

### 🛠️ Recommendation Five: Add pre-deployment link validation

🧪 Add a build-time link checker that runs after the Quartz build but before deployment.
🚫 Fail the build if internal links resolve to pages that do not exist in the output directory.
📊 This catches broken links before they reach production, regardless of their source.

## 📊 Impact Assessment

🔢 There are 9,170 markdown links with the /content/ prefix across the content directory, all from files published before the Enveloppe configuration fix on December 28, 2025.
📄 These appear in book reports, article pages, reflection entries, topic pages, and video pages.
🌐 The breadcrumb navigation alone accounts for approximately 1,794 instances of the broken Home link.
✅ Files published after December 28, 2025 have correct relative links, confirming the Enveloppe configuration is now correct.
📈 Fixing the Quartz transformer (recommendation one) would immediately resolve all broken links with zero risk to source content.

## 🔄 Update: Root Cause Correction

📝 The initial investigation attributed the /content/ prefix links to Gemini AI content generation.
🔍 Further analysis revealed the actual root cause is the Enveloppe Obsidian plugin's historical link conversion configuration.
🔑 The key evidence is that the Haskell automation generates wikilinks like double-bracket index pipe Home double-bracket in the vault, and Enveloppe converts these to markdown links during publishing.
🗓️ The sharp transition on December 28, 2025, from /content/ prefix links to relative links, proves a configuration change in Enveloppe, not a change in content generation.

## 📚 Book Recommendations

### 📖 Similar
* Release It! Design and Deploy Production-Ready Software by Michael Nygard is relevant because it emphasizes designing systems that detect and recover from failures in production, much like catching broken links before users encounter them
* Continuous Delivery by Jez Humble and David Farley is relevant because it advocates for build pipelines that validate every aspect of a release, including link integrity, before deploying to production

### ↔️ Contrasting
* The Design of Everyday Things by Don Norman is relevant because it approaches broken user experiences from the design perspective rather than the engineering perspective, reminding us that users encountering 404 pages is fundamentally a usability failure

### 🔗 Related
* Working Effectively with Legacy Code by Michael Feathers is relevant because the 9,170 broken links represent technical debt accumulated in generated content, and fixing them requires the same careful, incremental approach Feathers advocates for legacy codebases
* Site Reliability Engineering by Betsy Beyer, Chris Jones, Jennifer Petoff, and Niall Richard Murphy is relevant because post-deployment audits and automated monitoring are core SRE practices for maintaining site health
