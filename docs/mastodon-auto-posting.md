# Mastodon Auto-Posting Setup Guide

## Overview

This document covers the Mastodon integration added to the social posting pipeline.
Mastodon posts are created in parallel with Twitter and Bluesky — all three platforms
run concurrently via `Promise.allSettled()`, and each platform is optional and non-fatal.

The Mastodon embed is written to the Obsidian note as an `## 🐘 Mastodon` section
(similar to `## 🐦 Tweet` and `## 🦋 Bluesky`), using Mastodon's iframe-based oEmbed
format. Edits to the reflection note are serialized to avoid conflicts.

## Architecture

```
                                   ┌──────────────┐
                              ┌───▶│  Twitter API  │───▶ oEmbed / local embed
                              │    │  (optional)   │
┌─────────────┐   ┌────────┐  │    └──────────────┘
│  Read       │──▶│ Gemini │──┤
│  Reflection │   │ Generate│  │    ┌──────────────┐
└─────────────┘   │ Post   │  ├───▶│  Bluesky API  │───▶ oEmbed / local embed
                  └────────┘  │    │  (optional)   │
                              │    └──────────────┘
  All three post in           │
  parallel, non-fatal         │    ┌──────────────┐
                              └───▶│  Mastodon API │───▶ oEmbed / local embed
                                   │  (optional)   │
                                   └──────────────┘
```

After all platforms complete, successful embeds are written to the Obsidian note
sequentially (to avoid file write conflicts), then pushed via Obsidian Headless Sync.

## Environment Variables

### Required GitHub Actions Secrets (for Mastodon)

| Secret Name | Description | How to Obtain |
|---|---|---|
| `MASTODON_INSTANCE_URL` | Mastodon instance URL | e.g. `https://mastodon.social` or `https://fosstodon.org` |
| `MASTODON_ACCESS_TOKEN` | Mastodon access token | Settings → Development → New Application → Access Token |

Both must be set to enable Mastodon posting. If either is missing, the script
logs a message and skips Mastodon (non-fatal).

## How to Get Mastodon Credentials

### Step 1: Choose or Create a Mastodon Account

If you don't have one already, sign up on a Mastodon instance. Popular choices:

- **[mastodon.social](https://mastodon.social)** — The flagship instance run by the Mastodon team
- **[fosstodon.org](https://fosstodon.org)** — Popular with open-source and tech users
- **[hachyderm.io](https://hachyderm.io)** — Tech-focused, well-moderated
- **[infosec.exchange](https://infosec.exchange)** — Information security community

### Step 2: Create an Application and Get an Access Token

1. Log in to your Mastodon instance (e.g. `https://mastodon.social`)
2. Go to **Preferences** (gear icon or `/settings/preferences`)
3. Click **Development** in the left sidebar (or navigate to `/settings/applications`)
4. Click **New Application**
5. Fill in the form:
   - **Application name**: `social-posting-bot` (or any name you like)
   - **Application website**: `https://bagrounds.org` (optional, your website)
   - **Redirect URI**: `urn:ietf:wg:oauth:2.0:oob` (keep default)
   - **Scopes**: Check at minimum:
     - ✅ `write:statuses` (required — to create posts)
     - ✅ `read:statuses` (recommended — for oEmbed/verification)
   - Uncheck everything else to follow the principle of least privilege
6. Click **Submit**
7. You'll be taken to the application details page. Copy the **Access Token** value.
   - ⚠️ This is the only value you need — you do NOT need the Client Key or Client Secret
   - ⚠️ The access token is shown once. If you lose it, you can regenerate it from the same page.

### Step 3: Set GitHub Actions Secrets

1. Navigate to your GitHub repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add two secrets:

| Name | Value |
|---|---|
| `MASTODON_INSTANCE_URL` | Your Mastodon instance URL (e.g. `https://mastodon.social`) — include the `https://` prefix, no trailing slash |
| `MASTODON_ACCESS_TOKEN` | The access token from step 2 |

### Step 4: Test by Manually Triggering the Workflow

1. Go to **Actions** tab in your repository
2. Select the **Tweet Daily Reflection** workflow
3. Click **Run workflow**
4. Optionally set:
   - **Reflection date**: A date with an existing reflection (e.g. `2026-03-07`)
   - **Dry run**: Leave unchecked for a real post
5. Click **Run workflow** and monitor the logs

The logs will show:
```
🐘 Posting to Mastodon...
  📡 Mastodon: creating post on https://mastodon.social...
✅ Mastodon post created: https://mastodon.social/@yourhandle/123456789
🔗 Fetching Mastodon embed code...
📋 Got Mastodon embed HTML (xxx chars)
```

## Technical Details

### Mastodon API

- **Library**: [`masto`](https://www.npmjs.com/package/masto) (v7.10.x) — TypeScript Mastodon API client
- **Endpoint**: `POST /api/v1/statuses` with `Authorization: Bearer <token>`
- **Character limit**: 500 characters (default, instance-configurable)
- **Idempotency**: Mastodon supports `Idempotency-Key` header (stored for 1 hour)
- **oEmbed**: `GET /api/oembed?url=<post_url>` on the same instance

### Embed Format

Mastodon embeds use an iframe format (unlike Twitter's blockquote or Bluesky's blockquote):

```html
<iframe src="https://mastodon.social/@user/123456789/embed"
        class="mastodon-embed"
        style="max-width: 100%; border: 0"
        width="400"
        allowfullscreen="allowfullscreen"></iframe>
<script src="https://mastodon.social/embed.js" async="async"></script>
```

The `embed.js` script handles responsive sizing and dark mode support.

### Error Handling

- If Mastodon credentials are not set, the script logs and skips (non-fatal)
- If the Mastodon API returns an error, the script logs the error and continues
- If oEmbed fails, the script generates a local iframe embed as a fallback
- Mastodon posting runs in parallel with Twitter and Bluesky — one platform
  failing doesn't affect the others

### Idempotency

- The script checks for an existing `## 🐘 Mastodon` section in the reflection note
- If the section already exists, Mastodon posting is skipped for that note
- The overall pipeline skips if all three sections exist

## References

- [Mastodon API Documentation — Statuses](https://docs.joinmastodon.org/methods/statuses/)
- [Mastodon API Documentation — oEmbed](https://docs.joinmastodon.org/methods/oembed/)
- [Mastodon API Documentation — Authentication](https://docs.joinmastodon.org/client/token/)
- [masto.js — TypeScript Mastodon API Client](https://github.com/neet/masto.js)
- [masto npm package](https://www.npmjs.com/package/masto)
