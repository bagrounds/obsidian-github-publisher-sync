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
updated: 2026-05-04T05:26:48
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