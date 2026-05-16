---
share: true
aliases:
  - 📈❓📏🤖 On the Difficulty of Extrapolation with NN Scaling
title: 📈❓📏🤖 On the Difficulty of Extrapolation with NN Scaling
URL: https://bagrounds.org/articles/on-the-difficulty-of-extrapolation-with-nn-scaling
Author:
tags:
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-27T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
image_date: 2026-05-16T13:45:20Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, high-contrast illustration featuring a series of glowing, interconnected nodes representing a neural network. The network structure is depicted as a landscape of peaks and valleys, with a bright, clean line graph overlaid on top. The graph begins as a smooth, ascending curve that suddenly diverges into a jagged, chaotic path as it moves toward the right edge of the frame, symbolizing the unpredictability of extrapolation. The color palette uses deep navy and charcoal backgrounds with vibrant neon cyan and amber accents for the lines and nodes. A subtle, misty grid pattern fades into the background to suggest a technical, mathematical environment, while soft light glows from the junction points to convey the complexity of hyperparameter optimization.
---
[Home](../index.md) > [Articles](./index.md)  
# [📈❓📏🤖 On the Difficulty of Extrapolation with NN Scaling](https://lukemetz.com/difficulty-of-extrapolation-nn-scaling)  
![articles-on-the-difficulty-of-extrapolation-with-nn-scaling](../articles-on-the-difficulty-of-extrapolation-with-nn-scaling.jpg)  
## 🤖 AI Summary  
* 📉 The article highlights that while scaling laws can predict performance, "this can be misleading in practice if not done carefully."  
* 💡 An example is provided using "an MLP trained on ImageNet, showing how a naive extrapolation of performance based on a fixed learning rate dramatically underperforms predictions for larger models."  
* ⚙️ The core issue identified is "that as model size increases, optimal hyperparameters, such as the learning rate, can change significantly."  
* ⬇️ The article demonstrates "that larger models require smaller learning rates to achieve better performance, and failing to account for this can lead to costly mistakes in real-world scenarios."  
* ❓ It emphasizes that "while some scaling relationships for hyperparameters can be modeled, there are many other factors (e.g., learning rate schedules, optimization parameters, architecture decisions, initialization) that could also change with scale, making a full understanding of how every aspect of a model changes with scale seem impossible."  
* 📈 The author suggests that "scaling laws can be used to predict best-case performance, and deviations from this can signal that something is not tuned properly."  
* ⚠️ The article concludes by stressing "the importance of balancing the use of scaling laws for extrapolation with actual evaluation at larger scales to avoid expensive errors."  
  
## 🤔 Evaluation  
* ⚖️ This perspective emphasizes the practical challenges of scaling deep learning models, particularly the dynamic nature of optimal hyperparameters.  
* 🧐 It contrasts with purely theoretical scaling law discussions by highlighting real-world pitfalls like suboptimal learning rates.  
* 🔬 To better understand this topic, it would be beneficial to explore research on adaptive learning rate optimizers, and comprehensive studies on how various hyperparameters interact with model scale in different architectures and tasks.  
* 💡 Additionally, investigating the economic implications of such "expensive errors" in large-scale AI development could provide further insight.  
  
## 📚 Book Recommendations  
* [🧠💻🤖 Deep Learning](../books/deep-learning.md) by Ian Goodfellow, Yoshua Bengio, and Aaron Courville: A foundational text that covers the theoretical and practical aspects of deep learning, including optimization and hyperparameter tuning.  
* The Hundred-Page Machine Learning Book by Andriy Burkov: A concise introduction to machine learning concepts, providing a good overview of the challenges in model training and deployment.  
* [🤖⚙️🔁 Designing Machine Learning Systems: An Iterative Process for Production-Ready Applications](../books/designing-machine-learning-systems-an-iterative-process-for-production-ready-applications.md) by Chip Huyen: Explores the complexities of building and deploying large-scale machine learning systems, touching on practical issues like resource management and optimization.  
* Neural Networks and Deep Learning by Michael Nielsen: An online book that offers an intuitive introduction to neural networks, which could provide a different perspective on the fundamentals of scaling.  
* [🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md) by Daniel Kahneman: While not directly about AI, this book on cognitive biases can offer an interesting parallel to the "naive extrapolation" discussed in the article, highlighting how humans can also make errors in prediction based on incomplete information.