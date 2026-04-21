---
share: true
aliases:
  - "🏆🐘🆚🔮⚠️ Turing Award Winner: Postgres, Disagreeing with Google, Future Problems | Mike Stonebraker"
title: "🏆🐘🆚🔮⚠️ Turing Award Winner: Postgres, Disagreeing with Google, Future Problems | Mike Stonebraker"
URL: https://bagrounds.org/videos/turing-award-winner-postgres-disagreeing-with-google-future-problems-mike-stonebraker
Author:
Platform:
Channel: Ryan Peterman
tags:
youtube: https://youtu.be/YPObBOwIrHk
---
[Home](../index.md) > [Videos](./index.md)  
# 🏆🐘🆚🔮⚠️ Turing Award Winner: Postgres, Disagreeing with Google, Future Problems | Mike Stonebraker  
![Turing Award Winner: Postgres, Disagreeing with Google, Future Problems | Mike Stonebraker](https://youtu.be/YPObBOwIrHk)  
  
## 🤖 AI Summary  
* 💾 Postgres originated from the need for an extendable type system to support geographic information systems and custom financial bond calendars \[[13:10](http://www.youtube.com/watch?v=YPObBOwIrHk&t=790)].  
* 🗺️ Standard data types like integers and floats failed to efficiently manage points, lines, and polygons required for spatial data \[[10:03](http://www.youtube.com/watch?v=YPObBOwIrHk&t=603)].  
* 🤝 Mentorship is critical for early career success; being adopted by an experienced guide provides the necessary knowledge of the ropes \[[01:20](http://www.youtube.com/watch?v=YPObBOwIrHk&t=80)].  
* 🤥 Technical superiority often loses to aggressive sales tactics, such as shipping unimplemented features and letting customers debug them \[[07:02](http://www.youtube.com/watch?v=YPObBOwIrHk&t=422)].  
* 🧩 The query optimizer remains the most algorithmically difficult and challenging component of building any database system \[[12:16](http://www.youtube.com/watch?v=YPObBOwIrHk&t=736)].  
* 📉 Computer science may no longer be a growth industry; stable trades like healthcare or building may be safer for future generations \[[53:23](http://www.youtube.com/watch?v=YPObBOwIrHk&t=3203)].  
* 🐢 One size fits none in database architecture, as generic systems sacrifice an order of magnitude in performance compared to specialized engines \[[16:53](http://www.youtube.com/watch?v=YPObBOwIrHk&t=1013)].  
* ⚡ GPUs are ineffective for indexing because B-tree traversals require sequential memory accesses that do not parallelize well with SIMD \[[19:11](http://www.youtube.com/watch?v=YPObBOwIrHk&t=1151)].  
* ❌ Large language models score 0% on real-world data warehouse benchmarks because they lack exposure to private, non-mnemonic, and messy schemas \[[44:23](http://www.youtube.com/watch?v=YPObBOwIrHk&t=2663)].  
* 🏢 Operating systems can be improved by replacing the upper layers with database technology for more efficient scheduling and file management \[[32:41](http://www.youtube.com/watch?v=YPObBOwIrHk&t=1961)].  
* ⛓️ Distributed data integrity requires atomicity and consistency; eventual consistency is a poor trade-off that fails most enterprise needs \[[26:30](http://www.youtube.com/watch?v=YPObBOwIrHk&t=1590)].  
* 🗣️ High-level programmers should seek environments with minimal bureaucracy to maintain the ability to publish and speak freely \[[29:40](http://www.youtube.com/watch?v=YPObBOwIrHk&t=1780)].  
  
## 🤔 Evaluation  
🏗️ Stonebraker’s critique of Google's MapReduce and eventual consistency aligns with the industry's shift toward Spanner, a globally distributed database that provides strong consistency. This transition is documented in the paper Spanner: Google’s Globally-Distributed Database by Google researchers. While Stonebraker advocates for specialized database engines, some modern perspectives from Snowflake (Snowflake Computing) suggest that a unified cloud data platform can bridge the performance gap between row and column stores through clever metadata management and micro-partitioning. To better understand the limits of AI in data management, one should explore the Beaver benchmark mentioned in the video to see how LLMs struggle with structural complexity compared to human SQL experts.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 🐘 Q: Why was Postgres created after the success of Ingres?  
🐘 A: Postgres was developed to solve the limitations of Ingres's hardcoded data types, allowing for an extendable system that could handle complex data like geographic coordinates and custom business calendars \[[13:18](http://www.youtube.com/watch?v=YPObBOwIrHk&t=798)].  
  
### 📉 Q: How do Large Language Models perform on real-world SQL tasks?  
📉 A: LLMs struggle significantly with real-world data warehouses, often scoring near 0% on complex benchmarks due to messy schemas and the absence of specific private data in their training sets \[[44:23](http://www.youtube.com/watch?v=YPObBOwIrHk&t=2663)].  
  
### 🏎️ Q: Why are GPUs considered suboptimal for database indexing?  
🏎️ Q: GPUs use Single Instruction Multiple Data (SIMD) architectures which do not align well with the sequential, pointer-following nature of B-tree index lookups \[[20:44](http://www.youtube.com/watch?v=YPObBOwIrHk&t=1244)].  
  
### 🌐 Q: What is the main drawback of eventual consistency in distributed systems?  
🌐 A: Eventual consistency prioritizes performance over data integrity, which can lead to errors like overselling inventory or breaking referential integrity in enterprise applications \[[25:33](http://www.youtube.com/watch?v=YPObBOwIrHk&t=1533)].  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
* 📕 Readings in Database Systems by Peter Bailis, Joseph Hellerstein, and Michael Stonebraker explores the foundational papers and technical evolutions of data management systems.  
* 📗 Designing Data-Intensive Applications by Martin Kleppmann provides a deep dive into the trade-offs of consistency, scalability, and specialized database architectures.  
  
### 🆚 Contrasting  
* 📘 The Lean Startup by Eric Ries emphasizes shipping early and iterating based on customer feedback, a strategy often at odds with Stonebraker's focus on deep academic rigor before commercialization.  
* 📙 NoSQL Distilled by Pramod J. Sadalage and Martin Fowler explains the rise and utility of non-relational systems that Stonebraker frequently critiques as being less performant than specialized relational engines.  
  
### 🎨 Creatively Related  
* 📓 The Soul of a New Machine by Tracy Kidder captures the high-stakes, obsessive nature of engineering teams building complex computer systems from the ground up.  
* 📔 Dreaming in Code by Scott Rosenberg chronicles the immense difficulty of managing software complexity and the common pitfalls of large-scale programming projects.