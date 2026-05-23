---
share: true
aliases:
  - 🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model
title: 🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model
URL: https://bagrounds.org/articles/reasoning-with-language-model-is-planning-with-world-model
Author:
tags: []
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-14T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
image_date: 2026-05-16T16:36:26Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A stylized, high-tech visualization of a decision-tree structure branching out from a glowing, translucent digital brain. The nodes of the tree are represented by geometric icons—cogs, lightbulbs, and map pins—interconnected by luminous data lines that fade into a deep, dark blue background. In the foreground, a sleek, semi-transparent robotic silhouette is shown interacting with these branches, carefully selecting a path. The lighting is focused and cinematic, using neon cyan and soft amber gradients to evoke a sense of deliberate, strategic planning. The overall aesthetic is clean, modern, and abstract, emphasizing the transition from chaotic raw data to structured, logical reasoning.
updated: 2026-05-23T11:39:27
---
[Home](../index.md) > [Articles](./index.md)  
# [🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model](https://arxiv.org/pdf/2305.14992)  
![articles-reasoning-with-language-model-is-planning-with-world-model](../articles-reasoning-with-language-model-is-planning-with-world-model.jpg)  
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
* [⚖️🤖 The Alignment Problem](../books/the-alignment-problem.md) by Brian Christian: Addresses the critical question of how to ensure machine learning systems ⚖️ align with human values.  
* Build a Large Language Model (From Scratch) by Sebastian Raschka: A hands-on guide for those who want to 🛠️ build a large language model from the ground up.  
* AI Superpowers: China, Silicon Valley, and the New World Order by Kai-Fu Lee: Offers a broader geopolitical 🌎 perspective on the global competition in artificial intelligence.  
* Multi-Agent Reinforcement Learning: Foundations and Modern Approaches by Stefano V. Albrecht, Filippos Christianos, and Lukas Schäfer: Dives into how multiple intelligent agents can 🤝 interact and learn in shared environments.  
  
## 🐦 Tweet  
<blockquote class="twitter-tweet" data-theme="dark"><p lang="en" dir="ltr">🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model<br><br>🧠 Reasoning | 🗺️ Planning | 🤖 Language Models | 📈 Performance | 💡 Framework | 🤖 World Model | 🗄️ Arxiv<a href="https://t.co/o2QQgTuDxO">https://t.co/o2QQgTuDxO</a></p>&mdash; Bryan Grounds (@bagrounds) <a href="https://twitter.com/bagrounds/status/1951088746855801047?ref_src=twsrc%5Etfw">August 1, 2025</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116598248311479079/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116598248311479079" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mm6brg4wda2t" data-bluesky-cid="bafyreibdealfwkxsc4ub3pbxzasxdmjwn65mxibnmincpte3xcbmqszx2a"><p>🗣️🗺️🤖⚙️ Reasoning with Language Model is Planning with World Model  
  
#AI Q: 🤖 Should AI be more like a human planner or a fast pattern matcher?  
  
🌳 Search Algorithms | 🧠 System 2 Thinking | 🎯 Decision Making  
https://bagrounds.org/articles/reasoning-with-language-model-is-planning-with-world-model</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mm6brg4wda2t?ref_src=embed">2026-05-19T01:52:32.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>