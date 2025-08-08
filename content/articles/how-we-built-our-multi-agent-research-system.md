---
share: true
aliases:
  - 🤖🧠👨‍💻🏗️ How we built our multi Agent research system
title: 🤖🧠👨‍💻🏗️ How we built our multi Agent research system
URL: https://bagrounds.org/articles/how-we-built-our-multi-agent-research-system
Author: 
tags: 
---
[Home](../index.md) > [Articles](./index.md)  
# [🤖🧠👨‍💻🏗️ How we built our multi Agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)  
## 🤖 AI Summary  
* 🧠 **The multi-agent research system** is an architecture developed by Anthropic that uses multiple Claude agents to explore complex topics.  
* 💡 **A lead agent** plans a research process based on user queries, then creates parallel subagents to search for information simultaneously.  
* ⚖️ **This system excels at "breadth-first" queries** that require pursuing multiple independent directions at once, a flexible approach that mirrors how humans conduct research.  
* 📈 **The system with Claude Opus 4** as the lead agent and Claude Sonnet 4 subagents outperformed a single-agent Claude Opus 4 by 90.2% on internal evaluations.  
* ⚙️ **Performance variance is primarily explained by token usage**, which accounts for 80% of the performance, with the number of tool calls and model choice making up the rest.  
  
## 🤔 Evaluation  
* 🧐 While the Anthropic system demonstrates impressive performance gains by distributing work across multiple agents, it's worth considering other approaches.  
* 📚 Some research focuses on creating **highly capable single agents** with larger context windows and more sophisticated reasoning abilities, rather than a multi-agent structure.  
* ⚖️ Another perspective is to explore **hybrid models** that combine single-agent depth with multi-agent breadth, allowing for a more nuanced approach.  
* ❓ Further topics to explore for a better understanding include the **cost-benefit analysis** of token usage for different problem types, the **trade-offs between parallel and sequential processing** in AI agents, and the **potential for emergent behaviors** or unintended consequences in complex multi-agent systems.  
  
## 📚 Book Recommendations  
  
#### 🧠 Similar Perspectives: Multi-Agent and Emergent Systems  
  
* 🤖 **Vehicles: Experiments in Synthetic Psychology** by Valentino Braitenberg: This classic book provides simple, elegant thought experiments on how complex, seemingly intelligent behaviors can emerge from the interactions of a few simple rules, offering a foundational perspective on bottom-up system design similar to a multi-agent approach.  
* 🐢 **Turtles, Termites, and Traffic Jams** by Mitchel Resnick: This book explores the power of decentralized systems and emergent phenomena. It shows how simple agents following local rules can collectively produce sophisticated patterns, a core concept behind multi-agent systems.  
  
#### ⚖️ Contrasting Perspectives: Single-Agent and Philosophical Approaches  
  
* **[🧠💻🤖 Deep Learning](../books/deep-learning.md)** by Ian Goodfellow, Yoshua Bengio, and Aaron Courville: This is a foundational textbook on the opposing paradigm of deep neural networks. It focuses on single, large models that learn complex representations from data, representing a contrasting "single-agent" approach to AI.  
* **[🤖⚠️📈 Superintelligence: Paths, Dangers, Strategies](../books/superintelligence-paths-dangers-strategies.md)** by Nick Bostrom: This book contrasts with the multi-agent approach by focusing on the risks and ethical considerations of building a singular, highly intelligent AI, including the potential for complex systems to act in ways that are misaligned with human intentions.  
* 💻 **The Master Algorithm** by Pedro Domingos: This book provides a broad overview of different machine learning paradigms, offering a wider context on the various ways AI systems can be designed to learn and solve problems, beyond just a multi-agent architecture.  
* 🧘 **I Am a Strange Loop** by Douglas Hofstadter: A contrasting perspective that delves into the nature of consciousness and self-awareness, offering a philosophical counterpoint to the purely functional and technical approach of building an AI research system.  
  
#### 💡 Creatively Related: Analogies from Other Fields  
  
* **[👤🧬 The Selfish Gene](../books/the-selfish-gene.md)** by Richard Dawkins: While not about AI, it offers a foundational understanding of how independent agents (genes) interact to produce complex, emergent behaviors in biological systems, which is a great creative analogy for a multi-agent AI system.  
* **[♾️📐🎶🥨 Gödel, Escher, Bach: An Eternal Golden Braid](../books/godel-escher-bach.md)** by Douglas Hofstadter: A deeply creative recommendation, this book explores how complex, hierarchical systems and emergent properties arise from simple, self-referential rules. It is a masterpiece that provides a philosophical and logical framework for understanding complex systems like multi-agent AI.  
* 💰 **The Wealth of Nations** by Adam Smith: This classic economic text introduces the idea of the "invisible hand," where individual agents (people) pursuing their own interests can lead to a coherent, functional system (a market). This concept is a powerful analogy for how decentralized, multi-agent AI systems can achieve a collective goal.