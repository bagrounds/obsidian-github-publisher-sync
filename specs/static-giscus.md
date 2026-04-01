# 🔧 Static Giscus — Comment Injection for Static Sites

## 🎯 Overview

📋 Injects pre-rendered Giscus comments into static HTML pages for improved SEO and initial page load.
🏗️ Runs as a post-build step after Quartz generates the static site.
💬 Fetches comments from GitHub Discussions via GraphQL and renders them as HTML.

## 🏗️ Architecture

### 📦 Components

- 📚 Haskell library at haskell/src/Automation/StaticGiscus.hs provides comment fetching, rendering, and injection
- 🖥️ Haskell binary inject-giscus at haskell/app/InjectGiscus.hs runs as the deploy workflow entry point

### 🔄 Data Flow

- 📁 Recursively scans public directory for HTML files (including all subdirectories)
- 📡 Fetches discussions from GitHub GraphQL API
- 🎨 Renders comments as static HTML with author info and timestamps
- 💉 Injects rendered HTML before the giscus container div

## 🔧 Key Functions

### 🧊 Pure Functions

- renderStaticComment converts a comment object to HTML string
- buildCommentsMap maps discussion pathnames to their comment lists
- extractSlug reads the data-slug attribute from an HTML page body
- findGiscusDiv locates the giscus div insertion point

### 💾 I/O Functions

- fetchAllDiscussions retrieves all discussions for the repository
- injectStaticComments inserts rendered comments into an HTML page
- walkHtmlFiles recursively discovers all HTML files under a root directory
- processHtmlFiles walks a directory recursively and processes all HTML files

## 🧪 Testing

🔬 Unit tests in haskell/test/Automation/StaticGiscusTest.hs cover pure functions and file system operations.
📁 File system tests verify recursive directory traversal using temporary directories.
