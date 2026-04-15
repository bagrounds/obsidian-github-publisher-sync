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
