# 🤖 Gemini API — AI Model Client and Authentication

## 🎯 Overview

📡 Provides a typed client for the Google Gemini generative AI API with retry, model fallback chains, and grounding support.
🔐 Includes GCP service account JWT authentication for accessing Imagen and other Google Cloud APIs.
📊 Quota checking for monitoring inference capacity.
🔄 Exponential backoff retry with configurable transient error detection.

## 🏗️ Architecture

### 📦 Components

- 📚 Gemini Client at haskell/src/Automation/Gemini.hs provides content generation with model fallback
- 🔐 GCP Auth at haskell/src/Automation/GcpAuth.hs handles JWT creation and OAuth token exchange
- 📊 Quota Checker at haskell/src/Automation/GeminiQuota.hs fetches model catalog and quota info
- 🔄 Retry at haskell/src/Automation/Retry.hs provides exponential backoff for transient HTTP errors
- ⏱️ Timer at haskell/src/Automation/Timer.hs tracks pipeline timing for performance monitoring

### 🔄 Data Flow

- 🧠 Caller provides prompt text, optional system instruction, model chain, and optional grounding config
- 📡 generateContentWithFallback tries each model in order
- 📋 When a system instruction is provided, `generateContent` checks `supportsSystemInstruction` for the current model: Gemini models receive the system instruction via the API `system_instruction` field; Gemma models receive it concatenated into the user prompt for compatibility
- 🔄 Each model attempt uses withRetry for transient errors (429, 502, 503, 504)
- ⏭️ On definitive failure (including quota exhaustion), moves to next model in chain
- 📦 Returns generated text and grounding sources, or throws after exhausting all models

## 🔧 Key Functions

### 🧊 Pure Functions

- isRetriableError detects transient HTTP codes and Gemini error messages
- isQuotaError detects 429 and RESOURCE_EXHAUSTED responses
- extractText extracts text from nested Gemini API response structure
- extractGroundingSources extracts grounding sources from candidates groundingMetadata
- formatGroundingSources formats grounding sources as a markdown section with deduplicated links
- buildRequestBody builds the JSON request body, including the google_search tool when grounding is enabled

### 💾 I/O Functions

- generateContent makes a single Gemini API call, returning Response with text and grounding sources
- generateContentWithFallback tries model chain with retry and grounding fallback
- createJwt builds RS256-signed JWT for GCP authentication
- getAccessToken exchanges JWT for OAuth bearer token
- fetchModelCatalog lists available Gemini models
- checkQuota queries quota status for a specific model

## 🌐 Grounding Support

- 📡 When a series config sets enableGrounding to true, blog posts are generated with Google Search grounding enabled
- 🏷️ Grounding is configured through GenerationConfig by setting searchGrounding to true, keeping request configuration cohesive
- 🔗 Grounded responses include groundingChunks in the response metadata containing web URIs and titles
- 🏷️ Source URLs are validated using the Url domain type via mkUrl, ensuring only http and https URLs are ever included in a GroundingSource
- 🧹 Sources are deduplicated by URL preserving first occurrence order
- 📝 A Sources section is appended to blog posts listing all grounding sources as markdown links prefixed with the globe emoji
- 🔄 formatGroundingSources returns Nothing for empty lists and Just for non-empty lists, letting callers decide whether to include the section
- 🛑 If grounding fails, the entire model attempt fails and the next model in the chain is tried; there is no silent fallback to an ungrounded post
- ✅ Enabled for: the-noise, systems-for-public-good, positivity-bias, convergence

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

🔬 Tests across multiple suites covering retry logic, error classification, Gemini response parsing, quota error detection, grounding source extraction, and grounding source formatting.
