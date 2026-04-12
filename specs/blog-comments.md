# 💬 Blog Comments — Giscus Discussion Fetching

## 🎯 Overview

📋 Fetches reader comments from GitHub Discussions via the GraphQL API for use in blog post generation.
⭐ Marks comments from priority users (series-specific) as high-priority for preferential treatment in prompts.
📦 Supports batch fetching across multiple discussion pathnames for an entire series.

## 🏗️ Architecture

### 📦 Components

- 📚 Library at haskell/src/Automation/BlogComments.hs provides comment fetching and priority flagging
- 🧪 Tests at haskell/test/Automation/BlogCommentsTest.hs (mock-based testing not included)

### 🔄 Data Flow

- 🔍 Given a series config and repo info, search GitHub Discussions by pathname
- 📡 GraphQL query fetches up to 50 discussions with their comment threads
- ⭐ Comments from the priority user are flagged as isPriority
- 📅 filterCommentsAfterLastPost in BlogPrompt.hs filters by date cutoff computed dynamically from scheduleHourPacific and the last post date

## 🔧 Key Functions

### 💾 I/O Functions

- fetchGiscusComments fetches comments for a single discussion pathname
- fetchAllSeriesComments batch fetches comments for a series with up to 50 discussions

### 📦 Types

- BlogComment record with author, body, createdAt, and isPriority fields

## 🛡️ Authentication

🔑 Requires GITHUB_TOKEN environment variable for GraphQL API access.

## 🧪 Testing

🔬 Integration tests require live GitHub API access and are typically run manually.
