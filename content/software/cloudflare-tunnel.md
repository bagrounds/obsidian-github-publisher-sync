---
share: true
aliases:
  - ☁️🛡️ Cloudflare Tunnel (cloudflared)
title: ☁️🛡️ Cloudflare Tunnel (cloudflared)
URL: https://bagrounds.org/software/cloudflare-tunnel
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-15T00:00:00Z
force_analyze_links: false
image_date: 2026-04-10T17:25:25Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A stylized, isometric illustration featuring a glowing, translucent blue tunnel connecting a small, minimalist home server icon to a larger, abstract cloud structure floating above. The tunnel is represented by a beam of light composed of digital data particles or fiber-optic strands, symbolizing a secure connection. The background is a clean, dark navy gradient, accented with soft, glowing geometric shapes and subtle circuit board patterns. A golden shield icon subtly overlays the tunnel entrance to represent security. The overall aesthetic is modern, sleek, and high-tech, utilizing a color palette of electric blues, vibrant oranges, and deep grays to evoke a sense of digital infrastructure and reliable protection.
link_analysis_version: "2"
updated: 2026-05-05T05:18:12
---
[Home](../index.md) > [Software](./index.md)  
# [☁️🛡️ Cloudflare Tunnel (cloudflared)](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps)  
![software-cloudflare-tunnel](../software-cloudflare-tunnel.jpg)  
  
## 🤖 AI Summary  
  
### 👉 What Is It?  
  
* ☁️🛡️ Cloudflare Tunnel (cloudflared) is a tool that creates a secure connection between your local server and Cloudflare's network.  
* 📱 It lets you expose local development servers to the internet without configuring firewalls or routers.  
* 🔐 Traffic is encrypted and routed through Cloudflare, adding security and DDoS protection.  
  
### 🚀 Common Use Cases  
  
* 📱 Expose local development servers to your phone for testing  
* 🌐 Share local sites with others without deploying  
* 🔒 Add Cloudflare's security layer to self-hosted services  
* 🏠 Access home network services remotely  
  
### 💻 Installation  
  
```bash  
# Download cloudflared  
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64  
  
# Make executable  
chmod +x cloudflared-linux-amd64  
  
# Run tunnel  
./cloudflared tunnel --url http://127.0.0.1:4096  
```  
  
### 🔧 Basic Usage  
  
```bash  
# Simple tunnel to local server  
cloudflared tunnel --url http://localhost:3000  
  
# Create a named tunnel  
cloudflared tunnel create my-tunnel  
cloudflared tunnel route dns my-tunnel example.example.com  
cloudflared tunnel run my-tunnel  
```  
  
### 📍 Links  
  
* [Cloudflare Zero Trust Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps)  
* [GitHub Repository](https://github.com/cloudflare/cloudflared)  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mkywqsmta22s" data-bluesky-cid="bafyreifqahx5mlv5wdgwwiaulzpquybra663pnf2okpjsipnoezn4un4fe"><p>☁️🛡️ Cloudflare Tunnel (cloudflared)  
  
#AI Q: 🌐 How do you securely access your home network from anywhere?  
  
🌐 Networking | 🔐 Security | 💻 Development | 🚀 DevOps  
https://bagrounds.org/software/cloudflare-tunnel</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mkywqsmta22s?ref_src=embed">2026-05-04T05:26:50.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116520274794890444/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116520274794890444" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>