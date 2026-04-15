# 🔗 Share Buttons — Social Media Sharing for Website Pages

## 📋 Overview

🔗 Share buttons allow readers to easily share website pages on social media platforms, via text message, email, or by copying the link.

## 🎯 Goals

- 🚀 Make it effortless for readers to share content they enjoy
- 🔒 Respect reader privacy: no third-party tracking scripts or SDKs
- ⚡ Stay lightweight: use intent URLs and native URI schemes
- 🎨 Maintain visual consistency with the Solarized theme
- 🧩 Follow the existing Quartz component architecture
- 📱 Work well on both desktop and mobile devices

## 🏗️ Architecture

### 🧱 Component Structure

- 📦 `quartz/components/ShareButtons.tsx` — the Quartz component rendering share button markup
- 🎨 `quartz/components/styles/shareButtons.scss` — styles for the share button layout
- ⚙️ `quartz/components/scripts/shareButtons.inline.ts` — client-side JavaScript for Mastodon instance handling and SPA navigation

### 🔧 Intent URL Patterns

| 🌐 Platform | 🔗 URL Pattern | 📝 Notes |
|---|---|---|
| 🦋 Bluesky | `https://bsky.app/intent/compose?text={text}` | URL included in text body |
| 🐘 Mastodon | `https://{instance}/share?text={text}` | User provides instance; saved in localStorage |
| 🐦 Twitter/X | `https://twitter.com/intent/tweet?text={text}&url={url}` | Separate text and URL parameters |
| 💬 SMS | `sms:?&body={text}` | Native URI scheme; opens messaging app |
| 📧 Email | `mailto:?subject={title}&body={text}` | Future phase |
| 🔗 Copy Link | JavaScript clipboard API | Future phase |
| 📲 Native Share | Web Share API | Future phase; progressive enhancement for mobile |
| 📘 Facebook | `https://www.facebook.com/sharer/sharer.php?u={url}` | Future phase |
| 💼 LinkedIn | `https://www.linkedin.com/sharing/share-offsite/?url={url}` | Future phase |
| 🟠 Reddit | `https://www.reddit.com/submit?url={url}&title={title}` | Future phase |
| 📱 WhatsApp | `https://wa.me/?text={text}` | Future phase |
| ✈️ Telegram | `https://t.me/share/url?url={url}&text={text}` | Future phase |

### 📝 Default Share Message

The default message format is the page title followed by the page URL:

```
{title}

{url}
```

For Twitter, the text and URL are sent as separate parameters so Twitter can format them nicely.

### 🐘 Mastodon Instance Handling

1. 🖱️ User clicks Share on Mastodon
2. 🔍 Check localStorage for a saved Mastodon instance
3. ✅ If saved: open the share URL in a new tab
4. ❓ If not saved: show a browser prompt asking for the instance domain
5. 💾 Save the instance to localStorage for future use
6. 🔄 Allow changing the saved instance by holding Shift while clicking

### 📍 Layout Placement

🔽 The share buttons appear in the `afterBody` section of the page layout, positioned before Graph and Backlinks, so readers see them immediately after finishing the content.

## 🚀 Implementation Phases

### ✅ Phase 1 (This PR)

- 🦋 Bluesky
- 🐘 Mastodon
- 🐦 Twitter/X
- 💬 SMS/Text Message

### 🔮 Phase 2

- 📧 Email
- 🔗 Copy Link
- 📲 Native Share (Web Share API)

### 🔮 Phase 3

- 📘 Facebook
- 💼 LinkedIn
- 🟠 Reddit
- 📱 WhatsApp
- ✈️ Telegram

## 🔒 Security Considerations

- 🚫 No third-party JavaScript SDKs loaded
- 🚫 No tracking pixels or analytics from social platforms
- ✅ All external links use `rel="noopener noreferrer"` and `target="_blank"`
- ✅ All user input (share text) is URL-encoded to prevent injection
- ✅ Mastodon instance input is validated before use

## ♿ Accessibility

- 🏷️ Each button has an `aria-label` describing its purpose
- 🎯 Buttons are focusable and keyboard-navigable
- 🔤 Visual labels accompany icons for clarity
