---
share: true
aliases:
  - ☁️🛡️ Cloudflare Tunnel (cloudflared)
title: ☁️🛡️ Cloudflare Tunnel (cloudflared)
URL: https://bagrounds.org/software/cloudflare-tunnel
---
[Home](../index.md) > [Software](./index.md)  
# [☁️🛡️ Cloudflare Tunnel (cloudflared)](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps)  
  
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
