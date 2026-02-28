---
share: true
aliases:
  - 🤖⚙️🧠 Writing about Agentic Engineering Patterns
title: 🤖⚙️🧠 Writing about Agentic Engineering Patterns
URL: https://bagrounds.org/articles/writing-about-agentic-engineering-patterns
Author:
tags:
---
[Home](../index.md) > [Articles](./index.md)  
# [🤖⚙️🧠 Writing about Agentic Engineering Patterns](https://simonwillison.net/2026/Feb/23/agentic-engineering-patterns)  
## 🤖 AI Summary  
  
* 🛠️ Agentic engineering involves using coding agents like Claude Code and OpenAI Codex that generate, execute, and test code independently.  
* 📉 The cost of producing initial code has dropped to nearly zero, disrupting traditional intuitions about development trade-offs and planning.  
* 🏗️ Professional software engineers must shift from manual implementation to acting as architects and reviewers who ensure code quality.  
* 🧪 Automated testing is the primary differentiator between disciplined agentic engineering and unreliable vibe coding.  
* 🔴 Red/green Test Driven Development allows agents to iterate in a loop until tests pass, turning unreliable models into reliable systems.  
* 🚶 Linear walkthroughs of code remain essential for human supervisors to maintain deep understanding and ownership of the codebase.  
* 🐿️ Engineers should hoard knowledge of how to perform tasks manually to effectively direct and audit the work of autonomous agents.  
* 🏗️ Long-term maintainability, accessibility, and security remain human responsibilities that agents cannot yet fully guarantee without oversight.  
  
## 🤔 Evaluation  
  
* ⚖️ Simon Willison emphasizes a practitioner-led, bottom-up approach to agentic patterns focusing on individual developer habits and TDD.  
* 🔍 In contrast, CodeScene in Agentic AI Coding: Best Practice Patterns for Speed with Quality emphasizes organizational safeguards and objective code health metrics to prevent technical debt accumulation.  
* 🏗️ MachineLearningMastery.com in 7 Must-Know Agentic AI Design Patterns focuses on structural architectural patterns like ReAct and Reflection which are more granular than Willison's workflow-centric view.  
* 📈 While Willison focuses on the efficiency of the individual engineer, Addy Osmani in Agentic Engineering notes that these practices disproportionately benefit senior engineers who possess the deep architectural fundamentals required for effective review.  
* 💡 Areas for further exploration include the impact of non-deterministic agent behavior on traditional CI/CD pipelines and the evolving role of the human-in-the-loop for security-critical applications.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 💻 Q: What is the difference between agentic engineering and vibe coding?  
  
🤖 A: Agentic engineering applies professional discipline, testing, and architectural oversight to AI-generated code, whereas vibe coding refers to a more casual, non-technical approach that lacks rigorous validation.  
  
### 🧪 Q: Why is Test Driven Development critical for AI agents?  
  
🤖 A: TDD provides a deterministic feedback loop that allows an agent to self-correct by iterating on its code until it passes a predefined suite of requirements.  
  
### 📉 Q: How does the falling cost of code impact software project planning?  
  
🤖 A: When code is nearly free to produce, teams can shift from heavy upfront estimation to rapid prototyping and asynchronous exploration of multiple implementation paths simultaneously.  
  
### 🧠 Q: Does agentic engineering reduce the need for senior software developers?  
  
🤖 A: Senior expertise becomes more valuable because the role shifts from typing code to making high-level architectural decisions and performing rigorous quality audits on agent outputs.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
  
- [🤖🏗️ AI Engineering: Building Applications with Foundation Models](../books/ai-engineering-building-applications-with-foundation-models.md)  
- [🤖⚙️ The Agentic AI Engineer's Handbook](../books/the-agentic-ai-engineers-handbook.md) by Elvis Albright provides a practical guide to building production-scale agentic systems using workflow architectures.  
* [🤖🧠⚙️💡 Building Agentic AI Systems: Create intelligent, autonomous AI agents that can reason, plan, and adapt](../books/building-agentic-ai-systems-create-intelligent-autonomous-ai-agents-that-can-reason-plan-and-adapt.md) by Anjanava Biswas and Wrick Talukdar explores the core principles of designing autonomous agents that can plan and reason.  
  
### 🆚 Contrasting  
  
* 🛑 Designing Autonomous AI Systems by Gunjan Vi focuses on the necessary constraints and safety boundaries required to prevent agents from acting unpredictably.  
* 🛡️ The Agentic AI Book by Dr. Ryan Rad critiques the current hype and explores the common failure modes of multi-agent systems in production.  
  
### 🎨 Creatively Related  
  
* 🏗️ Design Patterns: Elements of Reusable Object-Oriented Software by Erich Gamma and others serves as the original inspiration for documenting repeatable software engineering solutions.  
* [🦢 The Elements of Style](../books/the-elements-of-style.md) by William Strunk Jr. and E.B. White provides the foundation for the concise and economical communication style required for managing complex systems.