---
share: true
aliases:
  - 📦⬅️🌯⬅️🧱 Monadic Parsers at the Input Boundary
title: 📦⬅️🌯⬅️🧱 Monadic Parsers at the Input Boundary
URL: https://bagrounds.org/videos/monadic-parsers-at-the-input-boundary
Author:
Platform:
Channel: Hasgeek TV
tags:
youtube: https://youtu.be/LLkbzt4ms6M
updated: 2026-03-15T14:10:58.318Z
---
[Home](../index.md) > [Videos](./index.md)  
# 📦⬅️🌯⬅️🧱 Monadic Parsers at the Input Boundary  
![Monadic Parsers at the Input Boundary](https://youtu.be/LLkbzt4ms6M)  
  
## 🤖 AI Summary  
  
* 🛡️ Monadic parsers operate at the isolation boundary where processes encounter external byte streams to turn unstructured data into typed structures. \[[00:29](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=29)]  
* 🐛 Most software bugs and security vulnerabilities stem from processes misbehaving when encountering unexpected surprises in input byte streams. \[[01:24](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=84)]  
* 💎 Parsing should produce data structures that make illegal states unrepresentable, providing a proof that the input is valid. \[[04:15](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=255)]  
* 🏗️ A parsing monad requires exactly three features: tracking position in the input, choosing alternate branches, and the ability to fail. \[[04:44](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=284)]  
* 🧩 Parser combinators are normal functions that take parsers as arguments and return new parsers, allowing for highly composable code. \[[08:39](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=519)]  
* 📖 Unlike regular expressions which are often write-only and arcane, monadic parsers mirror the structure of formal specifications like RFC 5322. \[[15:16](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=916)]  
* 🌳 Regular expressions cannot handle recursive or tree-like structures such as HTML or JSON, whereas monadic parsers handle recursion naturally. \[[18:21](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=1101)]  
* 🚀 While PureScript monadic parsers are slower than native JavaScript regular expressions, Haskell libraries like Attoparsec offer comparable speed. \[[23:16](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=1396)]  
* 🧠 Monadic parsers with monad transformers can parse context-sensitive grammars by bringing state into the parsing computation. \[[32:42](http://www.youtube.com/watch?v=LLkbzt4ms6M&t=1962)]  
  
## 🤔 Evaluation  
  
* ⚖️ The speaker advocates for Monadic Parsing as a superior alternative to Regular Expressions for complex data, which aligns with the Parse, don't validate philosophy popularized by Alexis King.  
* 🔍 While the talk highlights the power of parser combinators, it is important to note that for high-performance systems, parser generators like LALR or specialized binary decoders are often preferred in industry settings.  
* 🗺️ Topics for further exploration include the performance trade-offs of different parsing libraries in garbage-collected versus manual memory management languages.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 🧐 Q: What is the primary advantage of monadic parsers over regular expressions?  
  
🚀 A: Monadic parsers are written in a host language like PureScript or Haskell, making them highly readable, composable, and capable of parsing recursive structures like JSON which regular expressions cannot handle.  
  
### ⏱️ Q: Are monadic parsers slower than regular expressions?  
  
🐢 A: In JavaScript environments, they are often ten times slower because they lack the highly optimized JIT compilers dedicated to regular expressions, though Haskell implementations can be significantly faster.  
  
### 🧩 Q: Can monadic parsers be used for binary data?  
  
📂 A: Yes, monadic parsers are not limited to text and can be applied to any byte stream, including binary formats, using specialized libraries like purescript-parsing-dataview.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
  
* 📘 Introduction to Functional Programming by Richard Bird and Philip Wadler explores the foundational concepts of functional programming and monads.  
* 📘 Programming in Haskell by Graham Hutton provides a comprehensive guide to Haskell including chapters dedicated to the mechanics of monadic parsing.  
* [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md)  
* [👨‍🏫🎉👍✨ Learn You a Haskell for Great Good!](../books/learn-you-a-haskell-for-great-good.md)  
  
### 🆚 Contrasting  
  
* 📘 Mastering Regular Expressions by Jeffrey Friedl details the high-performance world of regex engines and their optimization across different programming environments.  
* 📘 Compilers: Principles, Techniques, and Tools by Alfred Aho and Jeffrey Ullman focuses on traditional compiler construction and formal grammar parsing techniques like Lex and Yacc.  
  
### 🎨 Creatively Related  
  
* 📘 Syntactic Structures by Noam Chomsky introduces the chomsky hierarchy mentioned in the video which classifies the complexity of formal grammars.  
* [♾️📐🎶🥨 Gödel, Escher, Bach: An Eternal Golden Braid](../books/godel-escher-bach.md) by Douglas Hofstadter explores the nature of recursive systems and formal logic in a way that relates to the structure of parsers.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mgym2jnvpt25" data-bluesky-cid="bafyreia3yi732whsybvtkwaxlzpf3ixhabgzydsuepurxb4zjqvdnxktta"><p>📦⬅️🌯⬅️🧱 Monadic Parsers at the Input Boundary  
  
🛡️ Data Validation | 🧩 Parser Combinators | 🌳 Recursive Structures | 📚 Functional Programming  
https://bagrounds.org/videos/monadic-parsers-at-the-input-boundary</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mgym2jnvpt25?ref_src=embed">2026-03-14T04:34:39.626Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116225663242522133/embed" style="background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116225663242522133" target="_blank" style="align-items: center; color: #1C1A25; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #787588; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>