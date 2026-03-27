## PR Blogs
- 📝 With every PR, please generate a blog post describing your work in the ai-blog directory at the root of the repo. See some posts in https://bagrounds.org/ai-blog for prior examples.
- 🎯 Every heading, sentence, list item, and table cell in the blog post should begin with an emoji.
- 🚫 AI blog posts must never contain tags in their frontmatter or links in the content.
- 🧭 Always include breadcrumb nav links at the top of the blog post, right after the frontmatter: `[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]`
- 📚 Always include a book recommendations section at the bottom of the blog post with Similar, Contrasting, and Creatively Related recommendations relevant to the post content. Do not include any links in the recommendations — just recommend books by title and author.
- 📖 Never put book titles in italics or quotes. Just write the title plainly.
- 🎧 Write for TTS listening. The blog owner always listens to posts via text-to-speech, so write in a style that sounds good when read aloud. Avoid relying on tables, code blocks, or back-ticked inline code to convey essential information — TTS readers skip or garble these. If a table or code block is truly necessary, always accompany it with a prose description that fully conveys the same information for audio listeners. Prefer descriptive sentences and lists over visual formatting.
- 🔢 Always number ai-blog posts with a sequence number per day in the filename: `YYYY-MM-DD-N-slug.md` where N is the post's position that day (e.g., `2026-03-27-3-porting-internal-linking.md` is the third post on March 27). Check existing posts for that date to determine the next number. The URL and aliases in frontmatter must match the filename slug.

## Product & Engineering Specs
- 📋 All features must be covered by a product/engineering spec in the `specs/` directory.
- 🆕 Create or extend specs when implementing new features.
- 🐛 Amend specs when bugs are found or behavior changes.
- 🔗 The README should link to specs but not duplicate their content.

## Intelligent Planning
- 🧠 Before doing any work, always generate at least 3 initial plans. Analyze each of them and iterate on a best plan until you're very confident it'll produce a great result.

## Engineering Excellence
- 🏗️ Strong static types - inspiration from Haskell
- 🧪 Thorough test coverage, ideally with property based tests
- 🧩 Functional declarative programming patterns. Avoid for loops and conditional logic in favor of principled functional abstractions. Prefer map, reduce, filter, flatMap, and forEach to for and while loops. Never use mutable variables (const > let). Leverage function composition and expression oriented programming.
- 🔬 Prefer principled abstractions. Good ideas often come from category theory
- 🔧 Unix Philosophy & Modularity
- 📐 Domain Driven Design
- 📖 Self Documenting Code - never write comments that tell what the code is doing; always write well named functions and variables so that it's obvious

## Scientific Engineering
- 🔬 Always test your work and iterate until your tests succeed and verify that the goal has been achieved.

## Obsidian Vault is the Source of Truth
- 📱 The `content/` directory is a **read-only one-way sync** from the Obsidian vault on the user's phone. Never write to `content/` from GitHub Actions or scripts.
- 🚫 Never commit to the git repo from a GHA workflow. There is no reason to do this today.
- 🔄 All generated content (blog posts, images, attachments, updated frontmatter) must be persisted by syncing to the Obsidian vault using `scripts/sync-file-to-obsidian.ts` or `scripts/lib/obsidian-sync.ts`.
- 🔒 GHA workflows should use `contents: read` permissions — never `contents: write`.
