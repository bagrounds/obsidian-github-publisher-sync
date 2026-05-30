---
share: true
aliases:
  - "2026-05-29 | 🐉 Welcoming Gemma 4 to the Fiction Rotation 🤖"
title: "2026-05-29 | 🐉 Welcoming Gemma 4 to the Fiction Rotation 🤖"
URL: https://bagrounds.org/ai-blog/2026-05-29-8-gemma-4-fiction-rotation
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-29 | 🐉 Welcoming Gemma 4 to the Fiction Rotation 🤖

## ✨ What changed today

🐲 The AI fiction rotation just grew two new wings. Gemma 4 has landed on the Gemini API in two flavors, and both are now part of the daily model rotation that decides which model writes the little story attached to each reflection.

🪶 The first flavor is the dense thirty-one billion parameter model, named gemma-4-31b-it on the Gemini side. It is the headline open weights model from the Gemma 4 family, and it is the one most readers will think of when they hear the name Gemma 4.

🧠 The second flavor is the mixture of experts variant, named gemma-4-26b-a4b-it. It activates a small fraction of its weights for any given token, which often means snappier responses while still carrying a large pool of knowledge to draw from.

## 🔁 How the rotation works

📅 The fiction rotation is a pure function of the Pacific date and a fixed pool of candidate models. The day number is reduced modulo the size of the pool, the pool is rotated to put the chosen model first, and the rest of the pool follows behind as a fallback chain.

🎯 Adding two new models means the pool is now eight long, so the rotation cycle finishes every eight days and every model gets a turn at being the primary voice.

🪪 The signature on each story still proudly says which model actually wrote it, so readers can see Gemma 4 on the page when its day comes around.

## 🧪 How we test it before it goes live

🩺 The most important question with any new model is whether the live API will actually accept it. Documentation can drift, names can change, and the only way to be sure is to ask the real service.

🛠️ This change ships a tiny new Haskell binary named test-fiction-models. It reads the GEMINI_API_KEY from the environment, sends a short fiction prompt to every model in the rotation pool, prints whatever the API returns, and exits with a failure code if any model fails to respond.

🔌 The binary uses the same generateContent function that the production scheduled job uses, so a green run is real evidence that the production code path will also work. A red run prints the exact API error message and the model name that failed.

📱 A new test-fiction-models GitHub Actions workflow wraps the binary with a workflow_dispatch trigger, which means I can launch the smoke test from the GitHub mobile web interface with a single tap, no laptop required.

🛰️ The Gemini side of the code now also raises a clear warning in the log whenever a model returns a not found status or rejects the request as invalid argument, with a pointer to the official deprecations page. That makes a decommissioned model unmistakable in the scheduled job logs instead of hiding inside a generic error.

🧷 The binary intentionally has no fancy plumbing. It is the smallest possible end to end probe, designed to be safe to run by hand whenever a new model lands or whenever a key needs to be checked.

## 🛡️ Why we picked the same system instruction policy as Gemma 3

📜 The Gemini API has historically rejected the systemInstruction field for the Gemma family. The existing convention treats Gemma 3 as not supporting that field, and the prompt is folded into the user turn instead.

🤝 Both Gemma 4 variants follow the same convention. If a future change confirms that the API now accepts a top level system instruction for Gemma 4, flipping the policy is a one line change and the existing tests will catch any accidental regression.

📚 The conservative choice is annotated in the code with pointers to the official Gemma 4 model card, the dedicated Gemma on Gemini API page, and the Gemini API model and deprecations indexes, so the next person who revisits this can verify against the latest published behavior rather than guessing. The matching pointers also live in the AI fiction spec, so a reader exploring the rotation can hop straight to authoritative documentation.

## 📖 Reflection

🌱 Adding a model to a pool is a small change in lines, and a meaningful change in voice. Each model has its own tone, its own sense of humor, and its own way of imagining a tiny dragon discovering a library. Spreading the work across a larger pool makes the rotation feel less like one author wearing different hats and more like a small ensemble with rotating leads.

🪄 Tomorrow, the fiction at the bottom of a reflection might suddenly read with a slightly different rhythm, and that will be Gemma 4 saying hello.

## 📚 Book Recommendations

### 📖 Similar
* The Wisdom of Crowds by James Surowiecki is relevant because the fiction rotation gets its strength from many different model voices contributing in turn rather than relying on a single perspective.
* Antifragile by Nassim Nicholas Taleb is relevant because spreading work across a pool of models with a primary and a fallback chain is exactly the kind of redundancy that turns occasional failures into harmless background noise.

### ↔️ Contrasting
* Show Your Work by Austin Kleon argues for a single steady voice sharing process publicly, which contrasts with a deliberately rotating ensemble that chooses a fresh voice each day.
* The War of Art by Steven Pressfield treats the daily creative practice as a personal ritual with one author, which sits in tension with the idea of letting the calendar pick today's writer from a pool of language models.

### 🔗 Related
* You Look Like a Thing and I Love You by Janelle Shane is relevant because it explores the surprising, delightful, and sometimes baffling ways that language models invent stories when given short prompts.
* Surely You're Joking, Mr. Feynman by Richard P. Feynman is relevant because the live test binary is a small, hands on instrument for poking the system and watching what it does, which is exactly the kind of curious experimentation Feynman celebrated.
