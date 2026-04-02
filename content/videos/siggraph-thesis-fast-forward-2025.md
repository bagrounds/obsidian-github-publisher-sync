---
share: true
aliases:
  - 🧑‍💻📈⏩ SIGGRAPH Thesis Fast Forward 2025
title: 🧑‍💻📈⏩ SIGGRAPH Thesis Fast Forward 2025
URL: https://bagrounds.org/videos/siggraph-thesis-fast-forward-2025
Author:
Platform:
Channel: ACMSIGGRAPH
tags:
youtube: https://youtu.be/8esFWCQ_46Y
---
[Home](../index.md) > [Videos](./index.md)  
# 🧑‍💻📈⏩ SIGGRAPH Thesis Fast Forward 2025  
![SIGGRAPH Thesis Fast Forward 2025](https://youtu.be/8esFWCQ_46Y)  
  
## 🤖 AI Summary  
The 🎬 presentation covers six distinct thesis projects spanning computational graphics, physics, and design.  
  
* **Computational Shape Design through Robust Physics Simulations:**  
    * 📐 Proposed a special family of cells that can **preserve the geometry surface** when discretizing objects, improving upon traditional coarse voxel grid methods \[[01:15](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=75)].  
    * 🛡️ Developed a **robust differentiable simulator** based on the IPC (Intersection-Free, Physically-Based Collision-Handling) method to handle large deformations without self-intersection \[[01:38](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=98)].  
    * 💥 Applied the work to design **microstructures for shock absorbers** that undergo extremely large deformation and complex contact, with simulation results validated to match physical experiments \[[02:47](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=167)].  
  
* **Domain-Specific Languages (DSLs) for Geometry Processing:**  
    * ✍️ Introduced **AATALa** (AATALanguage), a DSL with a syntax designed to closely **mimic conventional linear algebra** while ensuring an unambiguous, compilable interpretation \[[04:11](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=251)].  
    * 🔄 AATALa compiles the same source into **LaTeX, C++ with Eigen, Python with NumPy/SciPy, and MATLAB**, making it convenient to maintain consistency across different platforms \[[04:28](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=268)].  
    * 📝 Developed **MATH Down**, an environment for scientific documents that supports compiling the arguments into a paper with **clickable definitions** and warns when a variable is not described \[[05:12](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=312)].  
  
* **Intelligent Optimization and Inverse Rendering:**  
    * 🚀 Introduced **MetAppearance** to accelerate slow network convergence by learning to adapt the network initialization itself, achieving overfitting quality at **interactive speeds** \[[07:13](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=433)].  
    * ⛰️ Proposed **PrPT** (Plateau Reduction Path Tracing) to alleviate plateaus in the cost landscape by convolving the rendering equation with a Gaussian smoothing kernel, leading to smoother cost landscapes and improved robustness \[[08:04](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=484)].  
    * ⚫ Developed **ZeroGrads** to enable gradient-based optimization on arbitrary **non-differentiable forward models** by sampling the cost landscape and building a neural model of it to compute the gradient \[[08:46](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=526)].  
  
* **Human-Centered and AI-Based Digital Painting:**  
    * 🎨 Aimed to bridge the gap between AI tools and the human creative process by improving digital painting technologies to better understand how artists **think and create** \[[10:27](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=627)].  
    * 🖼️ Framed complex sketch vectorization as a **surface extraction problem**, using the signed distance field and dual contouring to reconstruct vector lines and handle intricate details \[[11:10](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=670)].  
    * ⏱️ Created **Flat Magic**, a tool to automate the tedious **flatting** stage in comic production using simplified line drawings that represent only the boundaries of the regions \[[11:46](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=706)].  
  
* **Biologically Plausible Skin Texture Generation:**  
    * 🔬 Utilized **Baroni's biophysical model** to capture a faithful Bi-Directional Reflectance Distribution Function (**BRDF**) of skin under biological parameters like pigment concentration and layer thickness \[[13:29](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=809)].  
    * 🩸 Created a biologically plausible model for **vascular growth** that allows blood vessel networks to be grown interactively within a mesh, supporting **dynamic changes in blood flow** during animation \[[14:19](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=859)].  
    * ✨ Developed a conversion method that uses a **lookup table** to transform the BioSpec BRDF into a model supported by the target render engine in **real-time** \[[15:02](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=902)].  
  
* **3D Media Access Transform (MAT) Computing:**  
    * 🧩 Addressed the challenges in computing high-quality 3D Medial Axis Transform (MAT) for **CAD models** by focusing on preserving features, topology equivalence, and geometric accuracy \[[16:50](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=1010)].  
    * 🗺️ Used the **Restricted Power Diagram (RPD)** as a framework, which provides a natural decomposition and connectivity based on the medial spheres \[[17:08](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=1028)].  
    * 🔗 Ensured **topology preservation** by testing topological indicators for each restricted element of RPD and applying refinement (adding new medial spheres) when the Nerve theorem criteria are not met \[[17:39](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=1059)].  
  
## 🤔 Evaluation  
* The 💡 thesis on intelligent optimization in **inverse rendering** directly tackles well-known, high-level challenges in the field.  
* Inverse rendering is widely recognized as a **highly ill-posed problem** due to the infinite number of illumination, geometry, and material combinations that can produce the same image, as noted in the *Inverse Rendering: A Survey* by Hanlin "Asher" Mai.  
* The video's proposed solution, **PrPT**, for alleviating cost landscape plateaus, attempts to resolve a fundamental issue that commonly hinders gradient-based optimization in inverse rendering, a challenge frequently discussed in literature such as the paper *Efficient and Accurate Optimization in Inverse Rendering and Computer Graphics* published on researchgate.net.  
* The core challenge of **non-differentiable forward models** is also a major limitation in graphics, making the **ZeroGrads** surrogate model approach a timely and relevant attempt to unify gradient-based optimization across various systems.  
* **Topics to explore for a better understanding:**  
    * ⚖️ Investigate the **Nerve theorem**'s specific application within the Restricted Power Diagram (RPD) framework for ensuring **topology preservation** in the 3D Medial Axis Transform.  
    * 🤝 Explore the efficacy of the **human-centered approach** in digital painting by finding case studies or artist feedback on tools like **Flat Magic** to evaluate its real-world impact on professional workflows.  
    * ⚡ Determine the computational complexity and **hardware requirements** for the real-time BRDF conversion and dynamic blood flow features in the biologically plausible skin texture generation system.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### ❓ Q: Why does **PrPT** improve convergence in inverse rendering?  
**A:** 📈 PrPT (Plateau Reduction Path Tracing) improves convergence by addressing a major issue in inverse rendering: **cost landscape plateaus**. 📉 These plateaus—regions of zero gradient—occur because multiple combinations of scene parameters can result in the same per-pixel loss value, causing the optimization algorithm to get stuck \[[07:50](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=470)]. 💡 PrPT solves this by **convolving the rendering equation with a Gaussian smoothing kernel**, which effectively smooths out these plateaus and allows the optimization to find a path to the solution \[[08:04](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=484)].  
  
### ❓ Q: What is **AATALa** and how does it benefit geometry processing?  
**A:** 💻 **AATALa** is a Domain-Specific Language (DSL) that uses syntax designed to closely resemble **conventionally written linear algebra** \[[04:11](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=251)]. ✍️ This makes the code easier to read and write for researchers. 🔄 The key benefit is its ability to compile the single source code into multiple target languages and formats, including **LaTeX, C++, Python (with NumPy/SciPy), and MATLAB** \[[04:28](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=268)]. This ensures the mathematical formula remains **consistent** and unambiguous across papers, implementations, and platforms, eliminating bugs caused by re-implementation \[[03:40](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=220)].  
  
### ❓ Q: How does the computational shape design thesis ensure the structural model is **robust** under large forces?  
**A:** 🛡️ The thesis addresses structural robustness by developing a **robust differentiable simulator** specifically designed to handle collisions and large deformations \[[01:38](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=98)]. 💥 Traditional methods struggle with structures self-intersecting under large deformation due to a lack of collision handling \[[01:29](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=89)]. ⚙️ The new simulator is based on **IPC** (Intersection-Free, Physically-Based Collision-Handling) and guarantees **stability and intersection-free** simulation, making the design of complex structures like shock absorbers reliable \[[01:48](http://www.youtube.com/watch?v=8esFWCQ_46Y&t=108)].  
  
### ❓ Q: What role does the **Restricted Power Diagram (RPD)** play in calculating the 3D Medial Axis Transform (MAT)?  
**A:** 🗺️ The RPD is the core framework for accurate 3D MAT computation, especially for complex **CAD models**. 📐 It provides a **natural decomposition** of the shape based on the medial spheres. 💡 The RPD is key to preserving **geometric features** and the correct **topology** using the *minimal* number of medial spheres.  
  
### ❓ Q: How does the biologically plausible skin model account for **dynamic changes** in appearance?  
**A:** 🩸 The model uses a biologically plausible system for **vascular growth**, allowing interactive growth of **blood vessel networks** within a mesh. 💨 This system supports **dynamic changes in blood flow** during animation, such as the natural blanching (evacuation of blood) that occurs when pressure is applied to the skin.  
  
### ❓ Q: What is the significance of extending microstructure design to include **large deformations** and complex contacts?  
**A:** 🛠️ It enables the creation of highly functional designs, like effective **shock absorbers**. 💡 This is achieved with a **robust differentiable simulator**, which handles complex self-contact and guarantees **intersection-free** simulation. 💥 This allows designers to create microstructures that can undergo extreme, non-linear movement while reliably performing their protective function.  
  
## 📚 Book Recommendations  
  
### Similar Books  
* ⚛️ **Physically Based Rendering: From Theory to Implementation** by *Matt Pharr, Wenzel Jakob, and Greg Humphreys*. The definitive guide for physically based light transport, directly relevant to the **BRDF** modeling and **inverse rendering** work in the video.  
* **[🧠💻🤖 Deep Learning](../books/deep-learning.md)** by *Ian Goodfellow, Yoshua Bengio, and Aaron Courville*. Provides the foundational knowledge for the deep learning techniques used in **MetAppearance** and **ZeroGrads** for intelligent optimization.  
* 💻 **Fundamentals of Computer Graphics** by *Steve Marschner and Peter Shirley*. A comprehensive textbook that covers mesh processing, rendering pipelines, and geometric concepts like the **Medial Axis Transform**.  
  
### Contrasting Books  
* **[🦢 The Elements of Style](../books/the-elements-of-style.md)** by *William Strunk Jr. and E. B. White*. This book on concise, clear writing contrasts with the need for formal, unambiguous language in the DSL design (**AATALa**), highlighting the tension between natural and formal language.  
* 🎨 **Art and Fear: Observations on the Perils (and Rewards) of Artmaking** by *David Bayles and Ted Orland*. A philosophical look at the creative process, offering a counterpoint to the analytical approach of the **human-centered digital painting** thesis.  
* **[🤖📈 The Second Machine Age: Work, Progress, and Prosperity in a Time of Brilliant Technologies](../books/the-second-machine-age-work-progress-and-prosperity-in-a-time-of-brilliant-technologies.md)** by *Erik Brynjolfsson and Andrew McAfee*. Provides an economic and social perspective on how AI and automation (like **Flat Magic**) change creative and professional labor.  
  
### Creatively Related Books  
* **[💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md)** by *Don Norman*. A classic text on human-centered design, highly relevant to the goal of creating **digital painting tools** that better align AI with the user's creative process.  
* 🧬 **The Book of Skin** by *Steven Connor*. A literary and philosophical exploration of skin as a surface and boundary, providing a creative context for the work on **biologically plausible skin texture generation**.  
* 🧱 **Generative Design: Visualize, Program, and Create with Processing** by *Hartmut Bohnacker, Benedikt Gross, and Julia Laub*. A practical book on using code to create art, connecting the structured world of DSLs and algorithms to the more abstract output of digital creativity.