---
share: true
aliases:
  - 🕵️‍♀️💼👥 Agents
title: 🕵️‍♀️💼👥 Agents
URL: https://bagrounds.org/articles/agents
Author:
tags:
---
[Home](../index.md) > [Articles](./index.md)  
# [🕵️‍♀️💼👥 Agents](https://huyenchip.com//2025/01/07/agents.html)  
  
## 🤖 AI Summary  
🤖 **Agents** are 🎯 anything that can **perceive** its environment and **act** upon that environment.  
🧠 **AI** is the **brain** that ⚙️ **processes** the task, 🗺️ **plans** a sequence of actions, and 🕵️‍♀️ **determines** whether the task has been accomplished.  
🔑 The 📈 **success** of an agent depends on the **tools** it has access to and the **strength** of its AI planner.  
  
### 🛠️ Tools  
🔌 **External tools** make an agent 🚀 vastly more capable, allowing it to both 👁️ **perceive** the environment (read-only actions) and ✍️ **act** upon it (write actions).  
📚 **Knowledge augmentation** tools 💡 augment the agent's knowledge, such as 📄 text retrievers, 🖼️ image retrievers, and 📊 SQL executors.  
🌐 **Web Browse** is an umbrella term for tools that 🌍 access the internet, preventing models from becoming ⏳ stale and enabling access to 📰 up-to-date information.  
💪 **Capability extension** tools 📈 address inherent limitations of AI models, such as ➕ calculators for math, 🧑‍💻 code interpreters for execution, and 🗣️ translators for language.  
🎨 Tools can also turn 📝 text-only or 🖼️ image-only models into 🌟 **multimodal** models by leveraging other models (e.g., DALL-E for image generation).  
  
### 🗺️ Planning  
🧠 **Foundation models** are used as **planners** to 💡 process tasks, 📊 plan action sequences, and ✅ determine task completion.  
❓ An **open question** is how well foundation models can plan, with some researchers believing autoregressive LLMs 🚫 cannot plan effectively.  
🔍 **Planning** is fundamentally a **search problem**, involving searching among different paths to a goal and predicting outcomes.  
🔙 While some argue autoregressive models cannot ↩️ backtrack, they can 🔄 revise paths or 🔄 start over if a chosen path is not promising.  
🚧 **Planning failures** can occur due to 😵 hallucinated action sequences or incorrect parameters.  
💡 **Tips for better planning** include ✍️ writing better system prompts, 📚 giving better tool descriptions, ♻️ refactoring complex functions, 🚀 using stronger models, and 🧑‍🏫 finetuning models for plan generation.  
📞 **Function calling** is the process of invoking tools, where tools are described by their execution entry point, parameters, and documentation.  
📏 **Planning granularity** refers to the level of detail in a plan; a detailed plan is harder to generate but easier to execute, while a higher-level plan is easier to generate but harder to execute.  
 hierarchical planning can circumvent this trade-off by generating high-level plans first, then more detailed plans for each sub-section.  
  
### 🚨 Agent Failure Modes and Evaluation  
📉 **Compound mistakes** mean that overall accuracy decreases as the number of steps an agent performs increases.  
💰 **Higher stakes** tasks mean failures could have more severe consequences.  
⏱️ **Efficiency** concerns relate to agents consuming significant API credits or time for multi-step tasks.  
🧐 When working with agents, it's advised to always ask the system to report what parameter values it uses for each function call and inspect these values for correctness.  
  
## 🤔 Evaluation  
The article presents a clear and concise framework for understanding AI agents, focusing on their components, capabilities, and challenges. It effectively defines agents and elaborates on the critical roles of tools and planning. The comparison with Anthropic's blog post highlights conceptual alignment while emphasizing the unique focus on planning, tool selection, and failure modes in this article.  
  
To gain a better understanding, it would be beneficial to explore:  
* ⚖️ **Real-world case studies**: 🌍 Practical examples of successful and unsuccessful agent deployments across various industries could provide deeper insights into their practical implications and limitations.  
* 📊 **Quantitative evaluation metrics**: 📏 While the article discusses failure modes, more specific quantitative metrics and benchmarks for evaluating agent performance beyond anecdotal evidence would be valuable.  
* 🔬 **Advancements in planning for LLMs**: 🧠 Further research or recent breakthroughs addressing the skepticism around LLMs' inherent planning capabilities would be an interesting area to investigate.  
  
## 📚 Book Recommendations  
* 📖 **[🤖🧠 Artificial Intelligence: A Modern Approach](../books/artificial-intelligence-a-modern-approach.md)** by Stuart Russell and Peter Norvig: A classic foundational text in AI, defining the field and intelligent agents, offering a comprehensive overview.  
* 📘 **[🤖🏗️ AI Engineering: Building Applications with Foundation Models](../books/ai-engineering-building-applications-with-foundation-models.md)** by Chip Huyen: The source from which this post is adapted, likely offering a more in-depth exploration of the topics discussed, especially the practical aspects of building AI systems.  
* **[💾⬆️🛡️ Designing Data-Intensive Applications: The Big Ideas Behind Reliable, Scalable, and Maintainable Systems](../books/designing-data-intensive-applications.md)** by Martin Kleppmann: While not directly about AI agents, this book provides essential knowledge on building robust, scalable, and reliable data systems, which are often the backbone for agents requiring extensive data access and processing.  
* **[🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md)** by Daniel Kahneman: Explores the two systems that drive the way we think, offering insights into cognitive processes that could be analogously applied to understanding how AI models "reason" and "plan," and their potential biases or limitations.  
* **[🧬👥💾 Life 3.0: Being Human in the Age of Artificial Intelligence](../books/life-3-0.md)** by Max Tegmark: Provides a broader philosophical perspective on the future of AI and its potential impact on humanity, relevant for considering the long-term implications of advanced autonomous agents.