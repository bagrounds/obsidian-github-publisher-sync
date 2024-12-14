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
_If you're here for the performance self-evaluation system, you can ignore everything below_  
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
  
### 🧑‍🔬 Attempts  
- I've updated my GitHub publisher (now [Enveloppe](https://enveloppe.github.io)) Obsidian plugin to the latest version  
- I've updated my Excalidraw Obsidian plugin to the latest version  
- I've tried toggling a bunch of settings in my Envelope plugin related to links and conversions  
- I've looked through Envelope's GitHub issue tracker for similar problems  
  
###  🤔 Hypothesis  
The Excalidraw is being sent over as markdown instead of directly being converted to svg  
  
### 📎 Workaround  
In the meantime, I've exported the excalidraw to svg and embedded that directly.  
This gives the same end result, but requires a suboptimal workflow: re-export the file on every change, delete the old one, and rename the new export.  
  
### 🦟 The Bug  
![Drawing 2024-12-12 17.20.04.excalidraw](../Drawing%202024-12-12%2017.20.04.svg)  
