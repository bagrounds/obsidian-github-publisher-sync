---
share: true
aliases:
  - 🤖⚙️🛠️ Agentic Engineering Patterns
title: 🤖⚙️🛠️ Agentic Engineering Patterns
URL: https://bagrounds.org/articles/agentic-engineering-patterns
Author:
tags:
---
[Home](../index.md) > [Articles](./index.md)  
# [🤖⚙️🛠️ Agentic Engineering Patterns](https://simonwillison.net/guides/agentic-engineering-patterns)  
## 🤖 AI Summary  
  
* ⚡ Writing code is cheap now because the cost to generate initial working implementations has dropped to near zero.  
* 🏗️ Professional expertise must shift from implementation to design, stewardship, and the judgment of clear abstractions.  
* 🧪 Automated tests are no longer optional since agents can generate and update them in minutes to ensure correctness.  
* 📉 Cognitive debt accumulates when we lose track of how agent-written code works, turning applications into black boxes.  
* 📺 Linear walkthroughs help pay down this debt by having agents provide structured, step-by-step explanations of a codebase.  
* 🎨 Interactive explanations use animations and visual demos to make complex agent-generated algorithms click for the human supervisor.  
* 📦 Hoard solutions you know how to do by collecting small proof-of-concepts and HTML tools to expand your personal library of verified code.  
* 🚫 Avoid the anti-pattern of inflicting unreviewed agent code on collaborators via lazy pull requests.  
* 🔄 Red/green TDD remains the gold standard for agentic workflows to verify that the agent actually solved the intended problem.  
  
## 🤔 Evaluation  
  
* ⚖️ Simon Willison emphasizes the empowerment of the individual through agentic engineering, while sources like The AI Engineer Council's 2024 State of AI Engineering report highlight the organizational risks of security and massive technical debt in enterprise settings.  
* 🔍 Willison’s focus on single-file HTML tools contrasts with the microservices and containerization trends discussed in O'Reilly's Software Architecture patterns, which prioritize scalability over the simplicity and portability Willison favors.  
* 🌐 Exploring the intersection of agentic workflows and Formal Verification could provide a more robust framework for ensuring safety in critical systems beyond standard automated testing.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 🤖 Q: What is the core definition of agentic engineering?  
  
🤖 A: Agentic engineering is the practice of building software using coding agents that can both generate and execute code to independently test and iterate on their work.  
  
### 💰 Q: How does the falling cost of writing code change software development?  
  
💰 A: When implementation becomes cheap, the primary value of a developer shifts toward high-level system design, architectural judgment, and the rigorous stewardship of code quality.  
  
### 🧠 Q: What is cognitive debt in the context of AI-assisted programming?  
  
🧠 A: Cognitive debt is the loss of understanding that occurs when a developer relies on an agent to write code without fully comprehending the underlying implementation details.  
  
### 🧪 Q: Why are automated tests considered mandatory for agentic workflows?  
  
🧪 A: Automated tests provide the necessary feedback loop for an agent to prove its code works, replacing the human's need to manually verify every line of generated logic.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
  
* [🧑‍💻📈 The Pragmatic Programmer: Your Journey to Mastery](../books/the-pragmatic-programmer-your-journey-to-mastery.md) by Andrew Hunt and David Thomas explores the mindset of continuous learning and automation that aligns with hoarding verified code solutions.  
* [🧼💾 Clean Code: A Handbook of Agile Software Craftsmanship](../books/clean-code.md) by Robert C. Martin provides the foundational principles for the clear abstractions and stewardship that Willison argues are now more important than ever.  
  
### 🆚 Contrasting  
  
* 📙 A Philosophy of Software Design by John Ousterhout argues that complexity is the greatest enemy of software, offering a more cautious perspective on the rapid code generation Willison describes.  
* [🦄👤🗓️ The Mythical Man-Month: Essays on Software Engineering](../books/the-mythical-man-month.md) by Frederick Brooks examines the inherent difficulties of software engineering management that AI speed alone may not be able to solve.  
  
### 🎨 Creatively Related  
  
* 🎨 Design Patterns by Erich Gamma et al. serves as the original inspiration for Willison's pattern-based approach to documenting new engineering behaviors.  
* [🌐🔗🧠📖 Thinking in Systems: A Primer](../books/thinking-in-systems.md) by Donella Meadows offers a framework for understanding the complex feedback loops and emergent behaviors found in autonomous agent systems.