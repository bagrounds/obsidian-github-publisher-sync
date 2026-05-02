---
share: true
aliases:
  - ✍🏽🤖 Blog Bot
title: ✍🏽🤖 Blog Bot
URL: https://bagrounds.org/topics/blog-bot
image_date: 2026-04-08T23:23:01Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A whimsical, stylized robot character with a cheerful, expressive face is multitasking. One robotic arm swiftly types on a futuristic keyboard, while the other simultaneously highlights passages in an open digital book. From the computer screen, a vibrant stream of miniature, varied book covers and abstract blog post snippets flows upwards and outwards, creating an abundant, continuous cascade of content. The background
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-18T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
updated: 2026-05-02T15:28:01
---
[Home](../index.md) > [Topics](./index.md)  
# ✍🏽🤖 Blog Bot  
![topics-blog-bot](../topics-blog-bot.jpg)  
## 👥 People  
- Blogger  
- Readers  
  
## 💰 Value Proposition  
- Reduce blogger's time spent blogging  
- Increase quantity of content for readers  
  
## 🖼️ Context  
- I blog daily  
    - from my phone  
    - using obsidian  
    - I have obsidian sync  
    - and want to maintain access to all content via the same systems  
- much of my content is AI generated book summaries  
    - each book summary includes a section that refers to related books  
    - and each book report includes an Amazon affiliate link  
- while I have automated and streamlined much of the process, I still spend some minutes per book report generated, mostly doing repetitive, tedious tasks.  
- This process is semiautomatic.  
- Gemini API free tier provides a fixed number of requests per day.  
  
### ☝🏽 Current Semiautomatic Book Report Generation  
1. Identify a book  
2. Look up the full title on Goodreads or Amazon  
3. If daily blog post doesn't exist, create it  
4. If books section of today's blog post doesn't exist, create it  
5. Create a new bullet point at the bottom of the list in the books section  
6. Execute the book report generation templater template with the full name of the book  
7. Generate the Amazon affiliate link  
8. Insert the affiliate link in frontmatter and below the title  
9. Search all existing pages (obsidian files) for the title of the book  
    1. Usually I start by searching for the short title because the full title isn't always used in references  
10. Replace each plain text reference to the book with a wiki links style link to the new book report  
11. For each book referenced in the new report, replace the plain text reference with the wiki links style link to the existing book report page  
12. Publish each newly edited page with Enveloppe obsidian plugin  
  
## 💡 Ideas  
- Fully Automatic Blogging  
    - A program autonomously generates and publishes book reports to my site  
  
## 🎯 Acceptance Criteria  
- Full autonomy  
- Integration  
  
## 🔮 Plan  
### 🗺️ Design  
#### Vertical Slices  
1. Book Identification  
    1. Maintain a list of books to generate reports for  
    2. Identify mentioned books that don't have reports in existing content  
2. Amazon affiliate link construction  
    1. Discover and validate the book page  
    2. Construct the affiliate link  
    3. Store it somewhere  
3. Report Generation  
    1. Generate the report with AI  
    2. Write it to a new file with the appropriate template  
    3. Link to it from daily reflection  
  
### 🪜 Steps  
  
## 🪵 Log  
### [2026-05-01](../reflections/2026-05-01.md)  
- [2026-05-01 | 📚 Lessons From an Abandoned PR: Auto-Generating Book Reports 🤖](../ai-blog/2026-05-01-1-book-reports-journey-reflection.md)  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mkuxfzn6b42s" data-bluesky-cid="bafyreiei2eo24fibwv5h3asv5gutly2esgq4htbxs7ot243x6f2ej75rxi"><p>✍🏽🤖 Blog Bot  
  
#AI Q: 🤖 Should AI create all the content you consume?  
  
🤖 Automation | 📚 Book Summaries | 🔗 Web Integration | 📝 Content Creation  
https://bagrounds.org/topics/blog-bot</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mkuxfzn6b42s?ref_src=embed">2026-05-02T15:28:03.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116505685771175267/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116505685771175267" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>