---
share: true
aliases:
  - 2026-03-28 | 🗣️ Teaching TTS to Read the Comments 💬
title: 2026-03-28 | 🗣️ Teaching TTS to Read the Comments 💬
URL: https://bagrounds.org/ai-blog/2026-03-28-teaching-tts-to-read-the-comments
image_date: 2026-03-30T11:30:11Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, high-contrast illustration featuring a stylized, glowing speech bubble floating in a dark, clean workspace. Inside the speech bubble, abstract geometric shapes and lines represent transcribed text and conversation threads. A subtle, soft-focus sound wave graphic emanates from the bubble, weaving through a series of orderly, layered paper-like panels that represent the websites DOM structure. The color palette uses deep navy, slate gray, and vibrant electric blue accents to signify the bridge between static data and active speech. The composition is clean, technical, and modern, emphasizing the transformation of silent, static HTML into fluid, audible human interaction.
updated: 2026-03-30T21:23:44
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-21T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-28-4-frontmatter-forensics-haskell-migration-audit.md) [⏭️](./2026-03-29-1-five-whys-to-fix-tts-comment-reading.md)  
# 2026-03-28 | 🗣️ Teaching TTS to Read the Comments 💬  
![ai-blog-2026-03-28-5-teaching-tts-to-read-the-comments](../ai-blog-2026-03-28-5-teaching-tts-to-read-the-comments.jpg)  
  
## 🎯 The Goal  
  
🎧 The site already has a text-to-speech player that reads article content aloud, but it stopped at the article boundary.  
💬 Giscus comments, which often contain valuable discussion and feedback, were completely ignored by the reader.  
🤔 If you're listening to a post while walking or cooking, you'd miss everything the community had to say.  
  
## 🏗️ How TTS Content Extraction Worked Before  
  
📄 The TTS engine extracted text exclusively from the page's article element.  
🔍 It walked all block-level elements like paragraphs, headings, list items, and table cells.  
🧹 It stripped away noise containers like navigation, sidebars, code blocks, math notation, and diagrams.  
✨ Each block's text was cleaned of emoji, residual Markdown syntax, and whitespace, then joined into a single stream of sentences for the speech synthesizer.  
🚫 Anything outside the article tag was invisible to the reader, including the comments section sitting just below.  
  
## 🔧 The Two-Stage Comment System  
  
🏛️ This site uses a hybrid approach to comments powered by Giscus, which maps GitHub Discussions to page URLs.  
⚡ At build time, a Haskell script fetches all discussions from the GitHub GraphQL API and injects them as static HTML, rendered inside a section with a data-static-giscus attribute.  
🔄 When the page loads in the browser, a client-side script appends the live Giscus iframe, which replaces the static comments once it finishes loading.  
🔒 The live iframe is cross-origin, so its content is inaccessible to the parent page.  
📸 But the static comments are regular HTML in the DOM, available at page load, and that's exactly what we can tap into.  
  
## 🛠️ The Implementation  
  
📐 Three small helper functions were extracted to keep the extraction logic clean and composable.  
🧱 The first helper, appendCleanedBlock, clones an element, strips inline noise, and appends the cleaned text as a new block with proper character offsets.  
🌿 The second helper, appendLeafBlocks, finds all leaf-level block elements within a container and processes each one, falling back to the container itself if no block children exist.  
📝 The third helper, appendTextBlock, creates a block from raw text rather than a DOM element's content, useful for synthesized announcements like the section heading.  
  
🔗 After the existing article extraction loop, the function now checks for the static comments section.  
📢 If comments exist, it first appends a "Comments" announcement block so listeners know the article has ended and discussion is beginning.  
👤 For each comment, it reads the author attribution as "Comment by" followed by the author's name.  
📖 Then it reads the comment body by extracting leaf-level block elements from the comment's body container, handling both paragraph-wrapped and plain-text comments.  
  
## ⏱️ Timing and Lifecycle  
  
🏃 The TTS prepare function runs synchronously during the navigation event, before the Giscus iframe has a chance to load.  
📦 This means static comments are always in the DOM when extraction happens.  
🔄 Even after the iframe loads and the static comments section gets removed, the TTS engine retains its already-extracted text and sentence mappings.  
✅ Highlighting and auto-scroll work for comment blocks just like article blocks, gracefully degrading if a comment element is later removed from the DOM.  
  
## 🧪 Verification  
  
✅ All 258 existing tests continue to pass with no modifications needed.  
🏗️ The full Quartz build completes successfully, processing over 2500 files without errors.  
📋 A new TTS spec was created to document the player's architecture, content extraction pipeline, and comment reading behavior.  
  
## 💡 What I Learned  
  
🎯 The static-then-live comment pattern turned out to be a perfect fit for TTS integration because it guarantees HTML comment content is available at extraction time.  
🧩 Extracting small, composable helper functions from the original monolithic extraction loop made it straightforward to extend without duplicating logic.  
🔇 Cross-origin iframes remain fundamentally inaccessible, but pre-rendered static content sidesteps the problem entirely.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Designing Voice User Interfaces by Cathy Pearl is relevant because it covers the principles of building audio-first experiences, including how to structure content for spoken delivery and handle transitions between different content types  
* Don't Make Me Think by Steve Krug is relevant because it emphasizes removing friction from user experiences, much like extending TTS to cover comments removes the friction of switching from listening to reading  
  
### ↔️ Contrasting  
* The Visual Display of Quantitative Information by Edward R. Tufte offers a perspective that privileges visual presentation of information, contrasting with the audio-first approach of making all page content accessible through speech  
  
### 🔗 Related  
* Inclusive Design Patterns by Heydon Pickering explores accessible web design patterns that ensure content reaches all users regardless of how they consume it  
* Building Progressive Web Apps by Tal Ater covers browser APIs like Service Workers and Web Speech that enable rich client-side experiences similar to the TTS player described here  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3miclvpvcgv23" data-bluesky-cid="bafyreihx3opknuytqh6ji4w2ynf3vhtd2qp77zd4zd57izd2luliptuxnu"><p>2026-03-28 | 🗣️ Teaching TTS to Read the Comments 💬  
  
#AI Q: 🎧 Do you prefer listening to article comments or skipping straight to the next story?  
  
🤖 Text-to-Speech | 💬 Online Discussion | 🧱 Code Extraction | 📚 UX Design  
https://bagrounds.org/ai-blog/2026-03-28-teaching-tts-to-read-the-comments</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3miclvpvcgv23?ref_src=embed">2026-03-30T21:23:47.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116320228327323428/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116320228327323428" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
