---
share: true
aliases:
  - Design a Performance Self-Evaluation System
title: Design a Performance Self-Evaluation System
URL: https://bagrounds.org/topics/design-a-performance-self-evaluation-system
---
[Home](../index.md) > [Topics](./index.md)  
# Design a Performance Self-Evaluation System  
![design-a-performance-self-evaluation-system](../design-a-performance-self-evaluation-system.svg)  
  
---  
## 🦟🔍 Bug Investigation  
🤔 Why doesn't my embedded Excalidraw get converted to svg when I publish this note?  
### 👀 Observations  
- there is an image element embedded in the page, but it doesn't render  
- when I view the image at its url directly, I see the following error and a blank page  
```  
This page contains the following errors:  
error on line 1 at column 1: Start tag expected, '<' not found  
Below is a rendering of the page up to the first error.  
```  
  
### Hypothesis  
The Excalidraw is being sent over as markdown instead of directly being converted to svg  
  
### 🦟 The Bug  
![Drawing 2024-12-12 17.20.04.excalidraw](../Drawing%202024-12-12%2017.20.04.svg)  
