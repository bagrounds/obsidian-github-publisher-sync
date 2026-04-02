---
share: true
aliases:
  - 🙋💻❓ How I use LLMs
title: 🙋💻❓ How I use LLMs
URL: https://youtu.be/EWvNQjAaOHw
Author:
Platform:
Channel: Andrej Karpathy
tags:
---
[Home](../index.md) > [Videos](./index.md) | [🤖🧠💻 Andrej Karpathy](../people/andrej-karpathy.md)  
# 🙋💻❓ How I use LLMs  
![How I use LLMs](https://youtu.be/EWvNQjAaOHw)  
  
## 🤖 AI Summary  
* **ChatGPT** 🥇, deployed in 2022, is the Original Gangster incumbent, being the most popular and feature-rich model \[[01:13](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=73)].  
* The LLM **ecosystem** 🌳 is rich, featuring big Tech offerings like Google's Gemini, Meta, and Microsoft's Copilot, alongside startups like Anthropic's Claude and xAI's Grok \[[01:30](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=90)].  
* **Model leaderboards** 📊, such as Chatbot Arena and the Seal Leaderboard, can be used to track model strengths and current performance across a variety of tasks \[[02:08](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=128)].  
* The basic interaction involves giving the model a **text prompt** ✍️ and receiving text back, which is effective for creative tasks like generating haikus \[[02:53](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=173)].  
* The chat window functions as the model's **working memory** 🧠, and a buildup of tokens in the window can become distracting, decrease accuracy, and is expensive \[[16:45](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=1005)].  
* Always **start a new thread** 💡 when previous context is no longer useful to prevent distraction and mitigate token cost issues \[[16:45](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=1005)].  
* A **larger model** 🐘 has superior World Knowledge, answers complex questions, provides better writing, and is more creative \[[02:08:05](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=7685)].  
* The latest frontier is **reinforcement learning** 📈 to improve accuracy in problems involving math, code, and reasoning \[[02:08:32](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=7712)].  
* Models are rapidly gaining **tools** 🛠️ such as internet search for fresh knowledge and a Python interpreter for generating figures or plots (Advanced Data Analysis) \[[02:08:58](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=7738)].  
* **Multimodality** 📸 is maturing, allowing models to handle text, audio, images, and video as native input and output (Omni models) \[[02:09:39](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=7779)].  
* **Quality of life** ✨ features like file uploads, memory, instructions, and GPTs enhance the overall user experience \[[02:10:18](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=7818)].  
* Pricing for flagship models like **GPT-4o** involves usage limits, such as 80 messages every 3 hours for the $20 per month Plus subscription \[[19:32](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=1172)].  
  
## 🤔 Evaluation  
* **The video** 🎥 offers an exceptionally practical and high-quality perspective on LLM use, drawing on the experience of a field leader.  
* **The speaker's** 🗣️ use of metaphors, like the LLM being a zip file of the internet and the chat history acting as working memory, is widely accepted and scientifically sound in the AI community.  
* **The claim** that reinforcement learning is a key frontier for improving reasoning, math, and code is supported by extensive research into techniques like Reinforcement Learning from Human Feedback (RLHF), as detailed in papers like **Training a Helpful and Harmless Assistant** (Anthropic, 2021).  
* **Overall** ✅, the video is highly reliable and provides an unbiased technical and practical overview of the current LLM landscape.  
  
### Topics to Explore for a Better Understanding  
* **The Nature of Hallucination** 👻: Explore why LLMs generate false but plausible-sounding information, which is a key limitation of the next-token prediction mechanism, even in larger models.  
* **Attention and Context Window Limits** 📏: Investigate the computational cost of the **attention mechanism**, the core concept introduced in the paper **Attention Is All You Need** (Google Brain, 2017), which explains why long chat histories are expensive and distracting.  
* **Model Persona Training** 🎭: Research the specific post-training processes, such as Supervised Fine-Tuning (SFT) and RLHF, that transform the internet-trained zip file into a conversational assistant with a defined persona \[[02:08:05](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=7685)].  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 🛑 Q: Why are the conversational limits of chatbots like GPT-4o restricted, even for paid users?  
💸 A: Conversational limits 🛑 are necessary because large language models, especially flagship models like GPT-4o, require a **substantial amount** of computational resources for each interaction. The models are inherently **expensive** 💰 to run due to their massive size and complexity, so capping messages helps manage server load, resource consumption, and cost.  
  
### 🧠 Q: How does the size of a Large Language Model affect its performance?  
📏 A: **Model size** 🧠 directly influences capability and performance. **Larger models** 🐘 typically contain more World Knowledge, effectively handle complex queries, produce higher-quality writing, and exhibit greater creativity. **Smaller models** 🤏 are prone to more errors, including generating false information, a behavior known as hallucination \[[02:08:05](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=7685)].  
  
### 🎨 Q: What is the significance of multimodality in modern large language models?  
🖼️ A: **Multimodality** 🎨 is a crucial feature signifying a model's capacity to process and generate information across various formats, including **text, audio, images, and video** \[[02:09:39](http://www.youtube.com/watch?v=EWvNQjAaOHw&t=7779)]. This capability evolves models past simple text conversations, allowing them to perceive and interact with the world in a more integrated, human-like way.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
- [🤖💻 Vibe Coding: Building Production-Grade Software With GenAI, Chat, Agents, and Beyond](../books/vibe-coding-building-production-grade-software-with-genai-chat-agents-and-beyond.md)  
* **[🧠💻🤖 Deep Learning](../books/deep-learning.md)** by Ian Goodfellow, Yoshua Bengio, and Aaron Courville: This serves as the definitive textbook on the fundamental concepts of deep learning, providing the theoretical foundation for how large language models are structured and trained.  
* **The Algorithmic Foundations of Reinforcement Learning** by Csaba Szepesvári: This work provides a rigorous and deep dive into the mathematical techniques behind reinforcement learning, the advanced training method mentioned for improving an LLM's reasoning and accuracy.  
  
### 🆚 Contrasting  
* **The Myth of Artificial Intelligence: Why Computers Can’t Think the Way We Do** by Erik J. Larson: This book offers an opposing viewpoint by challenging the claims of strong general AI, arguing that current machine learning is fundamentally limited to narrow tasks and differs from human intelligence.  
* **[🧠🧠🧠🧠 A Thousand Brains: A New Theory of Intelligence](../books/a-thousand-brains.md)** by Jeff Hawkins: This presents an alternative, biological theory of intelligence—the Thousand Brains Theory—which offers a distinct architectural model compared to the transformer-based mechanisms of modern LLMs.  
  
### 🎨 Creatively Related  
* **[🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md)** by Daniel Kahneman: This book explores human cognition's two systems (fast/intuitive and slow/deliberate), which can be analogized to an LLM's quick token-prediction versus its slower, deliberate Chain-of-Thought reasoning using its context window working memory.  
* **[📱🧠 The Shallows: What the Internet Is Doing to Our Brains](../books/the-shallows-what-the-internet-is-doing-to-our-brains.md)** by Nicholas Carr: This work examines how new information technologies, like the internet that forms the basis of the LLM's training data (the zip file), are changing human attention and knowledge consumption, providing a macro-cultural lens on the subject.