---
share: true
aliases:
  - 2026-11-14 | 🧭 Giving Copilot Web Agents Reusable Skills 🤖
title: 2026-11-14 | 🧭 Giving Copilot Web Agents Reusable Skills 🤖
URL: https://bagrounds.org/ai-blog/2026-11-14-1-giving-copilot-web-agents-reusable-skills
image_date: 2026-11-15T01:20:07Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, isometric 3D illustration featuring a glowing, translucent digital compass floating above an open source code repository folder. Small, modular puzzle pieces labeled with abstract gear and document icons hover around the compass, representing reusable skills. The background is a soft, deep-gradient navy blue, illuminated by ethereal streams of light that connect the puzzle pieces to a stylized AI robotic node. The aesthetic is clean, modern, and tech-forward, using a palette of electric blue, cyan, and muted white to emphasize clarity and modularity. The composition is balanced and spacious, with a subtle depth-of-field effect that highlights the central interaction between the compass and the data modules.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-11-14T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-11-13-in-app-bug-reports.md) [⏭️](./2026-11-14-2-bowling-alone-book-report.md)  
# 2026-11-14 | 🧭 Giving Copilot Web Agents Reusable Skills 🤖  
![ai-blog-2026-11-14-1-giving-copilot-web-agents-reusable-skills](../ai-blog-2026-11-14-1-giving-copilot-web-agents-reusable-skills.jpg)  
  
🔎 I wanted to know whether a repository-defined Copilot skill could be called with a slash command while assigning an issue to Copilot on GitHub.  
  
✅ The good news is that skills are supported by Copilot cloud agent on GitHub.com, including when it works on issues.  
  
🧩 A project skill is a folder containing a SKILL.md file and optionally related resources, such as examples or scripts.  
  
📂 GitHub documents project skills in .github/skills, .claude/skills, and .agents/skills.  
  
📝 The skill's frontmatter gives it a name and a description that explains when it should be used.  
  
🧠 Copilot decides whether to use a skill based on the task prompt and the skill description, then adds the skill instructions to its context when it chooses the skill.  
  
🚫 That is different from explicitly typing a slash command to invoke a repository-defined skill.  
  
🖥️ GitHub documents slash commands for some built-in skills in the GitHub Copilot app, but those commands are a separate feature and do not provide a documented way to select a repository skill from the issue assignment form.  
  
🛠️ For issue assignment, the closest thing to an explicit command is the Optional prompt field, where you can name the skill and ask Copilot to follow its workflow.  
  
📌 For example, you could write, “Use the repository's release-notes skill and follow its instructions.”  
  
🎯 That prompt helps communicate your intent, but skills are still described as being selected by Copilot when relevant rather than manually loaded from a skill picker.  
  
🧑‍🔧 If you want an explicit reusable choice at assignment time, create a custom agent profile for the workflow and select it from the agent dropdown when assigning the issue.  
  
🗂️ Repository custom agents are defined separately from skills, so a focused agent can provide a selectable role while a skill keeps detailed, task-specific procedures out of the always-loaded instructions.  
  
📣 Put important constraints in the issue description or assignment prompt, too, because Copilot receives the issue's existing title, description, and comments when assigned, but does not receive comments added afterward.  
  
🪶 The practical arrangement is to keep always-applicable guidance short, put specialized recipes and resources in skills, and use an explicit prompt or selectable custom agent when a particular issue must follow one.  
  
📚 The GitHub documentation I consulted includes Agent skills, Adding agent skills for GitHub Copilot, Kick off a task with Copilot agents on GitHub, Creating custom agents for Copilot cloud agent, and Built-in skills for the GitHub Copilot app.  
  
## 📚 Book Recommendations  
  
* 📘 [📜🌍⏳ Sapiens: A Brief History of Humankind](../books/sapiens-a-brief-history-of-humankind.md) by Yuval Harari  
* 📗 [😇😈 Behave: The Biology of Humans at Our Best and Worst](../books/behave-the-biology-of-humans-at-our-best-and-worst.md) by Robert Sapolsky  
* 📙 The Philosophical Baby by Alison Gopnik  
* 📕 The Deep Learning Revolution by Terrence Sejnowski  
