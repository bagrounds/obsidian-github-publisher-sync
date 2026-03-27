# 🤖 Gemini API — AI Model Client and Authentication

## 🎯 Overview

📡 Provides a typed client for the Google Gemini generative AI API with retry, model fallback chains, and grounding support.
🔐 Includes GCP service account JWT authentication for accessing Imagen and other Google Cloud APIs.
📊 Quota checking for monitoring inference capacity.
🔄 Exponential backoff retry with configurable transient error detection.

## 🏗️ Architecture

### 📦 Components

- 📚 Gemini Client at scripts/lib/gemini.ts provides content generation with model fallback
- 🔐 GCP Auth at scripts/lib/gcp-auth.ts handles JWT creation and OAuth token exchange
- 📊 Quota Checker at scripts/lib/gemini-quota.ts fetches model catalog and quota info
- 🔄 Retry at scripts/lib/retry.ts provides exponential backoff for transient HTTP errors
- ⏱️ Timer at scripts/lib/timer.ts tracks pipeline timing for performance monitoring

### 🔄 Data Flow

- 🧠 Caller provides prompt text, model chain, and optional grounding config
- 📡 generateContentWithFallback tries each model in order
- 🔄 Each model attempt uses withRetry for transient errors (429, 502, 503, 504)
- 🌐 If grounding fails with quota error, retries without grounding on same model
- ⏭️ On definitive failure, moves to next model in chain
- 📦 Returns generated text or throws after exhausting all models

## 🔧 Key Functions

### 🧊 Pure Functions

- isRetriableError detects transient HTTP codes and Gemini error messages
- isQuotaError detects 429 and RESOURCE_EXHAUSTED responses
- parseGeminiResponse extracts text from nested Gemini API response structure

### 💾 I/O Functions

- generateContent makes a single Gemini API call
- generateContentWithFallback tries model chain with retry and grounding fallback
- createJwt builds RS256-signed JWT for GCP authentication
- getAccessToken exchanges JWT for OAuth bearer token
- fetchModelCatalog lists available Gemini models
- checkQuota queries quota status for a specific model

## 🔐 GCP Authentication

- 📋 Parses service account JSON (supports base64-encoded keys)
- 🔑 Creates RS256-signed JWT with iat/exp claims
- 🔄 Exchanges JWT for OAuth access token via Google token endpoint
- ⏰ Tokens are requested fresh for each operation (no caching)

## 🔄 Retry Configuration

- 📈 Exponential backoff: base delay times 2 to the power of attempt number
- 🔢 Default: 3 retries with 2 second base delay (2s, 4s, 8s)
- 📡 Transient codes: 429, 500, 502, 503, 504
- 🔧 Configurable callback for retry logging

## 🧪 Testing

🔬 Tests across multiple suites covering retry logic, error classification, Gemini response parsing, and quota error detection.
