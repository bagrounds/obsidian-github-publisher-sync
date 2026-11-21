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
│ • dataview   │                      └──────┬───────┘
│ • embeds     │                             │
│ • hard breaks│                             ↓
│ • filter     │                      ┌──────────────┐
│ (30-60 sec)  │                      │ GitHub CI    │
└──────┬───────┘                      │              │
       │                              │ Transform:   │
       ↓                              │ • wikilinks  │
┌──────────────┐                      │ • dataview   │
│ GitHub       │                      │ • embeds     │
│ content/     │                      │ • hard breaks│
│              │                      │ • filter     │
│ Quartz build │                      │      ↓       │
│      ↓       │                      │ Quartz build │
│ GitHub Pages │                      │      ↓       │
└──────────────┘                      │ GitHub Pages │
                                      └──────────────┘
```

---

## What Enveloppe Does

Based on the [Enveloppe source code](https://github.com/Enveloppe/obsidian-enveloppe) and
[documentation](https://enveloppe.ovh/Settings/Content/), these are all the transformations
Enveloppe performs on mobile before pushing to GitHub:

1. **Wikilink → Markdown conversion**: `[[path|alias]]` → `[alias](./path.md)`
2. **Internal link resolution**: Relative paths computed between source and target files
3. **Dataview query rendering**: DQL, DataviewJS, inline DQL, and inline JS queries are
   executed and their computed output is baked into the markdown
4. **Embed baking**: `![[note]]` transclusions are resolved and the referenced content is
   inlined into the document
5. **Hard line breaks**: Two trailing spaces added to every line
6. **Frontmatter filtering**: Only `share: true` files are published
7. **Tag processing**: Inline tags (e.g., `#tag/subtag`) promoted to frontmatter `tags`
   field with `/` → `_` conversion
8. **Text replacement**: Configurable string/regex replacements
9. **File path resolution**: Supports YAML-based, Obsidian-based, or fixed folder strategies
10. **Folder notes**: Renaming to `index.md` for web compatibility
11. **Attachment handling**: Images, PDFs, and other assets are uploaded alongside notes

### Current Transformer Scope

The CI transformer (`scripts/lib/vault-transform.ts`) currently handles:

- ✅ Wikilink → Markdown conversion
- ✅ Internal link resolution (relative paths)
- ✅ Hard line breaks
- ✅ Frontmatter filtering (`share: true`)
- ✅ Code block protection (wikilinks in code blocks preserved)

Not yet implemented (will be needed for 100% parity):

- ❌ Dataview query rendering
- ❌ Embed baking (transclusion inlining)
- ❌ Tag processing (inline → frontmatter)
- ❌ Text replacements
- ❌ Folder note renaming

---

## Phase 1: Set Up Git Sync (Your Next Step)

### 1.1 Install the Obsidian Git Plugin

1. In Obsidian mobile: **Settings → Community plugins → Browse**
2. Search for **"Git"** (by Vinzent03)
3. Install and enable

### 1.2 Configure the Plugin

In the Obsidian Git plugin settings:

- **Authentication**: Paste your GitHub Personal Access Token (PAT)
- **Auto commit-and-sync interval**: 10 minutes (or your preference)
- **Pull on startup**: enabled
- **Push on commit-and-sync**: enabled

The plugin handles clone, commit, pull, and push entirely within Obsidian mobile.

### 1.3 Configure `.gitignore` in Your Vault

The `vault/.gitignore` already excludes Obsidian internals:

```
.obsidian/
.trash/
.DS_Store
```

Add any personal exclusions as needed.

### 1.4 First Sync

1. Open Obsidian mobile
2. Use the command palette: **Git: Commit all and push**
3. Verify files appear in `vault/` on GitHub

---

## Phase 2: CI Transformation (Already Built)

The CI transformation pipeline is already implemented:

- **Transformer**: `scripts/lib/vault-transform.ts` — converts wikilinks, adds hard breaks
- **CLI**: `scripts/transform-vault.ts` — processes all vault files
- **Workflow**: `.github/workflows/transform-vault.yml` — runs on push to `vault/`

The workflow transforms vault files to `content-ci/` and runs `diff -r content/ content-ci/`
to compare with the existing Enveloppe-produced content.

---

## Phase 3: Compare & Achieve 100% Parity

### 3.1 Automated Comparison

The CI workflow runs `diff -r` automatically on every push to `vault/`.
Check the workflow output for any differences.

### 3.2 HTML Comparison

For deeper validation, build both content directories with Quartz and diff the HTML:

```bash
# Build existing content
npx quartz build
mv public/ public-old/

# Build CI-transformed content
npx quartz build --directory content-ci
diff -r public-old/ public/
```

### 3.3 Root Cause Every Difference

For every discrepancy, perform a 5 whys analysis:

1. What is different?
2. Why is it different?
3. Is it a transformer bug, an Enveloppe feature we haven't replicated, or intentional?
4. Can we fix it?
5. If we can't achieve parity, is the difference acceptable?

Goal: **100% parity**. Compromise only after thorough investigation.

---

## Phase 4: Switch to CI Content

### 4.1 Point Quartz at the New Directory

When CI-transformed content achieves parity, update `quartz.config.ts` (or the
build command) to read from `content-ci/` instead of `content/`:

```bash
npx quartz build --directory content-ci
```

This avoids any risky mutation of the existing `content/` directory.

### 4.2 Validate the Deployed Site

After deploying with CI content, diff the generated HTML output against the
previous deployment to confirm no regressions:

```bash
diff -r public-old/ public/
```

---

## Phase 5: Clean Up

1. **Disable Enveloppe** on your mobile device
2. **Remove Enveloppe plugin** from Obsidian
3. **Delete the old `content/` directory** once confident in CI content
4. **Rename `content-ci/` to `content/`** (or update Quartz config permanently)
5. **Update README** with new workflow documentation

---

## Rollback Plan

At any phase, you can roll back:

1. **Re-enable Enveloppe** on mobile
2. **Point Quartz back at `content/`** (the old directory is untouched)
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
| `scripts/lib/vault-transform.test.ts`   | 168 tests covering all transformation rules     |
| `scripts/transform-vault.ts`            | CLI to transform a vault directory              |
| `.github/workflows/transform-vault.yml` | CI workflow for automatic transformation        |
| `vault/.gitkeep`                        | Placeholder for the vault sync directory        |
| `vault/.gitignore`                      | Excludes .obsidian/ and other non-content files |
| `MIGRATION.md`                          | This guide                                      |
