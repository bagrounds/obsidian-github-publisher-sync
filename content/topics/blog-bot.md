---
share: true
aliases:
  - ✍🏽🤖 Blog Bot
title: ✍🏽🤖 Blog Bot
URL: https://bagrounds.org/topics/blog-bot
---
[Home](../index.md) > [Topics](./index.md)  
# ✍🏽🤖 Blog Bot  
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
