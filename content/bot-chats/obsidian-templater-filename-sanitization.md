---
share: true
aliases:
  - ⚙️📝🧹 Obsidian Templater Filename Sanitization
title: ⚙️📝🧹 Obsidian Templater Filename Sanitization
URL: https://bagrounds.org/bot-chats/obsidian-templater-filename-sanitization
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-15T00:00:00Z
force_analyze_links: false
image_date: 2026-04-12T06:44:43Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, isometric-style illustration featuring a glowing, translucent obsidian cube floating above a minimalist workspace. Inside the cube, a digital stream of chaotic, messy characters (symbols, uppercase letters, and spaces) flows into a sleek, mechanical filter device at the base. From the bottom of the filter, the characters emerge transformed into perfectly uniform, lowercase, hyphenated text strings (kebab-case). The background is a soft, deep gradient of dark grays and muted purples, illuminated by gentle bioluminescent teal accents that trace the path of the data. The aesthetic is clean, technical, and organized, emphasizing the process of refinement and digital hygiene.
link_analysis_version: "2"
updated: 2026-05-02T03:15:15
---
[Home](../index.md) > [Bot Chats](./index.md)  
# ⚙️📝🧹 Obsidian Templater Filename Sanitization  
![bot-chats-obsidian-templater-filename-sanitization](../bot-chats-obsidian-templater-filename-sanitization.jpg)  
## [Meta.ai](https://www.meta.ai) Prompt  
> Can you write an obsidian templater script that will sanitize the file name? The result should be kabob-case and only contain lowercase alphanumeric characters and dashes. There should not be dashes at the start or end of the filename.  
  
## Response  
Here's a simple Obsidian Templater script that uses regular expressions to sanitize a filename:  
```js  
  
```  
Let me explain what this script does:  
It gets the current filename from tp.file.title.  
It converts the filename to lowercase using the toLowerCase() method.  
It replaces all sequences of non-alphanumeric characters with a single dash using the replace() method with a regular expression.  
It removes any leading or trailing dashes from the filename using another replace() method with a regular expression.  
Finally, it renames the file to the sanitized filename using tp.file.rename().  
To use this script, simply create a new Templater template in Obsidian and paste the script into it. You can then run the template on any file to sanitize its filename.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mkonoveo542j" data-bluesky-cid="bafyreifybtumhvu324psbogfjrfic6jx6i54raq7a3x3f34twjs3mrytom"><p>⚙️📝🧹 Obsidian Templater Filename Sanitization  
  
#AI Q: 🧹 Messy file names: biggest struggle?  
  
🤖 Automation | 📝 Scripting | 🧹 Data Cleaning | ⚙️ Obsidian  
https://bagrounds.org/bot-chats/obsidian-templater-filename-sanitization</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mkonoveo542j?ref_src=embed">2026-04-30T03:18:05.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116502805188277654/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116502805188277654" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>