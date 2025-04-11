---
share: true
aliases:
  - Maximizing AI Leverage
title: Maximizing AI Leverage
---
[Home](../index.md) > [Topics](./index.md)  
# Maximizing AI Leverage  
## 🖼️ Background  
- [LLMs](./large-language-models.md) are all the rage now.  
- I think it's been a year or two since I first used a chatbot to write a release email for me at work.  
- Nowadays, it's not uncommon for me to use Copilot to draft some code for me.  
- And I'm regularly asking Chatbots questions for certain problems I'd previously have gone to Google for.  
- LLMs are still limited in their capabilities, but given what they're good at, they can drastically speed up a variety of writing tasks.  
- They also seem to be getting better all the time.  
- As a software engineer, I spent a lot of time in school and early in my career on tooling and practices to improve my efficacy.  
- Vim, functional programming, [linux](../software/linux.md) and terminal skills, etc  
- I think it's time to invest in optimizing the benefit I get out of LLMs.  
- I recently set up ollama on my work machine to play with local LLMs.  
- What are LLMs really good at and how can I best leverage them?  
- My general feeling is that they're great at presenting first drafts for me to review. Sometimes after a few prompts, I can coax them into producing a final draft, too. This applies to writing code, messages, and plans.  
- I haven't personally worked with tool wielding LLMs yet, but from what I've seen, this has a lot of potential, too.  
- I'm imagining that, given today's technology, LLMs should be able to  
    - make for much more effective voice assistants  
    - automate a variety of tedious tasks  
    - play a more significant role in most engineering activities  
    - read my notes, emails, etc in order to serve me better  
- of course, I'm not thrilled with the idea of sending all of my personal information off to the servers of some AI startup.  
- and given the pros and cons of various offerings, the cost of multiple subscriptions could quickly add up.  
- I want a benevolent, private, offline AI assistant capable of leveraging all of my tools, accounts, and documents.  
    - Free would be nice, too.  
    - And I think this is technically feasible.  
    - I don't think it exists yet, but I think that's primarily because they're developed by companies eager to profit from the new technology.  
    - 🤔 Maybe it's time for a new side project.  
- Where to begin?  
- I'm thinking about leverage. If I'm going to invest in this project, where will I get the most return on my efforts?  
- My initial thought is to start building an engineering assistant. If I can build a system that can help me build better systems faster, we should be off to the races.  
- I think this would be a great open source project. Working on the not only allows me to share the benefits this tool may provide, but could also invite collaboration that could further improved product quality and development velocity.  
- Maybe I should start with a system design.  
  
## AI Engineering Assistant System Design  
1. Functional Requirements (features)  
  1. Integrates with my engineering tools  
  2. Leverages large quantities of data at runtime to improve performance  
  3. Proposes work for me to review  
  4. Can use as much time as I want to give it to iterate toward the best solution it can generate  
2. Non-Functional Requirements (qualities)  
  1. Private  
  2. Fast  
3. Primary Data Model Entities  
  1. Devices (phone, laptop, desktops, etc)  
  2. 3rd Party Tools & Services  
  3. Databases & Document stores  
  4. AI Agents  
4. API  
  1. Text Prompt :: Natural Language Request -> (Text Response | Actions)  
  2. (Optional) Voice Prompt :: Sound -> Text  
5. Diagram  
  
  ![2024-12-28 2024-12-28T20-00-30.excalidraw](../2024-12-28%202024-12-28T20-00-30.excalidraw.svg)  
%%[🖋 Edit in Excalidraw](../2024-12-28%202024-12-28T20-00-30.svg)%%  
  
6. Discussion  
    1. All of these components could be on the same device, or they could be distributed across personal devices.  
    2. For example, maybe each component is on my development computer, but there's a prompt on my phone that connects to the agent on my development computer over the network. This could  
        1. make advanced performance feasible on limited mobile devices  
        2. Allow history, document, and tool access to be shared across devices. e.g. I could use a voice prompt on my smartphone to start a long running task on a more capable computer, then check on the results later.  
    3. Aiming for simplicity in the first version, we can start with all components on one device. Keeping the distributed case in mind may help guide some design decisions that allow for easy extension later on. e.g. developing components that sit behind web APIs.  
    4. While I haven't personally used an agent based system that can interact with tools, I have recently set up an ollama server that gets very close. It's possible that this project may only require installing and configuring off the shelf components.  
    5. References  
      1. [Ollama Course – Build AI Apps Locally](../videos/ollama-course-build-ai-apps-locally.md)  
      2. [I Built an AI That Does My Work For Me](../videos/i-built-an-ai-that-does-my-work-for-me.md)  
      3. [Anthropic MCP + Ollama. No Claude Needed? Check it out!](../videos/anthropic-mcp-ollama-no-claude-needed-check-it-out.md)  
      4. https://ollama.com  
      5. https://modelcontextprotocol.io  
      6. [AI Engineering Assistant Technology Recommendations](../bot-chats/ai-engineering-assistant-technology-recommendations.md)  
