---
share: true
aliases:
  - 🤖💬📈🌍 Build a Real-Time AI Sales Agent - Sarah Chieng & Zhenwei Gao, Cerebras
title: 🤖💬📈🌍 Build a Real-Time AI Sales Agent - Sarah Chieng & Zhenwei Gao, Cerebras
URL: https://bagrounds.org/videos/build-a-real-time-ai-sales-agent-sarah-chieng-zhenwei-gao-cerebras
Author:
Platform:
Channel: AI Engineer
tags:
youtube: https://youtu.be/mwzk2rlwtZE
---
[Home](../index.md) > [Videos](./index.md)  
# 🤖💬📈🌍 Build a Real-Time AI Sales Agent - Sarah Chieng & Zhenwei Gao, Cerebras  
![Build a Real-Time AI Sales Agent - Sarah Chieng & Zhenwei Gao, Cerebras](https://youtu.be/mwzk2rlwtZE)  
  
## 🤖 AI Summary  
  
* 🚀 Cerebras hardware eliminates memory bandwidth bottlenecks by placing SRAM directly on each of its 900,000 cores \[[06:18](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=378)].  
* ⚡ Inference speeds reach 20x to 70x faster than traditional GPUs due to this wafer-scale integration \[[04:50](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=290)].  
* 🧠 Speculative decoding uses a small draft model for speed and a large model for verification to optimize performance \[[07:27](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=447)].  
* 🗣️ Voice agents function as stateful systems that simultaneously listen, think, and respond using WebRTC for low latency \[[09:06](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=546)].  
* 🛠️ Real-time orchestration requires Speech-to-Text (STT), Large Language Models (LLMs), and Text-to-Speech (TTS) engines \[[10:42](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=642)].  
* 🛑 Voice Activity Detection (VAD) coupled with turn-detection models prevents awkward interruptions during natural speech \[[11:03](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=663)].  
* 📚 Context loading via structured data reduces hallucinations by providing specific product details and objection handlers \[[16:32](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=992)].  
* 🔄 Multi-agent architectures improve accuracy by routing queries to specialized agents like technical or pricing experts \[[21:08](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=1268)].  
* 🔗 Handover mechanisms allow a greeting agent to identify intent and transfer the session to the relevant specialist \[[22:22](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=1342)].  
  
## 🤔 Evaluation  
  
* ⚖️ While Cerebras claims massive speed advantages, NVIDIA maintains a dominant ecosystem with CUDA, which remains the industry standard for software compatibility according to The State of AI Report by Air Street Capital.  
* 🌐 The focus on on-chip memory is a distinct architectural choice compared to the HBM-heavy approach of NVIDIA H100s, which prioritize massive parallel throughput for training over ultra-low latency inference.  
* 🔍 Research into multi-agent systems by Microsoft (AutoGen) suggests that while routing improves specialization, it can increase orchestration complexity and error rates in handoffs.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 🏎️ Q: How does Cerebras hardware achieve high inference speeds?  
  
🤖 A: It uses a wafer-scale engine that integrates memory directly onto the processing cores to eliminate off-chip data transfer delays \[[06:35](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=395)].  
  
### 📉 Q: Why use WebRTC instead of HTTP for voice AI agents?  
  
🤖 A: HTTP is designed for text and has high overhead, whereas WebRTC enables sub-100ms latency for real-time voice data transmission \[[15:24](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=924)].  
  
### 🤝 Q: What is the benefit of a multi-agent sales system?  
  
🤖 A: It allows for specialized knowledge silos, ensuring technical or pricing questions are handled by models with specific relevant context \[[21:42](http://www.youtube.com/watch?v=mwzk2rlwtZE&t=1302)].  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
  
* 📘 Chip War by Chris Miller explains the evolution of semiconductor architecture and the competition for hardware dominance.  
* [🤖⚙️🔁 Designing Machine Learning Systems: An Iterative Process for Production-Ready Applications](../books/designing-machine-learning-systems-an-iterative-process-for-production-ready-applications.md) by Chip Huyen covers the practical aspects of building real-time AI applications and infrastructure.  
  
### 🆚 Contrasting  
  
* [🤖📈 Prediction Machines: The Simple Economics of Artificial Intelligence](../books/prediction-machines-the-simple-economics-of-artificial-intelligence.md) by Ajay Agrawal focuses on the economic impact of AI rather than the low-level hardware implementation.  
* 📜 The Age of AI by Henry Kissinger explore the societal and philosophical implications of AI rather than technical construction.  
  
### 🎨 Creatively Related  
  
* 🎨 The Art of Doing Science and Engineering by Richard Hamming discusses the mindset required for breakthrough innovations in computing hardware.  
* 🏗️ Working in Public by Nadia Eghbal examines the open-source ecosystems that support tools like LiveKit and Python.