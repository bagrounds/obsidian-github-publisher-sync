---
share: true
aliases:
  - 🤖🧭 Agentic Software Engineering
title: 🤖🧭 Agentic Software Engineering
tags:
  - AIEngineering
---
[Home](../index.md) > [Topics](./index.md) > [Software Development and Coding](./software-development-and-coding.md)  
# 🤖🧭 Agentic Software Engineering  
  
## 🤖 AI Summary  
  
* 📝 High-Level Summary: Agentic Software Engineering (ASE) represents a fundamental paradigm shift in how software is conceived, developed, and maintained. It leverages AI agents capable of autonomous action, tool use, and iterative problem-solving to amplify human software engineering capabilities. ASE encompasses the study of patterns, tools, frameworks, and best practices for effectively collaborating with AI coding agents. The discipline is evolving rapidly, with new patterns, tools, and research emerging weekly. 🧠💻🚀  
  
* 🔑 Key Concepts: The field is characterized by long-running agent sessions with tool execution capabilities, prompt engineering for agents, multi-agent orchestration, human-in-the-loop oversight, context engineering, and the development of agent-specific software engineering practices distinct from traditional human-centric approaches. The core shift is from "code is expensive" to "code is cheap now" - focusing human effort on architecture, quality, and integration rather than implementation details. ⚡📉  
  
---  
  
## 🧠 Mental Models  
  
### 🌟 The Spectrum of AI-Assisted Development  
  
* 🌱 **AI Prototyping** - Fast, exploratory, prompt-driven. Great for learning and proving concepts. [CTCO](https://www.ctco.blog/posts/vibe-coding-to-agentic-engineering/)  
* 🎯 **Directed AI Assistance** - Specify constraints, reference patterns, define success upfront. Tool is a lever; you're in control. [CTCO](https://www.ctco.blog/posts/vibe-coding-to-agentic-engineering/)  
* 👥 **Agent Orchestration** - Split work across multiple agents, run in parallel, integrate results. Like managing a small team. [CTCO](https://www.ctco.blog/posts/vibe-coding-to-agentic-engineering/)  
* 🏗️ **Agentic Engineering** - Build persistent workflows with context, guardrails, and quality gates. Stay accountable for security and delivery. [Simon Willison](https://simonw.substack.com/p/agentic-engineering-patterns)  
  
### 💡 Core Principles  
  
* 🏰 **Code is Cheap Now** - The fundamental mental shift: writing code has become nearly free. This changes everything about how we estimate, plan, and execute. Focus on architecture, quality, and integration - the decisions that require human judgment. [Simon Willison](https://simonwillison.net/guides/agentic-engineering-patterns/code-is-cheap/)  
  
* ⚖️ **SE for Humans vs SE for Agents** - Agentic SE introduces a fundamental duality: traditional human-centric development and new agent-centric workflows. Each requires different tools, processes, and artifacts. [arXiv](https://arxiv.org/abs/2509.06216)  
  
* 🔄 **From Vibe Coding to Agentic Engineering** - "Vibe coding" (using AI without attention to code, often by non-programmers) contrasts with "agentic engineering" (professional software engineers using AI to amplify their expertise). The latter involves rigorous methodology, quality gates, and accountability. [Simon Willison](https://simonwillison.net/2026/Feb/23/agentic-engineering-patterns/)  
  
### 🎯 The Agentic Engineer Role  
  
* 🧑‍💻 **Architect** - High-level system design and decision-making  
* 🔍 **Quality Controller** - Code review, standards enforcement, catching what agents miss  
* 📚 **Context Manager** - Maintaining documentation and context that makes agents effective  
* 🎯 **Strategist** - Deciding what to build and how to approach it  
  
* 🔑 **Key Insight**: You need to be able to do what the agent does, and recognize when it's gone wrong. Spot subtle bugs, security gaps, and maintainability issues. [CTCO](https://www.ctco.blog/posts/vibe-coding-to-agentic-engineering/)  
  
---  
  
## 🔧 How-To Guidance  
  
### 🧪 Test-Driven Development for Agents  
  
* 📝 **Red/Green TDD** - Write tests first, confirm they fail, then implement. Test-first development helps agents write more succinct, reliable code with minimal prompting. [Simon Willison](https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/)  
  
* 🔴 **Force Broken Tests** - Require agents to write failing tests before implementation to ensure they understand requirements. [Atomic Object](https://spin.atomicobject.com/make-ai-respect-tdd/)  
  
* ▶️ **Real Data Testing** - Use production-like data to gain clarity on edge cases. [Atomic Object](https://spin.atomicobject.com/make-ai-respect-tdd/)  
  
* ⏸️ **Human-in-the-Loop** - Pause the AI and run tests yourself during development cycles. [Atomic Object](https://spin.atomicobject.com/make-ai-respect-tdd/)  
  
### 📁 Context Engineering  
  
* 🗂️ **CLAUDE.md Files** - Project-specific instructions, conventions, and rules that persist across sessions. [Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)  
  
* 📋 **Instruction Directories** - Maintain persistent context files that give agents project-specific rules, patterns, and conventions. The more context you give, the better the outputs. [CTCO](https://www.ctco.blog/posts/github-copilot-tips-and-tricks)  
  
* 📥 **Just-in-Time Loading** - Load relevant context only when needed to avoid overwhelming the context window. [Morph](https://www.morphllm.com/context-engineering)  
  
* 🚫 **.claudeignore** - Exclude irrelevant files from agent context to improve focus and reduce noise. [Morph](https://www.morphllm.com/context-engineering)  
  
* 🔀 **Subagent Isolation** - Delegate subtasks to isolated subagents to prevent context pollution. [Morph](https://www.morphllm.com/context-engineering)  
  
### 🧩 Problem Decomposition  
  
* 🏗️ **Break Work Into Chunks** - When orchestrating agents, break work into independent chunks. Each agent needs clear context about its piece and how it connects to others. [CTCO](https://www.ctco.blog/posts/vibe-coding-to-agentic-engineering/)  
  
* 📦 **Batch Related Work** - Group similar tasks together to maximize context efficiency. [Aditya Bawankule](https://adityabawankule.io/guides/claude-code-complete-guide)  
  
* 🔄 **Parallel Worktrees** - Use Git worktrees for parallel work without conflicts. [Aditya Bawankule](https://adityabawankule.io/guides/claude-code-complete-guide)  
  
### 🙋 Human Oversight  
  
* 👁️ **Confirm Before Acting** - Set explicit confirmation requirements for destructive or irreversible actions. [Simon Willison](https://simonwillison.net/2026/Feb/23/agentic-engineering-patterns/)  
  
* 🛡️ **Guardrails** - Implement safety checks and boundaries for agent actions.  
  
* 📊 **Observability** - Log, trace, and monitor agent sessions for debugging and quality control.  
  
---  
  
## 🛠️ Tools & Frameworks  
  
### 🤖 Coding Agents  
  
| 🏆 Tool | 🔑 Key Features | 📊 Best For |  
|---------|-----------------|-------------|  
| [Claude Code](https://claude.com/code) | Terminal-based, long-running sessions, tool execution, subagents, agent teams | Deep refactoring, complex debugging |  
| [OpenAI Codex](https://openai.com/codex) | Multi-agent parallel execution, Codex Agent Loop | Large-scale automation, enterprise |  
| [GitHub Copilot](https://github.com/features/copilot) | IDE integration, chat, agent tasks | Interactive development |  
| [Cursor](https://cursor.sh) | AI-native IDE, AI Tab, Chat, Ctrl+K | Integrated AI development |  
  
* 📈 **Model Selection** - OpenAI's Codex series optimized for code execution. Anthropic's Claude excels at reasoning. Google's Gemini 3.1 offers strong performance at half Claude's price. [Simon Willison](https://simonw.substack.com/p/agentic-engineering-patterns)  
  
* 📊 **SWE-Bench Leaders** - Claude Opus 4.6 (Thinking) leads with 79.20% on SWE-bench, followed by Gemini 3 Flash (76.20%) and GPT 5.2 (75.40%). [Vals AI](https://www.vals.ai/benchmarks/swebench)  
  
### 🏗️ Agent Frameworks  
  
* 🔗 **LangChain** - Python-based framework for building agent applications. [langchain.com](https://python.langchain.com)  
  
* 🤝 **AutoGen** (Microsoft) - Multi-agent conversation framework. [microsoft.com/autogen](https://microsoft.com/autogen)  
  
* 🦞 **OpenClaw** - Open-source autonomous coding agent. [GitHub](https://github.com/arc53/openclaw)  
  
* ⚙️ **CrewAI** - Multi-agent orchestration for complex workflows. [crewai.com](https://crewai.com)  
  
* 🌐 **Spring AI** - Enterprise Spring-based agent patterns. [Spring](https://spring.io/blog/2026/01/27/spring-ai-agentic-patterns-4-task-subagents)  
  
### 🔌 Model Context Protocol (MCP)  
  
* 🔌 **What is MCP** - Open standard by Anthropic that defines a unified way for AI agents to connect to external tools, data sources, and services. Like "USB-C for AI integrations." [Anthropic](https://www.anthropic.com/building-effective-ai-agents/mcp)  
  
* 🛠️ **MCP Servers** - Pre-built integrations for databases, APIs, and tools. [GitHub](https://docs.github.com/en/copilot/concepts/about-mcp)  
  
* 📦 **MCP Registry** - Growing ecosystem of MCP-compatible tools. [modelcontextprotocol.io](https://modelcontextprotocol.info)  
  
### 💾 Local Models  
  
* 🖥️ **Ollama** - CLI tool for running LLMs locally. [ollama.com](https://ollama.com)  
  
* 📱 **LM Studio** - Desktop app for local LLM experimentation. [lmstudio.ai](https://lmstudio.ai)  
  
* 🏠 **Jan** - Privacy-focused local AI. [jan.ai](https://jan.ai)  
  
* 🔒 **Benefits** - Data privacy, no API costs, offline capability, total control. [AI Lexicon](https://labibledelia.com/en/blog/run-ai-locally-ollama-lm-studio/)  
  
---  
  
## 🔒 Security & Safety  
  
### 🚨 OWASP Top 10 for Agentic AI (2026)  
  
1. 🗝️ **Sensitive Data Disclosure** - Agents may expose sensitive data through outputs or tool calls  
2. 🔄 **Tool Poisoning** - Compromised tools inject malicious behavior  
3. 🧠 **Memory Pollution** - Agent context manipulation through injected memories  
4. 🎭 **Prompt Injection** - External inputs override agent instructions  
5. 🔓 **Unbounded Execution** - Agents can execute unlimited actions without oversight  
6. 📦 **Dependency Confusion** - Agent dependencies can be hijacked  
7. 🦠 **Multi-Agent Malware** - Agents can spread malicious behavior  
8. 💉 **Code Injection** - Agent-generated code contains exploits  
9. 👤 **Identity Confusion** - Agents impersonate multiple identities  
10. ⚡ **Denial of Wallet** - Uncontrolled agent resource consumption  
  
[OWASP](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)  
  
### 🛡️ Security Best Practices  
  
* 🔐 **Least Privilege** - Grant agents minimum necessary permissions  
* ✅ **Input Validation** - Sanitize all inputs to agents  
* 📝 **Audit Logging** - Complete traceability of agent actions  
* 🔒 **Secret Management** - Never expose credentials to agents unnecessarily  
* 👁️ **Human Approval** - Require human confirmation for sensitive operations  
  
---  
  
## 📊 Observability & Monitoring  
  
### 📈 Key Metrics  
  
* ⏱️ **Latency** - Response time per step and overall task completion  
* 💰 **Cost** - Token usage and API costs per task  
* ✅ **Success Rate** - Task completion and quality metrics  
* 🔄 **Token Usage** - Context window utilization and efficiency  
  
### 🛠️ Observability Tools  
  
* 📊 **LangSmith** - LangChain's observability platform  
* 📈 **Datadog** - AI observability and monitoring  
* 🔍 **OpenTelemetry** - Open standard for tracing agents  
* 📉 **AgentOps** - Agent-specific monitoring  
  
### 🎯 Production Considerations  
  
* 📝 **Trace Tool Calls** - Every LLM call, tool execution, and decision needs logging  
* 💾 **Checkpoint State** - Save agent state for recovery and debugging  
* 📋 **Cost Alerts** - Set thresholds to prevent runaway spending  
* 🔔 **Quality Evaluation** - Automated assessment of agent outputs  
  
---  
  
## 📚 Key Research & Papers  
  
### 🔬 Foundational Papers  
  
* 📄 **[Agentic Software Engineering: Foundational Pillars and a Research Roadmap](https://arxiv.org/abs/2509.06216)** - Establishes ASE as a research area, identifies key pillars and future directions.  
  
* 📄 **[Toward Agentic Software Engineering Beyond Code](https://arxiv.org/abs/2510.19692)** - Explores vision, values, and vocabulary for ASE.  
  
* 📄 **[Toward an Agentic Infused Software Ecosystem](https://arxiv.org/pdf/2602.20979)** - Argues for rethinking the software ecosystem around AI agents.  
  
* 📄 **[LLM-Based Agentic Systems for Software Engineering](https://arxiv.org/pdf/2601.09822)** - Challenges and opportunities in LLM-based multi-agent SE systems.  
  
* 📄 **[Trustworthy AI Software Engineers](https://arxiv.org/html/2602.06310v1)** - What it means for AI agents to be considered software engineers.  
  
* 📄 **[daVinci-Dev: Agent-native Mid-training for Software Engineering](https://arxiv.org/abs/2601.18418)** - Training models specifically for agentic software engineering.  
  
### 📊 Evaluation Benchmarks  
  
* 🏆 **[SWE-bench](https://www.vals.ai/benchmarks/swebench)** - Software engineering benchmark with production tasks. Claude Opus 4.6 leads at 79.20%.  
  
* 📈 **[SWE-bench Pro](https://scale.com/leaderboard/swe_bench_pro_public)** - More challenging version with 1,865 real repository tasks.  
  
* 🔬 **[SWE-rebench](https://arxiv.org/pdf/2505.20411)** - Automated pipeline for decontaminated agent evaluation.  
  
---  
  
## 📈 Key Trends (2026)  
  
### 🔄 From Single Agents to Coordinated Teams  
  
* Complex tasks now span multiple specialized agents working in parallel  
* Each agent handles a specific subtask with dedicated context  
* Integration and orchestration become critical skills  
  
### ⏱️ Long-Running Agents  
  
* Agents can now work autonomously for hours, handling multi-file refactors  
* Persistence and state management become essential  
* Checkpointing and recovery mechanisms mature  
  
### 👁️ Human Oversight Evolution  
  
* From "human in the loop" to "human on the loop" - oversight rather than constant intervention  
* Intelligent collaboration - humans focus on decisions, agents handle implementation  
* Escalation protocols for ambiguous or high-stakes decisions  
  
### 🔒 Security-First Architecture  
  
* Agent-generated code introduces new attack surfaces  
* Guardrails, sandboxing, and permission systems become standard  
* Non-human identities (NHIs) emerge as a security category  
  
### 💰 Cost Management  
  
* Token usage optimization becomes critical  
* Prompt caching reduces costs 90% for long sessions  
* Budget limits and spending alerts for production agents  
  
---  
  
## 🎯 Practical Next Steps  
  
### 🧪 For Individuals  
  
1. 📚 **Start with TDD** - Agent-friendly tests = better agent output  
2. 📁 **Build your instruction directory** - Project conventions, patterns, and rules  
3. 🎯 **Orchestrate, don't micromanage** - Give agents goals, not step-by-step instructions  
4. 📊 **Invest in observability** - Agent sessions need logging, tracing, and rollback strategies  
5. 📚 **Keep learning** - This space evolves weekly; follow Simon Willison, Anthropic engineering, and arXiv SE research  
  
### 🏢 For Teams  
  
1. 📋 **Establish Agent Guidelines** - Document approved patterns and restrictions  
2. 🔒 **Implement Security Gates** - Scan agent outputs before production  
3. 📊 **Monitor Costs** - Set budgets and track agent spending  
4. 👥 **Create Agent Librarian Role** - Maintain context and patterns for the team  
5. 🔄 **Iterate on Processes** - Learn from each agent interaction  
  
---  
  
## 📖 Bibliography & References  
  
### 📚 Books in This Vault  
  
* [🤖⚙️ The Agentic AI Engineer's Handbook](../books/the-agentic-ai-engineers-handbook.md) - Distills essential principles and actionable methodologies for designing, developing, and deploying robust agentic AI systems.  
* [🤖⚙️ Agentic Artificial Intelligence](../books/agentic-artificial-intelligence-harnessing-ai-agents-to-reinvent-business-work-and-life.md) - Argues agentic AI is the most significant tech revolution since the GUI, with early adopters gaining compounding intelligence advantages.  
* [🤖🧠⚙️💡 Building Agentic AI Systems](../books/building-agentic-ai-systems-create-intelligent-autonomous-ai-agents-that-can-reason-plan-and-adapt.md) - Provides a roadmap for developing AI agents that operate independently, make decisions, and adapt to dynamic environments.  
* [🤖🏗️ AI Engineering: Building Applications with Foundation Models](../books/ai-engineering-building-applications-with-foundation-models.md) - Comprehensive guide focusing on practical application of pre-trained models to build real-world AI products.  
* [🤖💻 Vibe Coding](../books/vibe-coding-building-production-grade-software-with-genai-chat-agents-and-beyond.md) - The definitive manifesto for building production-grade software with GenAI, shifting developer focus from syntax to intent.  
* [🤖⚙️ AI Agents in Action](../books/ai-agents-in-action.md) - Provides a proven framework for developing practical agents that handle real-world business and personal tasks.  
* [✨🤖🔗🐍 Generative AI with LangChain](../books/generative-ai-with-langchain-a-hands-on-guide-to-crafting-scalable-intelligent-systems-and-advanced-ai-agents-with-python.md) - Hands-on guide to building LLM applications and multi-agent orchestration using Python and LangGraph.  
* [💻✍️ The Art of Prompt Engineering with ChatGPT](../books/the-art-of-prompt-engineering-with-chatgpt-a-hands-on-guide.md) - Accessible practical introduction to prompt engineering for ChatGPT, moving beyond simple queries.  
* [⌨️🤖 Prompt Engineering for LLMs](../books/prompt-engineering-for-llms-the-art-and-science-of-building-large-language-model-based-applications.md) - Technical frameworks for structuring effective AI inputs to get the best results from LLMs.  
  
### 📺 Videos in This Vault  
  
* [🤖🗣️🔮✨ AI Talks: Gen AI 2026](../videos/ai-talks-gen-ai-2026-what-will-shape-the-future.md) - Covers the shift from basic code completion to agentic engineering, targeting 30-70% efficiency gains.  
* [🤖💻📈⬇️2️⃣ The 5 Levels of AI Coding](../videos/the-5-levels-of-ai-coding-why-most-of-you-wont-make-it-past-level-2.md) - Explains the five levels of AI coding capability, from autocomplete to fully autonomous agents.  
* [👨‍💻➡️🤖🧩 Beyond the IDE](../videos/beyond-the-ide-toward-multi-agent-orchestration.md) - Argues that merging becomes the bottleneck when coding is automated, requiring new coordination patterns.  
* [🖼️🤔🛠️🤖 Context Engineering for Agents](../videos/context-engineering-for-agents.md) - Categorizes context into instructions, memories, few-shot examples, tools, knowledge, and environmental feedback.  
* [🤖🔗⬆️✅ 12-Factor Agents](../videos/12-factor-agents-patterns-of-reliable-llm-applications-dex-horthy-humanlayer.md) - Draws parallels between reliable agent design and the original 12-factor app methodology.  
* [🧠🛠️🕸️🚫 No Vibes Allowed](../videos/no-vibes-allowed-solving-hard-problems-in-complex-codebases-dex-horthy-humanlayer.md) - Emphasizes the RPI (Research, Plan, Implement) workflow to enforce deliberate System 2 thinking in agents.  
* [🤖🧠⚙️👩‍💻 AI Engineering with Chip Huyen](../videos/ai-engineering-with-chip-huyen.md) - Argues AI engineering focuses on product development leveraging existing capabilities through APIs rather than building models.  
  
### 🔬 Research Papers  
  
* [Agentic Software Engineering: Foundational Pillars and a Research Roadmap](https://arxiv.org/abs/2509.06216)  
* [Toward Agentic Software Engineering Beyond Code](https://arxiv.org/abs/2510.19692)  
* [Toward an Agentic Infused Software Ecosystem](https://arxiv.org/pdf/2602.20979)  
* [LLM-Based Agentic Systems for Software Engineering](https://arxiv.org/pdf/2601.09822)  
* [Trustworthy AI Software Engineers](https://arxiv.org/html/2602.06310v1)  
* [daVinci-Dev: Agent-native Mid-training for SE](https://arxiv.org/abs/2601.18418)  
* [Agyn: Multi-Agent System for Team-Based SE](https://arxiv.org/html/2602.01465v2)  
* [Multi-Agent Coordinated Rename Refactoring](https://arxiv.org/abs/2601.00482)  
* [Configuring Agentic AI Coding Tools](https://arxiv.org/html/2602.14690v1)  
* [TDFlow: Agentic Workflows for TDD](https://arxiv.org/html/2510.23761v1)  
  
### 📰 Articles & Blogs  
  
* [Simon Willison's Agentic Engineering Patterns](https://simonwillison.net/guides/agentic-engineering-patterns/)  
* [Writing about Agentic Engineering Patterns](https://simonwillison.net/2026/Feb/23/agentic-engineering-patterns/)  
* [From Vibe Coding to Agentic Engineering - CTCO](https://www.ctco.blog/posts/vibe-coding-to-agentic-engineering/)  
* [The Complete Guide to Agentic Coding 2026 - TeamDay](https://www.teamday.ai/blog/complete-guide-agentic-coding-2026)  
* [Claude Code Context Engineering](https://claudefa.st/blog/guide/mechanics/context-engineering)  
* [Context Engineering: Complete Guide - Morph](https://www.morphllm.com/context-engineering)  
* [Effective Context Engineering - Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)  
* [How Codex is Built - Pragmatic Engineer](https://newsletter.pragmaticengineer.com/p/how-codex-is-built)  
* [Claude Code Edges OpenAI's Codex](https://visualstudiomagazine.com/articles/2026/02/26/claude-code-edges-openais-codex-in-vs-codes-agentic-ai-marketplace-leaderboard.aspx)  
* [OWASP Top 10 for Agentic Applications](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)  
* [Agentic AI Security Explained - IBM](https://www.ibm.com/think/insights/agentic-ai-security)  
* [Agentic Workflows Guide - Redis](https://redis.io/blog/what-are-agentic-workflows/)  
* [AI Observability 2026 - ZeonEdge](https://zeonedge.com/ur/blog/ai-observability-2026-monitoring-llm-applications-production)  
* [The State of Coding Agents - Feb 2026](https://calv.info/agents-feb-2026)  
* [Vibe Coding vs Agentic Engineering - Versatik](https://versatik.net/en/news/from-vibe-coding-to-agentic-engineering)  
* [Agentic Engineering Guide - Cosmo Edge](https://cosmo-edge.com/agentic-engineering-guide/)  
* [Building Production AI Agents 2026](https://zeonedge.com/nl/blog/building-production-ai-agents-2026-autonomous-systems)  
  
### 🛠️ Tools & Frameworks  
  
* [Claude Code](https://claude.com/code)  
* [OpenAI Codex](https://openai.com/codex)  
* [GitHub Copilot](https://github.com/features/copilot)  
* [Cursor](https://cursor.sh)  
* [LangChain](https://python.langchain.com)  
* [AutoGen](https://microsoft.com/autogen)  
* [OpenClaw](https://github.com/arc53/openclaw)  
* [CrewAI](https://crewai.com)  
* [Ollama](https://ollama.com)  
* [LM Studio](https://lmstudio.ai)  
* [Model Context Protocol](https://modelcontextprotocol.io)  
  
### 📊 Benchmarks  
  
* [SWE-bench](https://www.vals.ai/benchmarks/swebench)  
* [SWE-bench Pro](https://scale.com/leaderboard/swe_bench_pro_public)  
* [SWE-bench Verified](https://epoch.ai/benchmarks/swe-bench-verified)  
  
---  
  
* 🗓️ Last Updated: 2026-03-02  
* 🔄 Research in Progress - This topic is actively being developed  
