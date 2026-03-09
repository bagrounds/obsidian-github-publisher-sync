# Platform Disable Environment Variables

## Overview

Each social media platform (Twitter, Bluesky, Mastodon) can be explicitly disabled
via environment variables, even when valid credentials are present. This is useful
when a platform's API becomes unreliable, a free tier is discontinued, or you simply
want to pause posting to a specific platform without removing credentials.

## Environment Variables

| Variable | Effect | Accepted Values |
|---|---|---|
| `DISABLE_TWITTER` | Disable Twitter/X posting | `true`, `1`, `yes` (case-insensitive) |
| `DISABLE_BLUESKY` | Disable Bluesky posting | `true`, `1`, `yes` (case-insensitive) |
| `DISABLE_MASTODON` | Disable Mastodon posting | `true`, `1`, `yes` (case-insensitive) |

Any other value (including empty string, `false`, `0`, `no`) keeps the platform enabled.

## How It Works

The `isPlatformDisabled(envVar)` function checks the value of the given environment
variable. If it matches one of the truthy values (`true`, `1`, `yes` — case-insensitive,
whitespace-trimmed), the platform is disabled.

In `validateEnvironment()`, each platform is disabled if:
1. The `DISABLE_*` env var is set to a truthy value, **OR**
2. The platform's required credentials are not all present.

When a platform is disabled via env var, a log message is emitted:
```
🚫 Twitter disabled via DISABLE_TWITTER env var
```

The platform's credentials object is returned as `null`, which causes all downstream
code (in `main()` and `getConfiguredPlatforms()`) to skip that platform entirely.

## GitHub Actions Configuration

The workflow (`.github/workflows/tweet-reflection.yml`) passes these env vars from
GitHub repository variables:

```yaml
env:
  DISABLE_TWITTER: ${{ vars.DISABLE_TWITTER || '' }}
  DISABLE_BLUESKY: ${{ vars.DISABLE_BLUESKY || '' }}
  DISABLE_MASTODON: ${{ vars.DISABLE_MASTODON || '' }}
```

### Setting a Repository Variable

1. Navigate to your repository → **Settings** → **Secrets and variables** → **Actions**
2. Click the **Variables** tab
3. Click **New repository variable**
4. Set the name (e.g. `DISABLE_TWITTER`) and value (`true`)
5. Click **Add variable**

To re-enable: delete the variable or set its value to `false` or an empty string.

## Interaction with Credentials

| Credentials Present | DISABLE_ Var Set | Platform Enabled? |
|---|---|---|
| ✅ Yes | ❌ Not set / empty / `false` | ✅ **Enabled** |
| ✅ Yes | ✅ `true` / `1` / `yes` | ❌ **Disabled** |
| ❌ No | ❌ Not set | ❌ **Disabled** (no credentials) |
| ❌ No | ✅ `true` | ❌ **Disabled** (both reasons) |

## Architecture

```
Environment Variables
        │
        ▼
  isPlatformDisabled()  ──▶  true?  ──▶  platform = null (skip)
        │
        ▼ false
  Check credentials  ──▶  missing?  ──▶  platform = null (skip)
        │
        ▼ present
  Return credential object  ──▶  platform enabled
```

Both `main()` in `tweet-reflection.ts` and `getConfiguredPlatforms()` in `auto-post.ts`
use `validateEnvironment()`, so the disable logic applies everywhere automatically.

## Testing

20 tests cover the disable functionality:
- 13 tests for `isPlatformDisabled()` (truthy/falsy values, case-sensitivity, whitespace)
- 7 tests for `validateEnvironment()` disable scenarios (per-platform, all platforms, edge cases)

Run tests with:
```bash
npx tsx --test scripts/tweet-reflection.test.ts
```
