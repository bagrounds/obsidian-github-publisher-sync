---
URL: https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying
aliases:
  - "The Log: What every software engineer should know about real-time data's unifying abstraction"
Author: "[[jay-kreps]]"
share: true
title: "The Log: What every software engineer should know about real-time data's unifying abstraction"
---
[Home](../index.md) > [Articles](./index.md)  
# The Log: What every software engineer should know about real-time data's unifying abstraction  
  
## 🤖 AI Summary  
**📖 Summary of "The Log: What every software engineer should know about real-time data's unifying abstraction"**  
  
The article argues that the "log," 🪵 or an append-only, ➕ ordered sequence of records, 📝 is a fundamental 🔑 abstraction for building reliable, ✅ real-time ⏱️ data systems. ⚙️ It highlights how the log:  
  
* 🧩 **Simplifies Data Management:** 🧮 It provides a single 🥇 source of truth, ✅ enabling consistency 🤝 and fault tolerance. 🛡️  
* 🔗 **Enables Decoupling:** ✂️ Producers write to the log, ✍️ 🪵 and consumers read from it, 👂 🪵 allowing for independent scaling ⬆️⬇️ and evolution. 🧬  
* ⏱️ **Supports Real-Time Processing:** ⚡ It facilitates stream processing, 🌊 event sourcing, 🗓️ and change data capture. 📸  
* 🌐 **Underpins Distributed Systems:** 🏗️ It's essential for building distributed databases, 💾 message queues, ✉️ and other robust systems. 💪  
  
**💡 Practical Takeaways:**  
  
* ➕ **Embrace Append-Only:** 🧱 Design systems to treat data as an immutable sequence of events.  
* 🔗 **Use Logs for Data Integration:** 🪵 Leverage logs to connect disparate systems and enable real-time data flow. 🌊  
* 🛡️ **Build Fault-Tolerant Systems:** 🔁 Utilize log replication and partitioning to ensure data durability and availability. ✅  
* 〰️ **Think in Streams:** 🌊 Consider data as a continuous stream of events rather than static snapshots. 📸  
* 🧑‍💻 **Understand Kafka:** Apache Kafka is a popular implementation of the log concept, and understanding it is very valuable for many large data systems. 🚀📚  
  
**⭐ Recommendations:**  
  
* ✅ **Best Alternate Resource on the Same Topic:**  
    * 💖 "I Heart Logs: Event Data, Stream Processing, and Data Integration" by Jay Kreps. This is a more 🧐 in-depth exploration of the log concept, written by one of the creators of 🐘 Kafka. It provides a 💯 comprehensive overview of the log's applications and benefits. 📚  
* ➕ **Best Resource That Is Tangentially Related:**  
    * ⚙️ "[Designing Data-Intensive Applications](../books/designing-data-intensive-applications.md)" by Martin Kleppmann. While it covers a 🌐 broad range of data system topics, it provides excellent context on 👯‍♀️ distributed systems, 🤝 consistency, and 💾 data storage, all of which are closely related to the log concept. This book provides excellent ℹ️ background information. 💻  
* ➖ **Best Resource That Is Diametrically Opposed:**  
    * 🏛️ "Database System Concepts" by Abraham Silberschatz, Henry F. Korth, and S. Sudarshan. While a 🕰️ classic, traditional database texts often emphasize relational databases and transactional systems, which can sometimes 💥 clash with the event-driven, log-centric approach. This resource is great to show the traditional side of 🗄️ Data bases. 💾  
* 📖 **Best Fiction That Incorporates Related Ideas:**  
    * 😈 "Daemon" and "Freedom™" by Daniel Suarez. These 🤖 techno-thrillers explore the concept of 👯‍♀️ distributed systems and ⚙️ autonomous agents, which rely on ⏱️ real-time data and event-driven architectures. While fictional, they offer a 🤩 compelling glimpse into the potential of these technologies. 🤖 These books contain many real world computer science concepts.  
  
## 💬 [Gemini](https://Gemini.google.com) Prompt  
> Summarize the article: [The Log: What every software engineer should know about real-time data's unifying abstraction](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying). Emphasize practical takeaways. Make the following additional recommendations: the best alternate resource on the same topic, the best resource that is tangentially related, the best resource that is diametrically opposed, and the best fiction that incorporates related ideas. Use lots of emojis.