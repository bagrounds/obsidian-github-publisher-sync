# Migration Guide: Enveloppe → Git Sync

## Overview

This guide walks through migrating from the Enveloppe (GitHub Publisher) Obsidian plugin
to a git-based workflow where raw vault files are synced directly and CI handles content
transformation.

### Architecture: Before & After

```
BEFORE (Enveloppe)                    AFTER (Git Sync + CI)
┌──────────────┐                      ┌──────────────┐
│ Obsidian     │                      │ Obsidian     │
│ (mobile)     │                      │ (mobile)     │
│              │                      │              │
│ Write notes  │                      │ Write notes  │
│      ↓       │                      │      ↓       │
│ Enveloppe    │                      │ Git commit   │
│ transforms:  │                      │ & push       │
│ • wikilinks  │                      │ (5-10 sec)   │
│ • hard breaks│                      └──────┬───────┘
│ • filter     │                             │
│ (30-60 sec)  │                             ↓
└──────┬───────┘                      ┌──────────────┐
       │                              │ GitHub CI    │
       ↓                              │              │
┌──────────────┐                      │ Transform:   │
│ GitHub       │                      │ • wikilinks  │
│ content/     │                      │ • hard breaks│
│              │                      │ • filter     │
│ Quartz build │                      │      ↓       │
│      ↓       │                      │ Quartz build │
│ GitHub Pages │                      │      ↓       │
└──────────────┘                      │ GitHub Pages │
                                      └──────────────┘
```

---

## Phase 1: Set Up Git Sync (Your Next Step)

### 1.1 Install the Obsidian Git Plugin

1. In Obsidian: **Settings → Community plugins → Browse**
2. Search for **"Git"** (by Vinzent03)
3. Install and enable

### 1.2 Configure the Plugin

**Option A: Sync entire vault to `vault/` subdirectory** (recommended)

This keeps raw vault files separate from the existing transformed content:

1. Clone this repository to your computer (if not already):

   ```bash
   git clone https://github.com/bagrounds/obsidian-github-publisher-sync.git
   ```

2. Set up a symlink or configure Obsidian Git to push to the `vault/` directory:
   - In the Git plugin settings, set **Custom base path**: `vault/`
   - Or configure a separate branch and merge strategy

**Option B: Use a separate branch**

Push raw vault content to a `vault-raw` branch:

1. In Git plugin settings:
   - **Branch**: `vault-raw`
   - **Auto commit-and-sync interval**: 10 minutes (or your preference)
   - **Pull on startup**: enabled

The CI workflow will read from this branch.

### 1.3 Configure `.gitignore` in Your Vault

The `vault/.gitignore` already excludes Obsidian internals:

```
.obsidian/
.trash/
.DS_Store
```

Add any personal exclusions as needed.

### 1.4 First Sync

1. Open Obsidian
2. Use the command palette: **Git: Commit all and push**
3. Verify files appear in `vault/` on GitHub

---

## Phase 2: CI Transformation (Already Built)

The CI transformation pipeline is already implemented:

- **Transformer**: `scripts/lib/vault-transform.ts` — converts wikilinks, adds hard breaks
- **CLI**: `scripts/transform-vault.ts` — processes all vault files
- **Workflow**: `.github/workflows/transform-vault.yml` — runs on push to `vault/`

### What the Transformer Does

| Vault (raw)                             | Content (transformed)                                             |
| --------------------------------------- | ----------------------------------------------------------------- |
| `[[note\|Display]]`                     | `[Display](./note.md)`                                            |
| `[[folder/note\|Text]]`                 | `[Text](../folder/note.md)` (relative path)                       |
| `[[/index\|Home]]`                      | `[Home](../index.md)` (absolute → relative)                       |
| `[[note#Heading\|Text]]`                | `[Text](./note.md#Heading)`                                       |
| `[[note#Heading With Spaces]]`          | `[note > Heading With Spaces](./note.md#Heading%20With%20Spaces)` |
| `![[image.png]]`                        | `![image.png](./image.png)`                                       |
| `![[image.png\|Alt Text]]`              | `![Alt Text](./image.png)`                                        |
| Lines without trailing spaces           | Lines with `  ` (hard breaks)                                     |
| Files with `share: false` or no `share` | Excluded                                                          |
| Frontmatter `Author: "[[name]]"`        | Preserved as-is (wikilinks in frontmatter stay)                   |
| Standard markdown links `[text](url)`   | Preserved as-is                                                   |
| Code blocks with `[[wikilinks]]`        | Preserved as-is (not transformed)                                 |

### Test Locally

```bash
# Transform vault files
npx tsx scripts/transform-vault.ts --vault vault/ --output /tmp/content-ci/

# Compare with existing content
npx tsx scripts/compare-content.ts --dir1 content/ --dir2 /tmp/content-ci/
```

---

## Phase 3: Compare & Validate

Once you have vault files synced and CI transforming them:

### 3.1 Run the Comparison

The comparison tool runs automatically in CI, or locally:

```bash
npx tsx scripts/compare-content.ts --dir1 content/ --dir2 content-ci/
```

It reports:

- **Matching files**: identical content ✅
- **Only in dir1**: files Enveloppe published but vault doesn't have
- **Only in dir2**: files in vault but not published by Enveloppe
- **Differing**: files that exist in both but have different content

### 3.2 Investigate Differences

Common expected differences:

- **Auto-blog files**: generated by CI, not from vault
- **Social embed sections**: added by the social posting pipeline
- **Trailing whitespace**: Enveloppe may handle slightly differently
- **Broken links**: Enveloppe has known bugs (e.g., `../../tower-of-hanoi.md`)

### 3.3 Iterate

Adjust the transformer to match Enveloppe's output. Run the comparison again.
Aim for >95% parity before proceeding.

---

## Phase 4: Switch to CI Content

### 4.1 Shadow Deploy

1. In the workflow, set `compare_only: false`
2. The CI will overwrite `content/` with transformed vault content
3. The Quartz build will use the CI-transformed files
4. Monitor the site for visual regressions

### 4.2 Run Both Systems in Parallel

Keep Enveloppe running for 1 week:

- Enveloppe pushes to `content/`
- CI transforms `vault/` to `content-ci/`
- Compare regularly

### 4.3 Switch

Once confident:

1. Manually trigger the workflow with `compare_only: false`
2. Verify the site looks correct
3. Proceed to Phase 5

---

## Phase 5: Clean Up

1. **Disable Enveloppe** on your mobile device
2. **Remove Enveloppe plugin** from Obsidian
3. **Update deploy.yml** to include vault transformation before Quartz build:

```yaml
# In deploy.yml, add before the Quartz build step:
- name: Transform vault content
  run: |
    npx tsx scripts/transform-vault.ts \
      --vault vault/ \
      --output content/
```

4. **Clean up**: Remove `content-ci/` directory references
5. **Update README** with new workflow documentation

---

## Rollback Plan

At any phase, you can roll back:

1. **Re-enable Enveloppe** on mobile
2. **Revert CI changes** (git revert)
3. **No data loss**: All content is version-controlled in git

---

## Alternative Approach: Let Quartz Handle Wikilinks

Since Quartz already includes `Plugin.ObsidianFlavoredMarkdown()` which converts
wikilinks during the build process, an alternative approach is:

1. Push raw vault files directly to `content/`
2. Let Quartz handle wikilink conversion at build time
3. Add `remark-breaks` or a custom plugin for hard line breaks

**Pros**: Simpler pipeline, no custom transformer to maintain
**Cons**: Hard breaks need separate handling, harder to compare with current content

This approach is viable for Phase 5+ once you're confident the site works correctly.

---

## Files Added by This PR

| File                                    | Purpose                                         |
| --------------------------------------- | ----------------------------------------------- |
| `scripts/lib/vault-transform.ts`        | Core transformation functions (pure, tested)    |
| `scripts/lib/vault-transform.test.ts`   | 93 tests covering all transformation rules      |
| `scripts/transform-vault.ts`            | CLI to transform a vault directory              |
| `scripts/compare-content.ts`            | CLI to compare two content directories          |
| `.github/workflows/transform-vault.yml` | CI workflow for automatic transformation        |
| `vault/.gitkeep`                        | Placeholder for the vault sync directory        |
| `vault/.gitignore`                      | Excludes .obsidian/ and other non-content files |
| `MIGRATION.md`                          | This guide                                      |
