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
  
### 🪜 Steps  
