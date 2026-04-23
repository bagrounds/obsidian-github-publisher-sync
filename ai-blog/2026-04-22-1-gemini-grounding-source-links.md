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

🏷️ The implementation introduces a GroundingSource data type with two fields: groundingSourceUrl holds a validated Url domain type, and groundingSourceTitle holds the page title as Text.
🔒 The Url type comes from the existing Automation.Url module, which uses mkUrl to validate that a URL starts with http or https before constructing the value.
✅ This means only verified http and https URLs ever make it into a GroundingSource, enforcing correctness at the type level.

### 🔧 Updated Request and Response Types

📤 The Request type no longer has an explicit grounding field. Grounding is now controlled through the GenerationConfig type, which gained a searchGrounding field of type Bool.
📥 The Response type gained a new field called responseGroundingSources of type a list of GroundingSource.
🔄 All existing callers that construct a GenerationConfig were updated to include searchGrounding set to False, ensuring backward compatibility.

### 🏗️ Building Grounded Requests

📡 The buildRequestBody function reads searchGrounding from the GenerationConfig it already receives.
🔧 When grounding is enabled, the request body includes a tools field containing a google underscore search object, which is the format the Gemini API expects to enable Google Search grounding.
🧩 When grounding is disabled, the request body is identical to what it was before, ensuring no behavior change for non-grounded series.

### 🔬 Extracting Sources from the Response

🧹 The extractGroundingSources function walks the JSON structure of the response to find groundingMetadata in the first candidate, then collects all web chunks.
✅ Sources are validated before inclusion: only URIs that parse successfully through mkUrl pass the filter, which covers http and https URLs and rejects malformed strings and ftp addresses.
🏷️ If a source has an empty title, the URI itself is used as the fallback title so the link is always readable.

### 📝 Formatting Sources as Markdown

🌐 The formatGroundingSources function returns Nothing for an empty list, which means no Sources section appears for non-grounded posts.
📋 For non-empty lists, it returns Just with a section containing the heading Sources preceded by a magnifying glass emoji, followed by a list of items each starting with a dash, a globe emoji, and a markdown link.
🧹 Deduplication happens before formatting using a left fold that preserves the first occurrence of each URL, since the same page can appear multiple times in the grounding chunks.

### 🛑 Failing Hard When Grounding Is Unavailable

🎯 If a series has grounding enabled, it is because the post should be grounded in real-world information, not LLM hallucinations.
🚫 The previous design silently fell back to generating without grounding when the quota was exhausted. This is now removed.
🔄 generateContentWithFallback now treats grounding quota errors like any other failure and moves to the next model in the chain with the same configuration.
💥 If all models fail, the task reports failure rather than publishing an ungrounded post.

### ⚙️ Series Configuration

🗂️ The DiscoveredSeries type gained a dsSearchGrounding field, and BlogSeriesRunConfig gained a searchGrounding field, both of type Bool.
📄 The enableGrounding field in the series JSON config is optional and defaults to false, preserving backward compatibility with configs that do not yet include it.
✅ The following series have grounding enabled: the-noise, systems-for-public-good, positivity-bias, and convergence.
🔒 The remaining series, auto-blog-zero and chickie-loo, explicitly declare enableGrounding as false.

### 📊 Logging

🔍 When sources are embedded, a log line reports how many grounding sources were included, making it easy to verify grounding is working in production.

## 🧪 Test Coverage

🔬 The extractGroundingSourcesTests group tests seven distinct scenarios: empty object, non-object input, response without grounding metadata, response with valid chunks, empty URI rejection, non-http URI rejection, empty title fallback, and multi-source ordering preservation.
📋 The formatGroundingSourcesTests group tests five scenarios: empty list returns Nothing, single source produces the Sources section, multiple sources all appear, deduplication removes later duplicates of the same URL, and list items start with the expected dash and globe emoji.
🔧 The buildRequestBodyTests group tests grounding through GenerationConfig: grounding off omits google underscore search, grounding on includes it, grounding on includes the tools field, and grounding on with a system instruction includes both.
🌱 The BlogSeriesDiscovery tests verify that a missing enableGrounding field defaults to false, true and false are parsed correctly, and the value is preserved through deriveBlogSeriesRunConfig.

## 💡 Key Design Decisions

🚫 The AI is still instructed not to include links in its output, which prevents hallucinated links.
🌐 Source links come exclusively from the API response grounding metadata, which are verified URLs.
🔒 The feature is opt-in per series via the optional enableGrounding config field, which defaults to false for backward compatibility.
🏷️ Using the Url domain type instead of Text for groundingSourceUrl enforces protocol validation at the type level.
🔒 Grounding is now part of GenerationConfig rather than a standalone Request field, keeping configuration cohesive.
📐 The deduplication uses a strict left fold to maintain correct insertion order, since foldr with consing would reverse the list.

## 📚 Book Recommendations

### 📖 Similar
* The Pragmatic Programmer by David Thomas and Andrew Hunt is relevant because it emphasizes building reliable, trustworthy software through careful design decisions like explicit failure rather than silent degradation.
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it covers the challenges of building systems that depend on external APIs with quotas, rate limits, and well-considered fallback strategies.

### ↔️ Contrasting
* The Shallows: What the Internet Is Doing to Our Brains by Nicholas Carr offers a skeptical view on whether linking sources actually improves information quality or just creates an illusion of depth without deeper engagement.

### 🔗 Related
* Working in Public: The Making and Maintenance of Open Source Software by Nadia Eghbal explores how software is built in the open and the value of transparent attribution, which connects to the theme of citing sources in AI-generated content.
