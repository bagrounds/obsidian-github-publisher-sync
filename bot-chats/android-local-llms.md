---
share: true
aliases:
  - 🤖📱🧠 Android Local LLMs
title: 🤖📱🧠 Android Local LLMs
URL: https://bagrounds.org/bot-chats/android-local-llms
---
[Home](../index.md) > [Bot Chats](./index.md)  
# 🤖📱🧠 Android Local LLMs  
## [Meta.ai](https://www.meta.ai) Prompt  
> I want to run a local 🏡 [llm](../topics/large-language-models.md) on my android 🤖 in order to power AI 🧠 apps on my android 🤖. For example, I want to use an [obsidian](../software/obsidian.md) 📝 plugin that calls to an LLM server to power text generation ✍️. What's the easiest way to do this? Unless there's an app that sets this up already, I'm thinking it might be easiest to run the [Ollama](../software/ollama.md) 🦙 server in [termux](../software/termux.md), expose the server to the android 🤖 os somehow (port forward or something may be necessary, not sure) and then use the local network interface as the web addresses when configuring my obsidian 📝 plugin. I'm not 100% sure if that's possible, but if it is, it's likely a bit of a pain 😫 to set up. Ideally, there's some android 🤖 app that will already handle this for me (with the constraint being that it runs local llms - I don't want to make calls to a cloud ☁️ service). What do you think?  
  
## Response  
💡 Running a local LLM on your Android device is an innovative idea. While there might not be a straightforward app that sets this up for you, your proposed approach using Termux and the ollama server is feasible. Here's a breakdown of the steps:  
  
### 💻 Option 1: Termux and ollama server  
1. ⬇️ **Install Termux**: Download and install Termux from the Google Play Store.  
2. 📦 **Install necessary packages**: Install the required packages, such as git, python, and pip, using the pkg command in Termux.  
3. 🐑 **Clone and set up ollama**: Clone the ollama repository, install the dependencies, and configure the server according to the documentation.  
4. 📡 **Expose the server**: Use the termux-socket package to expose the ollama server to the Android OS. You might need to use iptables or adb forward to forward the port.  
5. ⚙️ **Configure your Obsidian plugin**: Use the local network interface (e.g., http://localhost:port or http://127.0.0.1:port) as the web address when configuring your Obsidian plugin.  
  
### 📱 Option 2: Android apps with local LLM support  
🤔 While there might not be an app that exactly fits your requirements, some apps offer local LLM capabilities:  
1. 🦙 **LLaMA**: A mobile app that allows you to run LLaMA models locally on your device. However, it's unclear if it supports custom plugins or APIs.  
2. ⚡ **TensorFlow Lite**: A mobile app that enables you to run TensorFlow Lite models, including some LLMs, locally on your device. However, it requires significant technical expertise to set up and integrate with your Obsidian plugin.  
  
⚠️ Before proceeding, consider the following:  
- 📉 **Performance**: Running a local LLM on your Android device might impact performance, especially if you're using a resource-intensive model.  
- 🧠 **Model size and complexity**: Choose a model that's optimized for mobile devices and has a reasonable size and complexity to ensure smooth performance.  
- 🔋 **Power consumption**: Running a local LLM can consume significant power, so be mindful of your device's battery life.  
  
👍 If you're comfortable with the technical aspects and potential performance implications, proceed with the Termux and ollama server approach. 🔎 Alternatively, explore the Android apps mentioned above to see if they meet your requirements.