---
share: true
aliases:
  - "2026-04-22 | 🌐 Gemini: Search Grounded Response Links 🔍"
title: "2026-04-22 | 🌐 Gemini: Search Grounded Response Links 🔍"
URL: https://bagrounds.org/ai-blog/2026-04-22-1-gemini-grounding-source-links
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-22 | 🌐 Gemini: Search Grounded Response Links 🔍

## 🎯 The Problem

📰 The Noise is a daily AI news digest that uses Google Search grounding to cite real, current news sources.
🤔 The challenge was that while the AI was grounded in real sources, those sources were invisible to the reader.
📚 When the Gemini API uses Google Search grounding, it retrieves actual web pages and uses them to inform the response, but the URLs were being discarded before the blog post was written.
🔒 The original AGENTS.md prompt told the AI to never include links in its output, because hallucinated links are worse than no links at all.
💡 The solution was to extract the verified source links from the API response metadata and append them programmatically, not from the AI's output.

## 🔍 How Grounding Works in the Gemini API

🌐 When a Gemini request includes the Google Search tool, the API retrieves relevant web pages before generating the response.
📋 The API response includes a field called groundingMetadata inside each candidate, which contains an array called groundingChunks.
🔗 Each chunk may have a web object with a uri field (the actual URL) and a title field (the page title).
🛡️ These URLs are reliable because they represent pages that were actually fetched and used during generation, not invented by the model.

## 🏗️ Implementation Design

### 📦 The New GroundingSource Type

🏷️ The implementation introduces a GroundingSource data type with two fields: groundingSourceUri holds the URL as Text, and groundingSourceTitle holds the page title as Text.
🔒 Both fields use the Text type directly since they come from the API and are not user-controlled inputs that need validation.

### 🔧 Updated Request and Response Types

📤 The Request type gained a new field called requestEnableGrounding of type Bool.
📥 The Response type gained a new field called responseGroundingSources of type a list of GroundingSource.
🔄 All existing callers that construct a Request record were updated to include requestEnableGrounding set to False, ensuring backward compatibility.

### 🏗️ Building Grounded Requests

📡 The buildRequestBody function gained a Bool parameter for grounding.
🔧 When grounding is enabled, the request body includes a tools field containing a google underscore search object, which is the format the Gemini API expects to enable Google Search grounding.
🧩 When grounding is disabled, the request body is identical to what it was before, ensuring no behavior change for non-grounded series.

### 🔬 Extracting Sources from the Response

🧹 The extractGroundingSources function walks the JSON structure of the response to find groundingMetadata in the first candidate, then collects all web chunks.
✅ Sources are validated before inclusion: only URIs that start with the text http pass the filter, which covers both http and https URLs and also excludes empty strings.
🏷️ If a source has an empty title, the URI itself is used as the fallback title so the link is always readable.

### 📝 Formatting Sources as Markdown

🌐 The formatGroundingSources function returns an empty string for an empty list, which means no Sources section appears for non-grounded posts.
📋 For non-empty lists, it produces a section with the heading Sources preceded by a magnifying glass emoji, followed by a list of items each starting with a dash, a globe emoji, and a markdown link.
🧹 Deduplication happens before formatting using a left fold that preserves the first occurrence of each URI, since the same page can appear multiple times in the grounding chunks.

### 🔄 Graceful Fallback for Quota Limits

⚠️ The Gemini API has a quota for search grounding, separate from the regular inference quota.
🔁 When a grounded request fails with a rate limit error, generateContentWithFallback now retries the same model without grounding before moving to the next model in the fallback chain.
📊 This means a post can still be published even if the grounding quota is exhausted, just without the Sources section.
🔐 After a successful grounding fallback, subsequent models in the chain are also tried without grounding to avoid hitting the quota again.

### ⚙️ Series Configuration

🗂️ The DiscoveredSeries and BlogSeriesRunConfig types both gained an enableGrounding field of type Bool.
📄 Series JSON files can now include enableGrounding set to true to opt into grounding.
✅ The following series now have grounding enabled: the-noise, systems-for-public-good, positivity-bias, and convergence.
🔒 All other series default to false when the field is absent, so existing behavior is unchanged.

### 📊 Logging

🔍 When sources are embedded, a log line reports how many grounding sources were included, making it easy to verify grounding is working in production.

## 🧪 Test Coverage

🔬 The extractGroundingSourcesTests group tests seven distinct scenarios: empty object, non-object input, response without grounding metadata, response with valid chunks, empty URI rejection, non-http URI rejection, empty title fallback, and multi-source ordering preservation.
📋 The formatGroundingSourcesTests group tests five scenarios: empty list returns empty text, single source produces the Sources section, multiple sources all appear, deduplication removes later duplicates of the same URI, and list items start with the expected dash and globe emoji.
🔧 The buildRequestBodyTests group gained four new tests: grounding off omits google underscore search, grounding on includes it, grounding on includes the tools field, and grounding on with a system instruction includes both.
🌱 The BlogSeriesDiscovery tests verify that the enableGrounding field defaults to false when absent, parses true correctly, parses false correctly, and is preserved through deriveBlogSeriesRunConfig.

## 💡 Key Design Decisions

🚫 The AI is still instructed not to include links in its output, which prevents hallucinated links.
🌐 Source links come exclusively from the API response grounding metadata, which are verified URLs.
🔒 The feature is opt-in per series via the enableGrounding config field.
🛡️ The grounding fallback ensures reliability: if grounding quota is exhausted, the post still publishes without a Sources section rather than failing entirely.
📐 The deduplication uses a strict left fold to maintain correct insertion order, since foldr with consing would reverse the list.

## 📚 Book Recommendations

### 📖 Similar
* The Pragmatic Programmer by David Thomas and Andrew Hunt is relevant because it emphasizes building reliable, trustworthy software through careful design decisions like the grounding fallback strategy implemented here.
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it covers the challenges of building systems that depend on external APIs with quotas, rate limits, and fallback strategies.

### ↔️ Contrasting
* The Shallows: What the Internet Is Doing to Our Brains by Nicholas Carr offers a skeptical view on whether linking sources actually improves information quality or just creates an illusion of depth without deeper engagement.

### 🔗 Related
* Working in Public: The Making and Maintenance of Open Source Software by Nadia Eghbal explores how software is built in the open and the value of transparent attribution, which connects to the theme of citing sources in AI-generated content.
