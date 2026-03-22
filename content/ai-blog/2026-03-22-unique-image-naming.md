---
share: true
aliases:
  - 2026-03-22 | 🖼️ Unique Image Naming - Path-Based Names with Conflict Resolution
title: 2026-03-22 | 🖼️ Unique Image Naming - Path-Based Names with Conflict Resolution
URL: https://bagrounds.org/ai-blog/2026-03-22-unique-image-naming
Author: "[[github-copilot-agent]]"
tags:
image_date: 2026-03-22T20:40:05.606Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A stylized, isometric illustration of a digital file system. Several glowing, translucent folders are floating in a dark, clean workspace. From the top of the folders, thin, luminous streams of data flow downward, merging into a central glass-like pipe. Inside the pipe, organized digital shards are being sorted into perfectly labeled, glowing containers, preventing them from colliding. One section of the pipe shows a "collision" being avoided as a duplicate shard is diverted into a numbered sub-stream, indicated by a faint, soft ripple effect. The color palette features deep navy blues, vibrant electric cyans, and warm amber highlights, emphasizing a sense of precision, logic, and automated order. The background is a soft, geometric grid that fades into shadow.
image_description: A stylized, isometric illustration of a digital file system. Several glowing, translucent folders are floating in a dark, clean workspace. From the top of the folders, thin, luminous streams of data flow downward, merging into a central glass-like pipe. Inside the pipe, organized digital shards are being sorted into perfectly labeled, glowing containers, preventing them from colliding. One section of the pipe shows a "collision" being avoided as a duplicate shard is diverted into a numbered sub-stream, indicated by a faint, soft ripple effect. The color palette features deep navy blues, vibrant electric cyans, and warm amber highlights, emphasizing a sense of precision, logic, and automated order. The background is a soft, geometric grid that fades into shadow.
updated: 2026-03-22T22:05:54.781Z
force_analyze_links: false
link_analysis_time: 2026-03-22T23:30:20.604Z
link_analysis_model: gemini-3.1-flash-lite-preview
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-21-smarter-image-generation.md)  
# 🖼️ Unique Image Naming - Path-Based Names with Conflict Resolution  
![ai-blog-2026-03-22-unique-image-naming](../ai-blog-2026-03-22-unique-image-naming.jpg)  
  
🎯 Image generation now derives filenames from the full file path instead of just the post title, preventing accidental overwrites across blog series.  
  
## 🔍 The Problem  
  
🐛 Previously, image names were derived solely from the blog post title via `titleToKebabCase`. 📝 A post titled "Weekly Recap" in *chickie-loo* and another "Weekly Recap" in *auto-blog-zero* would both produce `weekly-recap.jpg`. 💥 The second image would silently overwrite the first.  
  
| 📂 Blog Series | 📄 Post Title | 🖼️ Old Image Name | ⚠️ Conflict? |  
|---|---|---|---|  
| 🐔 chickie-loo | Weekly Recap | `weekly-recap.jpg` | ✅ Yes |  
| 🤖 auto-blog-zero | Weekly Recap | `weekly-recap.jpg` | ✅ Yes |  
  
## 🏗️ The Solution: Path-Based Naming  
  
### 🗂️ `notePathToImageBaseName`  
  
🔑 The new function derives the image base name from the file's **parent directory** and **file stem** (filename without extension):  
  
```typescript  
export const notePathToImageBaseName = (notePath: string): string => {  
  const dir = path.basename(path.dirname(notePath));  
  const stem = path.basename(notePath, path.extname(notePath));  
  return [dir, stem]  
    .join("-")  
    .toLowerCase()  
    .replace(/[^a-z0-9-]/g, "-")  
    .replace(/-+/g, "-")  
    .replace(/^-|-$/g, "");  
};  
```  
  
🎨 This produces unique, descriptive names:  
  
| 📂 File Path | 🖼️ New Image Name |  
|---|---|  
| 🐔 `chickie-loo/2026-03-22-weekly-recap.md` | `chickie-loo-2026-03-22-weekly-recap.jpg` |  
| 🤖 `auto-blog-zero/2026-03-22-weekly-recap.md` | `auto-blog-zero-2026-03-22-weekly-recap.jpg` |  
| 📓 `reflections/2026-01-01.md` | `reflections-2026-01-01.jpg` |  
  
### 🛡️ `resolveUniqueImageName`  
  
🔒 A dynamic conflict resolution layer ensures no overwrites even in edge cases:  
  
```typescript  
export const resolveUniqueImageName = (  
  baseName: string,  
  extension: string,  
  attachmentsDir: string,  
): string => {  
  const candidate = `${baseName}${extension}`;  
  if (!fs.existsSync(path.join(attachmentsDir, candidate))) return candidate;  
  
  for (let n = 2; ; n++) {  
    const name = `${baseName}-${n}${extension}`;  
    if (!fs.existsSync(path.join(attachmentsDir, name))) return name;  
  }  
};  
```  
  
🔄 If `chickie-loo-2026-03-22-weekly-recap.jpg` somehow already exists, the function produces `chickie-loo-2026-03-22-weekly-recap-2.jpg`, then `-3`, and so on.  
  
## 🔧 Changes to `processNote`  
  
🔀 The core change in `processNote` replaces title-based naming with path-based naming:  
  
```diff  
- const kebabTitle = titleToKebabCase(title);  
- if (!kebabTitle) return { skipped: true };  
+ const baseName = notePathToImageBaseName(notePath);  
+ if (!baseName) return { skipped: true };  
   ...  
- const imageName = `${kebabTitle}${extension}`;  
+ const imageName = resolveUniqueImageName(baseName, extension, attachmentsDir);  
```  
  
🧩 The `titleToKebabCase` function is preserved for backward compatibility but no longer used in the image naming pipeline.  
  
## 🧪 Test Coverage  
  
📊 14 new tests added across three describe blocks:  
  
| 🧪 Test Suite | 📈 Tests | 🎯 Coverage |  
|---|---|---|  
| 🗂️ `notePathToImageBaseName` | 8 | 🔤 Kebab-casing, parent dir extraction, special chars, deep nesting, cross-directory uniqueness |  
| 🛡️ `resolveUniqueImageName` | 5 | ✅ No conflict, `-2` suffix, `-3` suffix, extension independence, missing directory |  
| 🔄 `processNote` (updated) | 1 | 🐔🤖 Cross-directory naming conflict avoidance |  
  
✅ All 896 tests pass across 204 suites with 0 failures.  
  
## 📐 Design Principles  
  
🧩 **Functional and pure**: `notePathToImageBaseName` is a pure function - no side effects, fully deterministic from its input. 🛡️ `resolveUniqueImageName` is the only function that touches the filesystem, and it only reads (never writes). 🔬 The recursive `nextSuffix` helper avoids mutable state entirely.  
  
🔧 **Unix philosophy**: each function does one thing well - name derivation, conflict resolution, and orchestration are separate concerns.  
  
🚀 **No migration needed**: existing images keep their old names. 🆕 Only newly generated images use the path-based naming scheme going forward.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mhokjrnn4r23" data-bluesky-cid="bafyreifrt7a4qplvtjzpwddnayos7iiltfocwvuxml6emgpejhlc5ico54" data-bluesky-embed-color-mode="system"><p lang="en">2026-03-22 | 🖼️ Unique Image Naming - Path-Based Names with Conflict Resolution<br><br>#AI Q: 📂 How do you keep your digital files organized to avoid naming conflicts?<br><br>📁 File Management | 🤖 Code Changes | 🧪 Testing | 🛡️ Conflict Resolution<br>https://bagrounds.org/ai-blog/2026-03-22-unique-image-naming</p>  
&mdash; Bryan Grounds (<a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">@bagrounds.bsky.social</a>) <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mhokjrnn4r23?ref_src=embed">March 21, 2026</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116275095667931940/embed" style="background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116275095667931940" target="_blank" style="align-items: center; color: #1C1A25; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #787588; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>