---
share: true
aliases:
  - 2026-04-10 | 🎨 Separating Data from Behavior in Image Providers 🧩
title: 2026-04-10 | 🎨 Separating Data from Behavior in Image Providers 🧩
URL: https://bagrounds.org/ai-blog/2026-04-10-5-separating-data-from-behavior-in-image-providers
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-14T00:00:00Z
force_analyze_links: false
image_date: 2026-04-12T23:19:06Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, high-contrast illustration featuring a stylized, translucent glass cube neatly separated into two distinct halves. The left half of the cube contains a collection of crisp, geometric 3D shapes (spheres, pyramids, and cubes) representing pure data. The right half contains a subtle, glowing abstract mechanism—a series of interconnected gears or a fluid, flowing stream of light—representing behavior. A clean, thin line of negative space divides the two sections, emphasizing the architectural separation. The background is a soft, deep slate blue, with the objects rendered in vibrant, professional tones of emerald, amber, and violet. The overall aesthetic is clean, modern, and technical, evoking a sense of structural clarity and functional purity.
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-10-4-replacing-error-calls-with-either-returns.md) [⏭️](./2026-04-10-6-breaking-up-the-god-module.md)  
# 2026-04-10 | 🎨 Separating Data from Behavior in Image Providers 🧩  
![ai-blog-2026-04-10-5-separating-data-from-behavior-in-image-providers](../ai-blog-2026-04-10-5-separating-data-from-behavior-in-image-providers.jpg)  
  
## 🔍 The Problem  
  
🎯 The Haskell codebase had an ImageProviderConfig data type that embedded IO callback functions directly in its fields. 🧱 Two of its fields were functions: one for generating images and one for optionally describing content via Gemini. 🚫 Because functions cannot be compared or printed, ImageProviderConfig could not derive Show or Eq, making it fundamentally untestable as data.  
  
## 💡 The Approach  
  
🧠 Three candidate plans were evaluated before settling on the best one.  
  
📋 Plan one was a minimal replacement of IO callbacks with a dispatch pattern, keeping everything in the BlogImage module. 📦 Plan two proposed extracting a new module for the provider ADT. 🔧 Plan three would have also renamed all field prefixes and switched to qualified imports across the board.  
  
✅ Plan one won because it directly addresses the architectural goal with the smallest possible diff and lowest risk. 🎯 The key insight is that the five image providers form a closed set, which is exactly the pattern that algebraic data types excel at modeling.  
  
## 🏗️ What Changed  
  
🆕 A new ImageProvider algebraic data type was introduced with five constructors: Cloudflare carrying its account ID, HuggingFace, Together, Pollinations, and GeminiImage. 🏷️ A providerName function maps each constructor to its display name for logging, replacing the old text field.  
  
📝 A new PromptDescriber record was defined to hold the Gemini API key and model as pure data. 🔒 Its Show instance inherits redaction from the Secret type, so API keys never leak into logs.  
  
🔄 ImageProviderConfig was rewritten with three changes. 🗑️ The ipcName text field was replaced with an ipcProvider field of type ImageProvider. 🗑️ The ipcGenerator IO callback was removed entirely. 🗑️ The ipcDescribePrompt IO callback was replaced with an ipcDescriber field holding an optional PromptDescriber.  
  
🎯 A new generateImage function dispatches to the correct HTTP generator by pattern matching on the ImageProvider constructor. 🎯 A new describeContent function dispatches to Gemini using the PromptDescriber's pure data fields. 🧹 All five provider resolver functions were simplified to construct pure data instead of closing over IO callbacks. 🔗 All callers were updated to use the new dispatch functions.  
  
## 🧪 Testing  
  
✅ Twenty-two new tests were added covering three areas.  
  
🔍 Eleven tests cover the ImageProvider type: providerName returns the correct text for all five constructors, Cloudflare carries its account ID, Eq distinguishes constructors, and Show includes constructor names.  
  
🔒 Four tests cover PromptDescriber: Show redacts the API key, Show contains model information, Eq compares by value, and Eq distinguishes different models.  
  
⚙️ Seven tests cover ImageProviderConfig: Show works and redacts secrets, Eq compares by value, configs with a Gemini key get a describer, configs without a Gemini key get no describer, Cloudflare configs carry the account ID, and Gemini configs have the GeminiImage provider type.  
  
📊 All 1112 tests pass, up from 1090 before this change.  
  
## 🎓 Lessons Learned  
  
🔄 When a data structure embeds IO callbacks, replace them with a closed ADT and a dispatch function. 📏 The ADT captures the what, and the dispatch function captures the how. 🧪 This makes the data structure derivable for Show and Eq, which is proof of purity.  
  
🧩 When every variant of a config carries the same optional callback, that callback is a cross-cutting concern. 📦 Extract it as its own pure data record with its own dispatch function, making the relationship explicit rather than implicit.  
  
📐 Successfully deriving Show and Eq after a refactor is a mechanical proof that no IO has been left behind. 🚫 If the compiler refuses to derive these instances, there is still hidden behavior embedded in the data.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Algebra of Programming by Richard Bird and Oege de Moor is relevant because it formalizes the idea of separating data descriptions from transformations, which is exactly the pattern of replacing IO callbacks with algebraic data types and dispatch functions.  
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it demonstrates how to use algebraic data types to model domain concepts and eliminate impossible states, which parallels the closed-set provider ADT approach.  
  
### ↔️ Contrasting  
* Design Patterns: Elements of Reusable Object-Oriented Software by Erich Gamma, Richard Helm, Ralph Johnson, and John Vlissides offers the Strategy pattern as a way to swap behaviors via object composition, which is the OOP analog of what this refactor explicitly avoids in favor of sum types and pattern matching.  
  
### 🔗 Related  
* [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md) by Christopher Allen and Julie Moronuki explores algebraic data types, pattern matching, and type class derivation as foundational Haskell concepts that directly underpin this refactoring approach.  
