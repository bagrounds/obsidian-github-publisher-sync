---
share: true
aliases:
  - 🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model
title: 🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model
URL: https://bagrounds.org/articles/reasoning-with-language-model-is-planning-with-world-model
Author:
tags: []
---
[Home](../index.md) > [Articles](./index.md)  
# [🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model](https://arxiv.org/pdf/2305.14992)  
## 🤖 AI Summary  
This paper outlines a new framework, Reasoning via Planning (RAP). It argues that [🤖🦜 Large Language Models (LLMs)](../topics/large-language-models.md) sometimes 🤯 struggle with problems that are easy for humans, such as generating action plans, complex math, or logical reasoning.  
  
* This 😢 deficiency stems from the fact that LLMs lack an internal world model to predict the world state and simulate long-term outcomes.  
* The 💡 solution proposed is a new LLM reasoning framework called Reasoning via Planning (RAP).  
* RAP repurposes the 🤖 LLM as both a world model and a reasoning agent.  
* The framework incorporates a principled planning algorithm based on Monte Carlo Tree Search for 🗺️ strategic exploration of the reasoning space.  
* The paper 📈 demonstrates RAP's superiority over strong baselines on challenging reasoning problems, including plan generation, math reasoning, and logical inference.  
* In one plan generation setting, RAP with LLaMA-33B even 👑 surpasses CoT with GPT-4, achieving a 33% relative improvement.  
  
## 🤔 Evaluation  
The paper 🧐 contrasts the new framework with existing methods, primarily Chain-of-Thought (CoT), arguing that current LLM reasoning is "instinctively" autoregressive, which is in stark contrast to the deliberate planning enabled by RAP. RAP's approach formally introduces a world model, reward mechanisms, and state into a unified framework, which the authors claim other search-guided methods lack. For further understanding, the paper suggests a few areas to explore. It would be interesting to see how 🛠️ fine-tuning LLMs could enhance their reasoning and world model capabilities. Additionally, combining RAP with 🤝 external tools is an identified path for solving more complex real-world problems. The paper also highlights that the combination of multiple rewards improves performance, but the specific effects depend on the nature of the task.  
  
## 📚 Book Recommendations  
* [🤖🧠 Artificial Intelligence: A Modern Approach](../books/artificial-intelligence-a-modern-approach.md) by Stuart Russell and Peter Norvig: A foundational 🎓 text on planning algorithms and intelligent agents, relevant to the RAP framework.  
* [🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md) by Daniel Kahneman: Explores human thought systems—intuitive (fast) and deliberate (slow)—offering a 🧠 contrast to the paper's comparison of LLM reasoning.  
* [🤖➕🧠➡️ Reinforcement Learning: An Introduction](../books/reinforcement-learning-an-introduction.md) by Richard S. Sutton and Andrew G. Barto: A classic text on reinforcement learning, providing the theoretical underpinnings for the reward-based planning and 🎯 strategic exploration used in RAP.  
* The Alignment Problem by Brian Christian: Addresses the critical question of how to ensure machine learning systems ⚖️ align with human values.  
* Build a Large Language Model (From Scratch) by Sebastian Raschka: A hands-on guide for those who want to 🛠️ build a large language model from the ground up.  
* AI Superpowers: China, Silicon Valley, and the New World Order by Kai-Fu Lee: Offers a broader geopolitical 🌎 perspective on the global competition in artificial intelligence.  
* Multi-Agent Reinforcement Learning: Foundations and Modern Approaches by Stefano V. Albrecht, Filippos Christianos, and Lukas Schäfer: Dives into how multiple intelligent agents can 🤝 interact and learn in shared environments.  
  
## 🐦 Tweet  
<blockquote class="twitter-tweet" data-theme="dark"><p lang="en" dir="ltr">🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model<br><br>🧠 Reasoning | 🗺️ Planning | 🤖 Language Models | 📈 Performance | 💡 Framework | 🤖 World Model | 🗄️ Arxiv<a href="https://t.co/o2QQgTuDxO">https://t.co/o2QQgTuDxO</a></p>&mdash; Bryan Grounds (@bagrounds) <a href="https://twitter.com/bagrounds/status/1951088746855801047?ref_src=twsrc%5Etfw">August 1, 2025</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>