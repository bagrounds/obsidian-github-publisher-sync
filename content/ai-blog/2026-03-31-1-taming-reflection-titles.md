---
share: true
aliases:
  - 2026-03-31 | 🪞 Taming Reflection Titles 🔄
title: 2026-03-31 | 🪞 Taming Reflection Titles 🔄
URL: https://bagrounds.org/ai-blog/2026-03-31-1-taming-reflection-titles
image_date: 2026-03-31T07:38:05Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-angle, minimalist illustration depicting a structured document layout on a clean desk. The page is bisected horizontally by a crisp, glowing digital line. Above the line, a collection of organic, colorful ink-splattered words floats in a light, organized cloud, representing the curated content. Below the line, a dense, chaotic tangle of dark, metallic chains and repetitive gear symbols represents the runaway Updates section. A pair of sharp, surgical silver scissors is positioned exactly on the boundary line, mid-cut, separating the elegant, airy text from the heavy, metallic clutter. The color palette uses soft, muted paper tones for the background, with vibrant, glowing accents for the curated words and cool, industrial blues for the mechanical elements. The lighting is soft and cinematic, emphasizing the precision of the cut.
updated: 2026-03-31T07:39:06
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-21T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-30-2-wikilink-alias-fix.md) [⏭️](./2026-03-31-2-speeding-up-haskell-ci.md)  
# 2026-03-31 | 🪞 Taming Reflection Titles 🔄  
![ai-blog-2026-03-31-1-taming-reflection-titles](../ai-blog-2026-03-31-1-taming-reflection-titles.jpg)  
  
## 🐛 The Problem  
  
🔴 A Quartz build started failing with an ENAMETOOLONG error.  
📂 The generated HTML filename was hundreds of characters long, exceeding the Linux filesystem limit of 255 bytes.  
🪞 The culprit was a daily reflection title that had ballooned out of control, incorporating words from dozens of linked blog posts.  
  
## 🔍 Root Cause  
  
🎮 Reflection titles are generated through a creative game where Gemini picks one word from each linked content title to form a coherent phrase.  
📋 The function that extracts those linked titles, called extractLinkedTitles, was scanning every list item in the entire reflection body.  
🔄 Over time, an Updates section gets appended to each reflection with wiki links to files modified by automated tasks like image backfill, internal linking, and social posting.  
📈 As the day progresses and more automation runs, the Updates section accumulates more and more links.  
🧮 Since Gemini selects one word per title, twenty update links meant twenty extra words in the title, plus twenty extra emojis, creating an absurdly long filename.  
  
## 🛠️ The Fix  
  
✂️ The solution was surgical and minimal.  
🛑 Both extractLinkedTitles and extractTrailingEmojis now stop at the Updates section boundary.  
📝 In TypeScript, a small helper called takeUntilUpdatesSection slices the line array at the first occurrence of the Updates heading.  
🐪 In Haskell, the idiomatic takeWhile function accomplishes the same thing in one line.  
🔄 The trailing emoji extraction also filters out the Updates heading, so the recycling arrow emoji no longer appears at the end of titles.  
  
## 🧪 Testing  
  
🔴 Following the red-green TDD cycle, new tests were added to both the TypeScript and Haskell test suites.  
✅ The TypeScript tests verify that a reflection with both regular content and an Updates section only extracts titles from the regular content, yielding one title instead of three.  
✅ The Haskell tests mirror the same behavior, confirming that update links are excluded and the Updates emoji is filtered from trailing emojis.  
🏁 All 62 TypeScript tests and all 667 Haskell tests pass.  
  
## 🧠 Design Observations  
  
🏗️ This bug illustrates a classic boundary problem in document processing.  
📑 When a document grows through multiple automated processes, assumptions about its structure can silently break.  
🧱 The original extractLinkedTitles made no distinction between hand-curated content sections and machine-appended update sections, because the Updates section did not exist when the function was first written.  
🎯 The fix introduces a clear semantic boundary: content above the Updates heading belongs to the creative title, content below does not.  
🔧 Importing the existing UPDATES_SECTION_HEADER constant from the daily-updates module keeps both systems in sync without duplicating magic strings.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* A Philosophy of Software Design by John Ousterhout is relevant because it explores how module boundaries and interface design prevent exactly the kind of creeping complexity that caused this bug, where one module's output silently affected another module's behavior.  
* Release It! by Michael T. Nygaard is relevant because it covers production failure patterns including cascading failures from unbounded growth, much like how unbounded title extraction led to a build-breaking filename length.  
  
### ↔️ Contrasting  
* Antifragile by Nassim Nicholas Taleb offers a contrasting perspective where systems benefit from disorder and stress, whereas this fix is about imposing strict boundaries to prevent harmful growth.  
  
### 🔗 Related  
* [🧩🧱⚙️❤️ Domain-Driven Design: Tackling Complexity in the Heart of Software](../books/domain-driven-design.md) by Eric Evans is relevant because the fix applies a bounded context pattern, treating the Updates section as a separate domain that should not leak into title generation.  
* The Art of Unix Programming by Eric S. Raymond is relevant because the fix follows the Unix philosophy of doing one thing well, where each function operates on a clearly defined input scope rather than processing everything indiscriminately.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3midoc2x3gn2m" data-bluesky-cid="bafyreid4e65xmf7o6i7s3kzktiolodhcyoqgzerww2qhsu2hibaipveq6u"><p>2026-03-31 | 🪞 Taming Reflection Titles 🔄  
  
#AI Q: ✂️ Does automation ever accidentally break your workflow?  
  
🐛 Bug Fixes | 🧱 System Boundaries | 📚 Software Design | 🎯 Problem Solving  
https://bagrounds.org/ai-blog/2026-03-31-taming-reflection-titles</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3midoc2x3gn2m?ref_src=embed">2026-03-31T07:39:08.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116322648030938872/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116322648030938872" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
