---
share: true
aliases:
  - "Parables on the Power of Planning in AI: From Poker to Diplomacy: Noam Brown (OpenAI)"
title: "Parables on the Power of Planning in AI: From Poker to Diplomacy: Noam Brown (OpenAI)"
URL: https://youtu.be/eaAonE58sLU
Author: 
Platform: "#YouTube"
Channel: "[[Paul G. Allen School]]"
tags: 
---
[Home](../index.md) > [Videos](./index.md)  
# Parables on the Power of Planning in AI: From Poker to Diplomacy: Noam Brown (OpenAI)  
![Parables on the Power of Planning in AI: From Poker to Diplomacy: Noam Brown (OpenAI)](https://youtu.be/eaAonE58sLU)  
  
## Notes  
- planning significantly improves machine learning system performance  
- planning in machine learning systems can be implemented via e.g. Monte Carlo search  
- planning is useful in domains with a large generator-verifier gap  
- the generator-verifier refers to problems where it's much easier to verify a solution than it is to generate one  
  
## AI Summary  
**Scaling AI Through Search and Planning: Lessons from Game AI Research**    
  
### **Introduction**    
Noam Brown, a leading AI researcher at OpenAI, presents insights from his work on game-playing AI, particularly in **poker and strategy games like Diplomacy**. His talk explores the **power of search and planning** in AI, demonstrating that **increasing inference compute**—rather than just scaling model size—can lead to **dramatic improvements in performance**.    
  
This blog post distills Brown’s key findings and discusses **how they apply beyond games**, particularly in **large language models (LLMs) and real-world AI systems**.    
  
---  
  
### **AI in Poker: From Claudico to Pluribus**    
#### **Initial Challenges (2012-2015)**    
- Early poker AI was based on **precomputed strategies**, without real-time adaptation.    
- The **2015 Brains vs. AI match** saw AI *Claudico* **lose** to human professionals, revealing flaws in its approach.    
  
#### **Breakthrough with Search and Planning (2017-2019)**    
- Brown’s team introduced **real-time search and strategic planning**, improving decision-making.    
- Their **2017 AI system** became the **first to defeat human poker pros**.    
- *Pluribus* (2019) achieved **superhuman performance in 6-player poker**, running on **just 28 CPUs with a $150 training cost**.    
  
#### **Key Lesson:**    
**Strategic search massively outperforms naive scaling**—a **100,000x larger model** would be needed to match the gains achieved by introducing search.    
  
**Further Reading:**    
- *[Libratus: The AI that Beat Humans in Heads-Up No-Limit Poker (CMU)](https://www.cs.cmu.edu/news/2017/libratus-first-ai-beat-top-humans-poker)*    
- *[Pluribus: Superhuman AI for Multiplayer Poker (Science)](https://www.science.org/doi/10.1126/science.aay2400)*    
  
---  
  
### **AI in Diplomacy: Cicero and Language-Based Strategy**    
Diplomacy, unlike poker, requires **natural language negotiation**. Brown’s team built **Cicero**, an AI that played at a **top human level**, using:    
  
1. **Dialogue-Conditional Action Models** – Predicting **not only moves but also negotiation strategies**.    
2. **Iterative Search** – Refining plans by simulating **what other players might believe and do**.    
3. **Language Model + Planning** – Instead of instantly responding like ChatGPT, Cicero **strategically planned each message** (often taking 10+ seconds per response).    
  
#### **Key Lesson:**    
**AI communication and planning can be tightly integrated** to create agents that **reason, negotiate, and adapt dynamically**.    
  
**Further Reading:**    
- *[Cicero: AI That Masters Diplomacy (Meta)](https://ai.meta.com/blog/cicero-ai-that-masters-diplomacy/)*    
- *[Diplomacy Game Theory (CS Research Paper)](https://arxiv.org/abs/2210.01780)*    
  
---  
  
### **Why Planning Works: The Generator-Verifier Gap**    
Brown introduces the **Generator-Verifier Gap**, where:    
- **Some problems are easier to verify than generate.**    
- Example: **Chess** → Recognizing a winning board state is easy; **finding the path to it is hard**.    
- AI should **search multiple solutions, then verify which is best**—instead of relying on a single direct output.    
  
This principle applies to:    
- **Math & Programming** → Checking correctness is easier than solving from scratch.    
- **Proof Generation** → Verifying a proof is far easier than discovering it.    
  
#### **Key Lesson:**    
Search-based AI **leverages the verifier gap** to find **optimal solutions in complex domains**.    
  
**Further Reading:**    
- *[The Generator-Verifier Framework (AI Alignment)](https://www.alignmentforum.org/posts/3hv2c9wdEyNhbEnjN/the-generator-verifier-framework-for-ai)*    
  
---  
  
### **Scaling Compute: Consensus, Best-of-N, and Process Reward Models**    
Brown discusses techniques for **scaling inference compute**, particularly in **LLMs and mathematical reasoning**:    
  
#### **1. Consensus Sampling**    
- AI generates **multiple solutions** and selects the most common.    
- Used in **Google’s Minerva**, improving math accuracy from **33.6% to 50.3%**.    
  
#### **2. Best-of-N Selection**    
- AI generates **N solutions** and picks the best **using a reward model**.    
- Works well in structured domains like **chess and Sudoku**, but struggles when **reward models are weak**.    
  
#### **3. Process Reward Models (Step-by-Step Verification)**    
- Instead of verifying only the final answer, AI **evaluates each intermediate step**.    
- **Boosted math accuracy to 78.2%**, surpassing all previous techniques.    
  
#### **Key Lesson:**    
Future AI will **scale inference compute dynamically**, balancing **speed and correctness for different tasks**.    
  
**Further Reading:**    
- *[Minerva: Solving Math with LLMs (Google Research)](https://arxiv.org/abs/2206.14858)*    
- *[Scaling Laws for Reward Models (DeepMind)](https://arxiv.org/abs/2302.06645)*    
  
---  
  
### **Future of AI: Rethinking Inference vs. Training Costs**    
Brown argues that:    
4. **Current AI is biased toward low-cost inference** (ChatGPT generates instant responses).    
5. **Some tasks justify high inference compute** (e.g., theorem proving, drug discovery).    
6. **General methods for scaling inference are still an open research challenge**.    
  
#### **Practical Implications**    
- **LLMs should incorporate search and planning** (beyond simple token prediction).    
- **Academia should explore high-compute inference strategies**, as industry favors **low-cost, high-speed AI**.    
  
**Further Reading:**    
- *[The Bitter Lesson (Rich Sutton)](http://www.incompleteideas.net/IncIdeas/BitterLesson.html)*    
  
---  
  
### **Conclusion: The Future is Search + Learning**    
Brown concludes with a reminder that **AI progress has always been driven by two scalable methods**:    
- **Deep Learning (Learning from data)**    
- **Search & Planning (Efficient inference computation)**    
  
While deep learning has seen explosive growth, **search-based methods remain underutilized**. Future AI will likely **combine both approaches** to unlock **new capabilities in reasoning, problem-solving, and decision-making**.    
  
---  
  
### **Final Takeaways**    
✅ **Scaling inference compute is as important as scaling training compute**.    
✅ **Search & planning improve AI performance across many domains**.    
✅ **Future AI should balance speed vs. accuracy dynamically**.    
