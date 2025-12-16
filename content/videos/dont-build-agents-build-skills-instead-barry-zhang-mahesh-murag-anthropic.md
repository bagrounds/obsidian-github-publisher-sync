---
share: true
aliases:
  - 🧠🛠️➡️🤖 Don't Build Agents, Build Skills Instead – Barry Zhang & Mahesh Murag, Anthropic
title: 🧠🛠️➡️🤖 Don't Build Agents, Build Skills Instead – Barry Zhang & Mahesh Murag, Anthropic
URL: https://bagrounds.org/videos/dont-build-agents-build-skills-instead-barry-zhang-mahesh-murag-anthropic
Author:
Platform:
Channel: AI Engineer
tags:
youtube: https://youtu.be/CEvIs9y1uog
---
[Home](../index.md) > [Videos](./index.md)  
# 🧠🛠️➡️🤖 Don't Build Agents, Build Skills Instead – Barry Zhang & Mahesh Murag, Anthropic  
![Don't Build Agents, Build Skills Instead – Barry Zhang & Mahesh Murag, Anthropic](https://youtu.be/CEvIs9y1uog)  
  
## 🤖 AI Summary  
* 🏗️ Shift focus from building standalone agents to developing modular skills. \[[00:47](http://www.youtube.com/watch?v=CEvIs9y1uog&t=47)]  
* 💻 Use code as the universal interface between models and digital environments. \[[01:38](http://www.youtube.com/watch?v=CEvIs9y1uog&t=98)]  
* 📂 Define skills as simple folders containing procedural knowledge and scripts. \[[03:04](http://www.youtube.com/watch?v=CEvIs9y1uog&t=184)]  
* 🛠️ Employ bash and file systems as thin, scalable scaffolding for agents. \[[02:03](http://www.youtube.com/watch?v=CEvIs9y1uog&t=123)]  
* 🧠 Solve the expertise gap by packaging domain-specific instructions into skills. \[[02:17](http://www.youtube.com/watch?v=CEvIs9y1uog&t=137)]  
* 🛡️ Protect context windows by using progressive disclosure of skill metadata. \[[04:34](http://www.youtube.com/watch?v=CEvIs9y1uog&t=274)]  
* 🤝 Use Model Context Protocol servers for connectivity and skills for expertise. \[[08:14](http://www.youtube.com/watch?v=CEvIs9y1uog&t=494)]  
* 📈 Enable continuous learning by allowing agents to create and save their own skills. \[[13:27](http://www.youtube.com/watch?v=CEvIs9y1uog&t=807)]  
* 🏦 Deploy specialized vertical offerings quickly using libraries of relevant skills. \[[10:09](http://www.youtube.com/watch?v=CEvIs9y1uog&t=609)]  
* 🖥️ View the agent runtime as an operating system orchestrating model potential. \[[14:50](http://www.youtube.com/watch?v=CEvIs9y1uog&t=890)]  
  
## 🤔 Evaluation  
🏛️ Anthropic engineers argue for a skill-centric architecture, emphasizing modularity and local file systems. 🏢 In contrast, Microsoft Research’s AutoGen framework often highlights multi-agent orchestration where different agents play specialized roles, as detailed in the paper Autogen: Enabling Next-gen Llma Applications via Multi-agent Conversation Framework by Microsoft Corporation. 🌐 While the video promotes simple folders, others explore vector databases for long-term memory. 🔍 Future research should investigate how these local skills handle massive, conflicting datasets compared to centralized knowledge graphs.  
  
## ❓ Frequently Asked Questions (FAQ)  
### 🎒 Q: What exactly is an agent skill?  
📂 A: A skill is a folder containing markdown instructions and scripts that give agents procedural expertise. \[[03:04](http://www.youtube.com/watch?v=CEvIs9y1uog&t=184)]  
  
### 🔗 Q: How do agent skills differ from Model Context Protocol servers?  
🔌 A: MCP provides the connection to external data, while skills provide the specific expertise to use it. \[[08:14](http://www.youtube.com/watch?v=CEvIs9y1uog&t=494)]  
  
### ⏳ Q: Can agents learn and improve over time using agent skills?  
🧬 A: Yes, agents can write and save new scripts into their skill folders to reuse later. \[[04:14](http://www.youtube.com/watch?v=CEvIs9y1uog&t=254)]  
  
### 💼 Q: Are agent skills only useful for software engineers?  
⚖️ A: No, non-technical professionals in finance, legal, and HR can create skills using simple text. \[[08:42](http://www.youtube.com/watch?v=CEvIs9y1uog&t=522)]  
  
## 📚 Book Recommendations  
### ↔️ Similar  
* 🧩 Building Intelligent Systems by Geoff Hulten. 🛠️ Covers the practical engineering required to make machine learning systems functional in real-world environments.  
* 🤖 Designing Autonomous Agents by Pattie Maes. 🎓 Explores the foundational concepts of how agents interact with their surroundings and execute tasks.  
  
### 🆚 Contrasting  
* 🤝 Multi-Agent Systems by Gerhard Weiss. 🏗️ Focuses on the complex coordination between many distinct agents rather than a single general agent with modular skills.  
* 🕸️ Linked by Albert-László Barabási. 🌐 Discusses the power of networks and connectivity, offering a perspective on distributed intelligence versus local file-based skills.  
  
### 🎨 Creatively Related  
* [🦢 The Elements of Style](../books/the-elements-of-style.md) by William Strunk Jr. and E.B. White. ✍️ Relevant because the speakers emphasize brevity and clarity in instructions to ensure agent reliability.  
* [🧑‍💻📈 The Pragmatic Programmer: Your Journey to Mastery](../books/the-pragmatic-programmer-your-journey-to-mastery.md) by Andrew Hunt and David Thomas. 💻 Provides timeless advice on modularity, automation, and treating knowledge as a version-controlled asset.