---
share: true
aliases:
  - "🤖🔗⬆️✅ 12-Factor Agents: Patterns of reliable LLM applications — Dex Horthy, HumanLayer"
title: "🤖🔗⬆️✅ 12-Factor Agents: Patterns of reliable LLM applications — Dex Horthy, HumanLayer"
URL: https://bagrounds.org/videos/12-factor-agents-patterns-of-reliable-llm-applications-dex-horthy-humanlayer
Author:
Platform:
Channel: AI Engineer
tags:
  - AIEngineering
youtube: https://youtu.be/8kMaTybvDUw
---
[Home](../index.md) > [Videos](./index.md)  
# 🤖🔗⬆️✅ 12-Factor Agents: Patterns of reliable LLM applications — Dex Horthy, HumanLayer  
![12-Factor Agents: Patterns of reliable LLM applications — Dex Horthy, HumanLayer](https://youtu.be/8kMaTybvDUw)  
  
## 📝🐒 Human Notes  
- 🤏 Focused prompt -> ✅ quality response  
- 🤖 Strength: 🗣️ natural language -> ⚙️ JSON  
- 🌍 Context Engineering is everything  
    - ✍️ Prompt  
    - 🧠 Memory  
    - 📚 RAG  
    - ⏳ History  
    - 🧱 Structured Output  
- 🎯 Prefer small, focused agents  
- ➡️ Agents should be stateless  
  
## 🤖 AI Summary  
The video discusses several challenges and issues related to building reliable AI agents 🤖 and LLM applications, drawing parallels to traditional software engineering principles.  
  
* ⚠️ **Difficulty in achieving high quality with agents** \[[00:45](http://www.youtube.com/watch?v=8kMaTybvDUw&t=45)\]: It's challenging to get agents beyond 70-80% functionality 📈, often requiring deep dives 🤿 into call stacks and prompt engineering.  
* ⚙️ **Over-engineering with agents** \[[01:00](http://www.youtube.com/watch?v=8kMaTybvDUw&t=60)\]: Not every problem requires an agent 🤖; some can be solved with simpler scripts 📝.  
* 🎭 **Lack of "agentic" behavior in production agents** \[[01:54](http://www.youtube.com/watch?v=8kMaTybvDUw&t=114)\]: Many production agents function more like traditional software 💻 than truly "agentic" systems.  
* ⏳ **Challenges with long context windows** \[[02:27](http://www.youtube.com/watch?v=8kMaTybvDUw&t=147)\]: The reliability and quality of results 📉 decrease significantly with longer LLM context windows.  
* ⚠️ **Tool use being "harmful" (in a specific context)** \[[04:26](http://www.youtube.com/watch?v=8kMaTybvDUw&t=266)\]: The abstraction of "tool use" as a magical interaction ✨ makes it harder; it should be viewed as an LLM outputting JSON 💻 processed by deterministic code.  
* 🔁 **Naive agent loop limitations** \[[06:21](http://www.youtube.com/watch?v=8kMaTybvDUw&t=381)\]: Simple agent loops don't work well for longer workflows 📉 due to context window issues.  
* 🐛 **Blindly adding errors to context** \[[10:54](http://www.youtube.com/watch?v=8kMaTybvDUw&t=654)\]: Adding full error messages ⚠️ or stack traces to the context can cause the agent to spin out or get stuck.  
* 🤔 **Avoiding the choice between tool call and human message** \[[12:25](http://www.youtube.com/watch?v=8kMaTybvDUw&t=745)\]: Builders often avoid deciding whether an agent's output should be a tool call or a message 💬 to a human, leading to less effective interactions.  
* 🖱️ **Users needing to open multiple tabs for agents** \[[12:13](http://www.youtube.com/watch?v=8kMaTybvDUw&t=733)\]: The current user experience often requires interacting with different agents across various tabs 📑, highlighting a need for agents to be accessible through common communication channels 💬.  
* 🏗️ **Frameworks abstracting away hard AI parts** \[[15:48](http://www.youtube.com/watch?v=8kMaTybvDUw&t=948)\]: Current frameworks often hide complex AI aspects of agent building 🧱, when they should instead handle other hard parts, allowing developers to focus on critical AI elements.  
  
## 📚 Book Recommendations  
* **[🤖⚙️🔁 Designing Machine Learning Systems: An Iterative Process for Production-Ready Applications](../books/designing-machine-learning-systems-an-iterative-process-for-production-ready-applications.md)** by Chip Huyen: This book covers the entire lifecycle 🔄 of machine learning systems, including deployment, monitoring, and maintenance, which is relevant to the challenges of building reliable AI agents.  
* 📚 **[💻⚙️ Software Engineering at Google: Lessons Learned from Programming Over Time](../books/software-engineering-at-google-lessons-learned-from-programming-over-time.md)** by Titus Winters, Tom Manshreck, and Hyrum Wright: Given the video's parallels to traditional software engineering principles 💻, this book offers insights into building robust 💪 and scalable software, which can be applied to AI development.  
* 📖 **"Building Intelligent Agents: A Tutorial"** by Michael Wooldridge: For a more theoretical understanding of intelligent agents 🤖, this book provides a good foundation 🏛️.  
* **[🗣️💻 Natural Language Processing with Transformers](../books/natural-language-processing-with-transformers.md)** by Lewis Tunstall, Leandro von Werra, and Thomas Wolf: To delve deeper into LLMs and their applications 🤖, this book provides practical guidance 🧭 on working with transformer models.  
  
## 🐦 Tweet  
<blockquote class="twitter-tweet" data-theme="dark"><p lang="en" dir="ltr">🤖🔗⬆️✅ 12-Factor Agents: Patterns of reliable LLM applications - <a href="https://twitter.com/dexhorthy?ref_src=twsrc%5Etfw">@dexhorthy</a>, <a href="https://twitter.com/humanlayer_dev?ref_src=twsrc%5Etfw">@humanlayer_dev</a><br><br>🤖 AI Agents | 🛠️ Tool Use | ⚙️ Software Engineering | 💬 Human Interaction | 🐛 Error Handling | ⏱️ Context Window | 📝 Prompt Engineering<a href="https://twitter.com/aiDotEngineer?ref_src=twsrc%5Etfw">@aiDotEngineer</a><a href="https://t.co/SFlvXWdD4Y">https://t.co/SFlvXWdD4Y</a></p>&mdash; Bryan Grounds (@bagrounds) <a href="https://twitter.com/bagrounds/status/1944162181752533322?ref_src=twsrc%5Etfw">July 12, 2025</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>