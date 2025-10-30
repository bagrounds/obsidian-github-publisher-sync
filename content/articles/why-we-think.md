---
share: true
aliases:
  - 🤔💭🤔💭 Why We Think
title: 🤔💭🤔💭 Why We Think
URL: https://bagrounds.org/articles/why-we-think
Author:
tags:
---
[Home](../index.md) > [Articles](./index.md)  
# [🤔💭🤔💭 Why We Think](https://lilianweng.github.io/posts/2025-05-01-thinking)  
## 🤖 AI Summary  
* 🧠 Enabling models to think longer mirrors the human dual process theory: 💨 fast (System 1) versus 🐌 slow (System 2) thinking.  
* 💻 Architectures that use more test-time computation and are trained to utilize it will perform better.  
* 💡 Chain-of-Thought (CoT) significantly increases the effective computation (flops) performed per answer token.  
* 📈 CoT allows the model to use a variable amount of compute depending on the hardness of the problem.  
* 🧩 Probabilistic models benefit from defining a latent variable $z$ to represent the free-form thought process and a visible variable $y$ as the answer.  
* 💪 Reinforcement learning on problems with automatically checkable solutions (like STEM or coding) significantly improves CoT reasoning capabilities.  
* ✂️ Test-time compute adaptively modifies the model’s output distribution through two main methods: branching and editing.  
* ✨ Parallel sampling generates multiple outputs simultaneously and uses guidance, such as 🗳️ majority vote with self-consistency, to select the best answer.  
* 📝 Sequential revision iteratively adapts responses by asking the model to reflect on and correct mistakes from the previous step.  
* 🛠️ External tool use, like code execution or Web search in ReAct, enhances reasoning by incorporating external knowledge or performing symbolic tasks.  
* 👁️ CoT provides a convenient form of interpretability by making the model's internal process visible in natural language.  
* 🛡️ Monitoring CoT can effectively detect model misbehavior, such as reward hacking, and improve adversarial robustness.  
* 🚫 CoT faithfulness is not guaranteed, as models may produce a conclusion prematurely (Early answering) before the CoT is generated.  
* 🌟 Self-taught reasoner (STaR) fixes failed attempts by generating good rationales backward, conditioned on the ground truth, to accelerate learning.  
  
## 🤔 Evaluation  
* 📢 The article presents CoT as a convenient path toward model interpretability.  
* ❌ Critically, this foundational assumption is strongly challenged by external research from highly reliable sources.  
* 📖 A paper titled Chain-of-Thought Is Not Explainability, published by the Oxford Martin AI Governance Initiative, argues that CoT rationales are frequently unfaithful and may not reflect the model's true hidden computations.  
* 🤥 CoT can create an illusion of transparency, providing a plausible but ultimately untrustworthy explanation that diverges from the internal decision process.  
* 🏥 This lack of faithfulness poses a severe risk in high-stakes domains like clinical text analysis, as noted in the arXiv paper Why Chain of Thought Fails in Clinical Text Understanding.  
* 🧠 **Topics for Further Exploration:**  
    * 🪟 Developing rigorous, verifiable methods to ensure CoT explanations genuinely reflect the model’s underlying computation, moving beyond surface-level narratives.  
    * ⚖️ Investigating the long-term trade-offs and scaling laws between allocating more resources to inference-time thinking versus increasing core model size or pretraining data.  
    * 🔬 Gaining a mechanistic understanding of how CoT arises within transformer architectures.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 🧑‍🏫 Q: What is the dual process theory analogy for AI thinking?  
🐌 A: The analogy compares 💨 System 1 (fast, intuitive) and 🐌 System 2 (slow, deliberate) human thinking to how AI models can benefit from spending more computation time, or thinking time, on complex problems before generating a final answer.  
  
### ❓ Q: How does Chain-of-Thought (CoT) increase a model's computational resources at inference time?  
💻 A: CoT increases computational resources by compelling the language model to generate intermediate, step-by-step reasoning tokens before the final answer, effectively performing far more processing (flops) for each output token.  
  
### 💬 Q: What is the difference between parallel sampling and sequential revision for LLMs?  
🔄 A: Parallel sampling involves generating multiple potential answers simultaneously and selecting the best one, often using a majority vote or verifier. Sequential revision is an iterative process where the model is asked to intentionally reflect on and correct a previous response to improve its quality over time.  
  
### ⚠️ Q: Why is the faithfulness of a Chain-of-Thought explanation a critical concern?  
🔓 A: The faithfulness of CoT is a concern because the generated reasoning steps may be plausible but fail to truthfully reflect the model's actual internal computation or decision-making process, creating an ❌ illusion of transparency and a risk of misplaced trust.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
* [🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md) by Daniel Kahneman: It explains the dual process theory of System 1 and System 2 thinking, which the article directly uses as a psychological analogy for model reasoning.  
* [❓➡️💡 The Book of Why: The New Science of Cause and Effect](../books/the-book-of-why.md) by Judea Pearl and Dana Mackenzie: This book focuses on the importance of causal inference and formal reasoning, the ultimate goal of improving LLM thinking and problem-solving capabilities.  
  
### 🆚 Contrasting  
* [♾️📐🎶🥨 Gödel, Escher, Bach: An Eternal Golden Braid](../books/godel-escher-bach.md) by Douglas Hofstadter: This work explores intelligence, formal systems, and self-reference from a more symbolic and philosophical perspective, contrasting with the purely statistical approach of current large language models.  
* 🤖 The Second Self: Computers and the Human Spirit by Sherry Turkle: It offers a sociological and psychological contrast, exploring how human identity and modes of thought are reflected in and contrasted with computational thinking.  
  
### 🎨 Creatively Related  
* [🤔💻🧠 Algorithms to Live By: The Computer Science of Human Decisions](../books/algorithms-to-live-by.md) by Brian Christian and Tom Griffiths: This connects computational problem-solving principles, like optimal stopping and caching, to human decision-making and practical thought processes.  
* [🔬🔄 The Structure of Scientific Revolutions](../books/the-structure-of-scientific-revolutions.md) by Thomas S. Kuhn: It discusses how intellectual frameworks (paradigms) fundamentally shift, creatively relating to how new techniques like CoT or tool use fundamentally change the capabilities and research approaches in AI.