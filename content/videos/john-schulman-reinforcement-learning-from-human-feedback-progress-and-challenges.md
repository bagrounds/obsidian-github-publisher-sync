---
share: true
aliases:
  - "🤖🧑‍💻📈🚧 John Schulman - Reinforcement Learning from Human Feedback: Progress and Challenges"
title: "🤖🧑‍💻📈🚧 John Schulman - Reinforcement Learning from Human Feedback: Progress and Challenges"
URL: https://bagrounds.org/videos/john-schulman-reinforcement-learning-from-human-feedback-progress-and-challenges
Author: 
Platform: 
Channel: UC Berkeley EECS
tags: 
youtube: https://www.youtube.com/embed/hhiLw5Q_UFg
---
[Home](../index.md) > [Videos](./index.md)  
# 🤖🧑‍💻📈🚧 John Schulman - Reinforcement Learning from Human Feedback: Progress and Challenges  
![John Schulman - Reinforcement Learning from Human Feedback: Progress and Challenges](https://www.youtube.com/embed/hhiLw5Q_UFg)  
  
## 🤖 AI Summary  
* **Introduction to John Schulman** 🗣️ Peter Abbeel introduces John Schulman, a Berkeley graduate, co-founder of OpenAI, and Chief Architect of ChatGPT, highlighting his contributions to deep learning-based policy gradient algorithms \[[00:21](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=21)\].  
* **Truthfulness in Language Models** 🧠 Schulman focuses on the technical problem of truthfulness in language models, explaining why "hallucination" occurs and how to address it \[[02:56](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=176)\]. He provides 📝 examples of ChatGPT's responses to demonstrate different levels of factual accuracy \[[03:45](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=225)\].  
* **Why Hallucination Happens** 💡 He presents a conceptual model where neural networks store information like a knowledge graph and explains that small-scale fine-tuning learns a program to output probabilities based on this graph \[[08:38](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=518)\]. He argues that behavior cloning (supervised fine-tuning) can lead to hallucination because the model is trained on correct answers it doesn't inherently know, or it might withhold information it does know \[[11:30](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=690)\].  
* **Reinforcement Learning (RL) as a Solution** 🛠️ Schulman proposes that RL can help fix the hallucination problem by teaching the model when to express uncertainty or say "I don't know" \[[18:48](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=1128)\]. He discusses an 🧪 experiment using RL in a trivia question-answering setting to learn optimal thresholding behavior for answering or refusing to answer questions \[[21:18](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=1278)\].  
* **Factuality in Long-Form Answers** ✍️ He addresses the challenge of factuality in long-form answers, where information can be a mix of right, wrong, and misleading \[[25:30](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=1530)\]. He mentions that RL from Human Feedback (RLHF) improves factuality, citing evaluations from the GPT-4 blog post \[[28:56](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=1736)\].  
* **Retrieval and Citing Sources** 🌐 Schulman discusses the importance of retrieval-based methods, where language models access external knowledge sources, for current events, private information, and especially for verifiability \[[32:26](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=1946)\]. He introduces WebGPT, a project that predated ChatGPT, which focused on answering questions by researching online and citing sources \[[34:39](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=2079)\].  
* **WebGPT System and RLHF Pipeline** ⚙️ He explains how WebGPT works, detailing the model's actions (search, click, quote) within a defined DSL (Domain Specific Language) and the RL environment used for training \[[36:44](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=2204)\]. He also outlines the RLHF pipeline, which involves behavior cloning, collecting human comparisons for reward modeling, and then using RL or search \[[38:50](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=2330)\].  
* **Browse in ChatGPT** 💻 Schulman demonstrates the Browse feature in ChatGPT, which uses similar methods to WebGPT, including an inner monologue for the AI's thought process \[[42:12](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=2532)\]. He highlights that ChatGPT only browses when it doesn't know the answer, leveraging its self-knowledge of uncertainty \[[44:01](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=2641)\].  
* **Open Problems**  
    * Incentivizing 🎯 models to accurately express uncertainty and use appropriate hedging \[[50:40](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=3040)\].  
    * Scalable 🔍 oversight to train models for tasks that are too difficult for human labelers to perform directly \[[48:38](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=2918)\].  
    * Optimizing for actual 💯 truth rather than just human approval, potentially through predicting the future or deduction \[[51:42](http://www.youtube.com/watch?v=hhiLw5Q_UFg&t=3102)\].  
  
## 🤔 Evaluation  
This 🗣️ seminar provides a deep dive into the technical challenges of achieving truthfulness in language models, particularly the issue of "hallucination." Schulman's 💡 explanation of hallucination as a consequence of behavior cloning, where models are trained on answers they don't inherently "know," offers a compelling perspective. The 🚀 proposed solution of using Reinforcement Learning (RL) to teach models when to express uncertainty or refuse to answer is a significant conceptual shift from simply trying to make models "know" more. The 🧪 WebGPT project and the Browse feature in ChatGPT demonstrate practical applications of these ideas, emphasizing the importance of retrieval-based methods and citing sources for verifiability.  
  
To further understand these concepts, it would be beneficial to explore alternative approaches to mitigating hallucination in large language models that do not rely on RLHF. Additionally, investigating the ethical implications of training models to express uncertainty, particularly in high-stakes applications, could provide a more comprehensive understanding. Finally, delving into the specifics of "scalable oversight" and methods for optimizing for "actual truth" beyond human approval would be crucial for future advancements in this field.  
  
## 📚 Book Recommendations  
* [🤖➕🧠➡️ Reinforcement Learning: An Introduction](../books/reinforcement-learning-an-introduction.md) by Richard S. Sutton and Andrew G. Barto: A foundational text for understanding the principles of reinforcement learning.  
* [🧠💻🤖 Deep Learning](../books/deep-learning.md) by Ian Goodfellow, Yoshua Bengio, and Aaron Courville: Provides a comprehensive overview of deep learning, including neural networks and their applications.  
* The Master Algorithm by Pedro Domingos: Explores various machine learning paradigms and how they contribute to a universal learning algorithm.  
* [🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md) by Daniel Kahneman: While not directly about AI, this book on human cognition offers insights into biases and decision-making that can be relevant to understanding how AI models might "think" or "reason."  
* [🤖⚠️📈 Superintelligence: Paths, Dangers, Strategies](../books/superintelligence-paths-dangers-strategies.md) by Nick Bostrom: Discusses the potential future of AI, including challenges related to control and alignment, which touches upon the "optimizing for actual truth" problem.