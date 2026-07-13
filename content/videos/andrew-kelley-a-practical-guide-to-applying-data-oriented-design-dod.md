---
share: true
aliases:
  - "⚙️📊 Andrew Kelley: A Practical Guide to Applying Data Oriented Design (DoD)"
title: "⚙️📊 Andrew Kelley: A Practical Guide to Applying Data Oriented Design (DoD)"
URL: https://bagrounds.org/videos/andrew-kelley-a-practical-guide-to-applying-data-oriented-design-dod
Author:
Platform:
Channel: ChimiChanga
tags:
youtube: https://youtu.be/IroPQ150F6c
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-07-12T00:00:00Z
force_analyze_links: false
---
[Home](../index.md) > [Videos](./index.md)  
# ⚙️📊 Andrew Kelley: A Practical Guide to Applying Data Oriented Design (DoD)  
![Andrew Kelley: A Practical Guide to Applying Data Oriented Design (DoD)](https://youtu.be/IroPQ150F6c)  
  
## 🤖 AI Summary  
  
* 🧠 Modern computing architectures operate with a significant speed disparity between CPU execution and main memory access, making efficient memory utilization crucial.  
* ⚡ The core strategy for high-performance software involves minimizing cache misses by reducing the memory footprint of data structures.  
* 📏 Structs should be scrutinized for memory alignment and size, as compilers often introduce implicit padding that wastes space.  
* 📎 Replace pointers with integer indexes to reduce struct size, especially on 64-bit systems, while being mindful of type safety.  
* 🚩 Store boolean flags out-of-band, such as by segregating items into separate arrays based on their state, to avoid unnecessary memory loads and branches.  
* 📦 Utilize struct-of-arrays layouts instead of arrays-of-structs to eliminate internal padding and improve data locality.  
* 🗺️ Employ hashmaps to store sparse data externally, reducing the overhead for the vast majority of items that do not require specific fields.  
* 🔣 Replace heavy object-oriented polymorphism with specialized encodings, which allow for a more compact and precise representation of object state.  
* 📉 Apply these techniques to compiler pipelines - specifically tokenization and syntax tree representation - to achieve substantial reductions in wall-clock execution time.  
* 💾 Consider embarrassingly parallel tasks, such as those found in compiler front-ends, as candidates for massive performance gains through multi-threading and optimized data loading strategies.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### ❓ What distinguishes data oriented design from object oriented design?  
  
🍎 Data oriented design prioritizes the physical layout of data in memory to match hardware characteristics, whereas object oriented design often focuses on abstraction and logical relationships that can lead to inefficient memory access patterns and increased cache misses.  
  
### ❓ Why does using pointers in structs consume more memory than using indices?  
  
🍎 On 64-bit architectures, pointers are 8 bytes wide, whereas indices can often be represented as 32-bit or even 16-bit integers, effectively halving or reducing the memory footprint of the struct while also reducing alignment requirements.  
  
### ❓ How does organizing data into a struct of arrays improve performance?  
  
🍎 This layout ensures that fields of the same type are contiguous in memory, which eliminates the padding bytes required to satisfy alignment constraints in an array of structs and significantly improves cache efficiency during bulk processing.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
  
* 📘 Game Engine Architecture by Jason Gregory offers a comprehensive look at the systems and data structures required to build high-performance gaming software.  
* 📗 Data Oriented Design by Richard Fabian provides the foundational principles for organizing code and data to align with modern CPU capabilities.  
  
### 🆚 Contrasting  
  
* 📙 Design Patterns: Elements of Reusable Object-Oriented Software by Erich Gamma et al. presents the classic object-oriented approach that favors abstraction over the hardware-centric view advocated in the video.  
* 📕 [🧼💾 Clean Code: A Handbook of Agile Software Craftsmanship](../books/clean-code.md) by Robert C. Martin focuses on software maintainability and readability, often prioritizing developer ergonomics over raw hardware-level optimization.  
  
### 🎨 Creatively Related  
  
* 📓 The Soul of a New Machine by Tracy Kidder chronicles the intense engineering effort behind designing a new computer, highlighting the intersection of hardware and software design.  
* 📔 Code: The Hidden Language of Computer Hardware and Software by Charles Petzold explains the fundamental physical and logical structures that underpin how computers actually process information.