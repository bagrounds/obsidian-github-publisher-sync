# 🔧 Static Giscus — Comment Injection for Static Sites

## 🎯 Overview

📋 Injects pre-rendered Giscus comments into static HTML pages for improved SEO and initial page load.
🏗️ Runs as a post-build step after Quartz generates the static site.
💬 Fetches comments from GitHub Discussions via GraphQL and renders them as HTML.

## 🏗️ Architecture

### 📦 Components

- 📚 Library at scripts/lib/static-giscus.ts provides comment fetching, rendering, and injection
- 🖥️ CLI at scripts/inject-static-giscus.ts runs as a standalone entry point

### 🔄 Data Flow

- 📁 Scans public HTML files for Giscus comment containers
- 📡 Fetches discussions from GitHub GraphQL API
- 🎨 Renders comments as static HTML with author info and timestamps
- 💉 Injects rendered HTML into the page DOM

## 🔧 Key Functions

### 🧊 Pure Functions

- renderStaticComment converts a comment object to HTML string
- buildCommentsMap maps discussion pathnames to their comment lists

### 💾 I/O Functions

- fetchAllDiscussions retrieves all discussions for the repository
- injectStaticComments inserts rendered comments into an HTML page
- processHtmlFiles walks a directory and processes all HTML files

## 🧪 Testing

🔬 Integration tests require the built static site and GitHub API access.
