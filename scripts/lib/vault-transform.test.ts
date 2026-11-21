import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  parseWikilink,
  resolveRelativePath,
  buildDisplayText,
  encodeHeading,
  convertWikilink,
  transformWikilinksInLine,
  transformBody,
  addHardBreaks,
  splitFrontmatter,
  hasShareTrue,
  transformFile,
} from "./vault-transform.ts";

// --- parseWikilink ---

describe("parseWikilink", () => {
  const cases: Array<{
    name: string;
    input: string;
    expected: {
      isEmbed: boolean;
      filePath: string | null;
      heading: string | null;
      alias: string | null;
    };
  }> = [
    {
      name: "simple path",
      input: "[[note]]",
      expected: {
        isEmbed: false,
        filePath: "note",
        heading: null,
        alias: null,
      },
    },
    {
      name: "path with alias",
      input: "[[note|Display Text]]",
      expected: {
        isEmbed: false,
        filePath: "note",
        heading: null,
        alias: "Display Text",
      },
    },
    {
      name: "path with heading",
      input: "[[note#Section]]",
      expected: {
        isEmbed: false,
        filePath: "note",
        heading: "Section",
        alias: null,
      },
    },
    {
      name: "path with heading and alias",
      input: "[[note#Section|Display]]",
      expected: {
        isEmbed: false,
        filePath: "note",
        heading: "Section",
        alias: "Display",
      },
    },
    {
      name: "heading only",
      input: "[[#Section]]",
      expected: {
        isEmbed: false,
        filePath: null,
        heading: "Section",
        alias: null,
      },
    },
    {
      name: "heading only with alias",
      input: "[[#Section|Display]]",
      expected: {
        isEmbed: false,
        filePath: null,
        heading: "Section",
        alias: "Display",
      },
    },
    {
      name: "image embed",
      input: "![[image.png]]",
      expected: {
        isEmbed: true,
        filePath: "image.png",
        heading: null,
        alias: null,
      },
    },
    {
      name: "image embed with alt",
      input: "![[image.png|Alt Text]]",
      expected: {
        isEmbed: true,
        filePath: "image.png",
        heading: null,
        alias: "Alt Text",
      },
    },
    {
      name: "absolute path",
      input: "[[/index|Home]]",
      expected: {
        isEmbed: false,
        filePath: "/index",
        heading: null,
        alias: "Home",
      },
    },
    {
      name: "directory path",
      input: "[[reflections/2024-04-19|⏮️]]",
      expected: {
        isEmbed: false,
        filePath: "reflections/2024-04-19",
        heading: null,
        alias: "⏮️",
      },
    },
    {
      name: "empty heading with alias",
      input: "[[reflections/2024-04-19#|started blogging]]",
      expected: {
        isEmbed: false,
        filePath: "reflections/2024-04-19",
        heading: "",
        alias: "started blogging",
      },
    },
    {
      name: "pipe in alias",
      input: "[[reflections/2024-11-20|2024-11-20 | 🪄 Comments]]",
      expected: {
        isEmbed: false,
        filePath: "reflections/2024-11-20",
        heading: null,
        alias: "2024-11-20 | 🪄 Comments",
      },
    },
    {
      name: "emoji heading",
      input: "[[topics/linear-processes#✍️🎁🦾 Sharing Understanding]]",
      expected: {
        isEmbed: false,
        filePath: "topics/linear-processes",
        heading: "✍️🎁🦾 Sharing Understanding",
        alias: null,
      },
    },
    {
      name: "note embed (transclusion)",
      input: "![[other-note]]",
      expected: {
        isEmbed: true,
        filePath: "other-note",
        heading: null,
        alias: null,
      },
    },
    {
      name: "note embed with heading",
      input: "![[other-note#Section]]",
      expected: {
        isEmbed: true,
        filePath: "other-note",
        heading: "Section",
        alias: null,
      },
    },
    {
      name: "pdf embed",
      input: "![[document.pdf]]",
      expected: {
        isEmbed: true,
        filePath: "document.pdf",
        heading: null,
        alias: null,
      },
    },
    {
      name: "external URL in wikilink",
      input: "[[https://example.com|Example]]",
      expected: {
        isEmbed: false,
        filePath: "https://example.com",
        heading: null,
        alias: "Example",
      },
    },
  ];

  cases.forEach(({ name, input, expected }) => {
    it(name, () => {
      assert.deepStrictEqual(parseWikilink(input), expected);
    });
  });
});

// --- resolveRelativePath ---

describe("resolveRelativePath", () => {
  const cases: Array<{
    name: string;
    target: string;
    sourceDir: string;
    expected: string;
  }> = [
    {
      name: "same directory",
      target: "reflections/2024-04-19",
      sourceDir: "reflections",
      expected: "./2024-04-19.md",
    },
    {
      name: "sibling directory",
      target: "software/obsidian",
      sourceDir: "reflections",
      expected: "../software/obsidian.md",
    },
    {
      name: "root from subdirectory",
      target: "index",
      sourceDir: "reflections",
      expected: "../index.md",
    },
    {
      name: "absolute path from subdirectory",
      target: "/index",
      sourceDir: "reflections",
      expected: "../index.md",
    },
    {
      name: "deeply nested to root",
      target: "index",
      sourceDir: "topics/programming-problems",
      expected: "../../index.md",
    },
    {
      name: "from root to subdirectory",
      target: "reflections/2024-04-21",
      sourceDir: ".",
      expected: "./reflections/2024-04-21.md",
    },
    {
      name: "same file reference from root",
      target: "index",
      sourceDir: ".",
      expected: "./index.md",
    },
    {
      name: "cross-directory from deep nesting",
      target: "books/planning-for-everything",
      sourceDir: "topics/programming-problems",
      expected: "../../books/planning-for-everything.md",
    },
    {
      name: "image asset (no .md)",
      target: "image.png",
      sourceDir: "reflections",
      expected: "../image.png",
    },
    {
      name: "same directory asset",
      target: "reflections/photo.jpg",
      sourceDir: "reflections",
      expected: "./photo.jpg",
    },
    {
      name: "pdf asset",
      target: "docs/paper.pdf",
      sourceDir: "reflections",
      expected: "../docs/paper.pdf",
    },
    {
      name: "excalidraw file",
      target: "diagrams/sketch.excalidraw",
      sourceDir: "topics",
      expected: "../diagrams/sketch.excalidraw",
    },
  ];

  cases.forEach(({ name, target, sourceDir, expected }) => {
    it(name, () => {
      assert.strictEqual(resolveRelativePath(target, sourceDir), expected);
    });
  });
});

// --- buildDisplayText ---

describe("buildDisplayText", () => {
  it("uses alias when present", () => {
    assert.strictEqual(
      buildDisplayText({
        isEmbed: false,
        filePath: "note",
        heading: null,
        alias: "Custom Name",
      }),
      "Custom Name",
    );
  });

  it("uses path > heading for path with heading", () => {
    assert.strictEqual(
      buildDisplayText({
        isEmbed: false,
        filePath: "topics/ai",
        heading: "Deep Learning",
        alias: null,
      }),
      "topics/ai > Deep Learning",
    );
  });

  it("uses heading alone for same-file reference", () => {
    assert.strictEqual(
      buildDisplayText({
        isEmbed: false,
        filePath: null,
        heading: "Section",
        alias: null,
      }),
      "Section",
    );
  });

  it("uses filename for path only", () => {
    assert.strictEqual(
      buildDisplayText({
        isEmbed: false,
        filePath: "folder/note",
        heading: null,
        alias: null,
      }),
      "note",
    );
  });

  it("uses full filename for root-level path", () => {
    assert.strictEqual(
      buildDisplayText({
        isEmbed: false,
        filePath: "index",
        heading: null,
        alias: null,
      }),
      "index",
    );
  });

  it("alias takes precedence over heading", () => {
    assert.strictEqual(
      buildDisplayText({
        isEmbed: false,
        filePath: "note",
        heading: "Section",
        alias: "My Display",
      }),
      "My Display",
    );
  });
});

// --- encodeHeading ---

describe("encodeHeading", () => {
  it("encodes spaces as %20", () => {
    assert.strictEqual(encodeHeading("Hello World"), "Hello%20World");
  });

  it("preserves emojis", () => {
    assert.strictEqual(
      encodeHeading("✍️🎁🦾 Sharing Understanding"),
      "✍️🎁🦾%20Sharing%20Understanding",
    );
  });

  it("preserves empty string", () => {
    assert.strictEqual(encodeHeading(""), "");
  });

  it("preserves text without spaces", () => {
    assert.strictEqual(encodeHeading("NoSpaces"), "NoSpaces");
  });
});

// --- convertWikilink ---

describe("convertWikilink", () => {
  it("converts simple wikilink from reflections/", () => {
    assert.strictEqual(
      convertWikilink("[[/index|Home]]", "reflections"),
      "[Home](../index.md)",
    );
  });

  it("converts same-directory wikilink", () => {
    assert.strictEqual(
      convertWikilink("[[reflections/index|Reflections]]", "reflections"),
      "[Reflections](./index.md)",
    );
  });

  it("converts navigation emoji link", () => {
    assert.strictEqual(
      convertWikilink("[[reflections/2024-04-19|⏮️]]", "reflections"),
      "[⏮️](./2024-04-19.md)",
    );
  });

  it("converts cross-directory link with emoji alias", () => {
    assert.strictEqual(
      convertWikilink("[[software/obsidian|💾✍️🌋⚫️ Obsidian]]", "reflections"),
      "[💾✍️🌋⚫️ Obsidian](../software/obsidian.md)",
    );
  });

  it("converts link with empty heading anchor", () => {
    assert.strictEqual(
      convertWikilink(
        "[[reflections/2024-04-19#|started blogging]]",
        "reflections",
      ),
      "[started blogging](./2024-04-19.md#)",
    );
  });

  it("converts link with heading and no alias", () => {
    assert.strictEqual(
      convertWikilink(
        "[[topics/linear-processes#✍️🎁🦾 Sharing Understanding]]",
        "reflections",
      ),
      "[topics/linear-processes > ✍️🎁🦾 Sharing Understanding](../topics/linear-processes.md#✍️🎁🦾%20Sharing%20Understanding)",
    );
  });

  it("converts link with alias containing pipe", () => {
    assert.strictEqual(
      convertWikilink(
        "[[reflections/2024-11-20|2024-11-20 | 🪄 Let There Be Comments 💬]]",
        "reflections",
      ),
      "[2024-11-20 | 🪄 Let There Be Comments 💬](./2024-11-20.md)",
    );
  });

  it("converts image embed to markdown image", () => {
    assert.strictEqual(
      convertWikilink("![[photo.png]]", "reflections"),
      "![photo.png](../photo.png)",
    );
  });

  it("converts image embed with alt text", () => {
    assert.strictEqual(
      convertWikilink("![[diagrams/flow.svg|Flow Diagram]]", "topics"),
      "![Flow Diagram](../diagrams/flow.svg)",
    );
  });

  it("converts note embed (transclusion) to link", () => {
    assert.strictEqual(
      convertWikilink("![[other-note]]", "reflections"),
      "[other-note](../other-note.md)",
    );
  });

  it("converts external URL wikilink", () => {
    assert.strictEqual(
      convertWikilink("[[https://example.com|Example]]", "reflections"),
      "[Example](https://example.com)",
    );
  });

  it("converts heading-only reference", () => {
    assert.strictEqual(
      convertWikilink("[[#My Section]]", "reflections"),
      "[My Section](#My%20Section)",
    );
  });

  it("handles books link from reflections", () => {
    assert.strictEqual(
      convertWikilink(
        "[[books/planning-for-everything|🗺️🎯🪜🏗️ Planning for Everything: The Design of Paths and Goals]]",
        "reflections",
      ),
      "[🗺️🎯🪜🏗️ Planning for Everything: The Design of Paths and Goals](../books/planning-for-everything.md)",
    );
  });

  it("handles deeply nested source directory", () => {
    assert.strictEqual(
      convertWikilink("[[index|Home]]", "topics/programming-problems"),
      "[Home](../../index.md)",
    );
  });
});

// --- transformWikilinksInLine ---

describe("transformWikilinksInLine", () => {
  it("transforms multiple wikilinks in one line", () => {
    const input =
      "[[/index|Home]] > [[reflections/index|Reflections]] | [[reflections/2024-04-19|⏮️]]";
    const expected =
      "[Home](../index.md) > [Reflections](./index.md) | [⏮️](./2024-04-19.md)";
    assert.strictEqual(
      transformWikilinksInLine(input, "reflections"),
      expected,
    );
  });

  it("preserves wikilinks inside inline code", () => {
    const input = "Use `[[wikilink]]` syntax in Obsidian";
    assert.strictEqual(
      transformWikilinksInLine(input, "reflections"),
      "Use `[[wikilink]]` syntax in Obsidian",
    );
  });

  it("transforms wikilinks outside inline code but not inside", () => {
    const input = "See [[note|Link]] and `[[code example]]` here";
    const expected = "See [Link](../note.md) and `[[code example]]` here";
    assert.strictEqual(
      transformWikilinksInLine(input, "reflections"),
      expected,
    );
  });

  it("leaves plain text unchanged", () => {
    const input = "No links here, just text.";
    assert.strictEqual(
      transformWikilinksInLine(input, "reflections"),
      "No links here, just text.",
    );
  });

  it("preserves standard markdown links", () => {
    const input = "[GitHub](https://github.com) and [[note|Internal]]";
    const expected = "[GitHub](https://github.com) and [Internal](../note.md)";
    assert.strictEqual(
      transformWikilinksInLine(input, "reflections"),
      expected,
    );
  });
});

// --- transformBody ---

describe("transformBody", () => {
  it("transforms wikilinks outside code blocks", () => {
    const input = "Link: [[note|Text]]\n```\n[[code]]\n```\n[[other|Other]]";
    const expected =
      "Link: [Text](./note.md)\n```\n[[code]]\n```\n[Other](./other.md)";
    assert.strictEqual(transformBody(input, "."), expected);
  });

  it("handles multiple code blocks", () => {
    const input = [
      "Before [[a|A]]",
      "```js",
      "[[inside]]",
      "```",
      "Between [[b|B]]",
      "```",
      "[[also inside]]",
      "```",
      "After [[c|C]]",
    ].join("\n");
    const expected = [
      "Before [A](./a.md)",
      "```js",
      "[[inside]]",
      "```",
      "Between [B](./b.md)",
      "```",
      "[[also inside]]",
      "```",
      "After [C](./c.md)",
    ].join("\n");
    assert.strictEqual(transformBody(input, "."), expected);
  });

  it("handles empty body", () => {
    assert.strictEqual(transformBody("", "."), "");
  });

  it("handles body with no wikilinks", () => {
    const input = "Just plain text\nWith multiple lines";
    assert.strictEqual(transformBody(input, "."), input);
  });
});

// --- addHardBreaks ---

describe("addHardBreaks", () => {
  it("adds trailing spaces to content lines", () => {
    assert.strictEqual(addHardBreaks("Hello\nWorld"), "Hello  \nWorld  ");
  });

  it("adds trailing spaces to blank lines", () => {
    assert.strictEqual(addHardBreaks("Line1\n\nLine2"), "Line1  \n  \nLine2  ");
  });

  it("replaces existing trailing whitespace", () => {
    assert.strictEqual(
      addHardBreaks("Trailing space   \nTab\t"),
      "Trailing space  \nTab  ",
    );
  });

  it("handles single line", () => {
    assert.strictEqual(addHardBreaks("Single"), "Single  ");
  });

  it("handles empty string", () => {
    assert.strictEqual(addHardBreaks(""), "  ");
  });
});

// --- splitFrontmatter ---

describe("splitFrontmatter", () => {
  it("splits standard frontmatter", () => {
    const content = "---\nshare: true\ntitle: Test\n---\nBody text";
    const result = splitFrontmatter(content);
    assert.strictEqual(
      result.frontmatter,
      "---\nshare: true\ntitle: Test\n---",
    );
    assert.strictEqual(result.body, "Body text");
  });

  it("handles missing frontmatter", () => {
    const content = "No frontmatter here";
    const result = splitFrontmatter(content);
    assert.strictEqual(result.frontmatter, "");
    assert.strictEqual(result.body, "No frontmatter here");
  });

  it("handles unclosed frontmatter", () => {
    const content = "---\nshare: true\nNo closing delimiter";
    const result = splitFrontmatter(content);
    assert.strictEqual(result.frontmatter, "");
    assert.strictEqual(result.body, "---\nshare: true\nNo closing delimiter");
  });

  it("preserves multiline frontmatter with arrays", () => {
    const content =
      "---\nshare: true\naliases:\n  - Alias One\n  - Alias Two\n---\nBody";
    const result = splitFrontmatter(content);
    assert.strictEqual(
      result.frontmatter,
      "---\nshare: true\naliases:\n  - Alias One\n  - Alias Two\n---",
    );
    assert.strictEqual(result.body, "Body");
  });
});

// --- hasShareTrue ---

describe("hasShareTrue", () => {
  it("detects share: true", () => {
    assert.strictEqual(hasShareTrue("---\nshare: true\n---"), true);
  });

  it("rejects share: false", () => {
    assert.strictEqual(hasShareTrue("---\nshare: false\n---"), false);
  });

  it("rejects missing share", () => {
    assert.strictEqual(hasShareTrue("---\ntitle: Test\n---"), false);
  });

  it("rejects empty share value", () => {
    assert.strictEqual(hasShareTrue("---\nshare:\n---"), false);
  });

  it("handles extra whitespace", () => {
    assert.strictEqual(hasShareTrue("---\nshare:   true  \n---"), true);
  });
});

// --- transformFile ---

describe("transformFile", () => {
  it("returns null for non-shared files", () => {
    const content = "---\nshare: false\n---\n[[note]]";
    assert.strictEqual(transformFile(content, "reflections/test.md"), null);
  });

  it("returns null for files without frontmatter", () => {
    const content = "Just content without frontmatter";
    assert.strictEqual(transformFile(content, "reflections/test.md"), null);
  });

  it("transforms shared file", () => {
    const content = "---\nshare: true\n---\n[[/index|Home]]";
    const result = transformFile(content, "reflections/test.md");
    assert.ok(result);
    assert.ok(result.includes("[Home](../index.md)"));
    assert.ok(!result.includes("[["));
  });

  it("preserves frontmatter exactly", () => {
    const content =
      '---\nshare: true\nAuthor: "[[bryan-grounds]]"\ntitle: Test\n---\nBody';
    const result = transformFile(content, "reflections/test.md");
    assert.ok(result);
    assert.ok(
      result.startsWith('---\nshare: true\nAuthor: "[[bryan-grounds]]"'),
    );
  });

  it("adds hard breaks to body only", () => {
    const content = "---\nshare: true\n---\nLine one\nLine two";
    const result = transformFile(content, "reflections/test.md");
    assert.ok(result);
    // Frontmatter should NOT have trailing spaces
    assert.ok(result.startsWith("---\nshare: true\n---"));
    // Body should have trailing spaces
    assert.ok(result.includes("Line one  \n"));
    assert.ok(result.includes("Line two  "));
  });
});

// --- Integration: Sample from Problem Statement ---

describe("integration: 2024-04-21 reflection transformation", () => {
  const vaultContent = [
    "---",
    "share: true",
    "URL: https://bagrounds.org/reflections/2024-04-21",
    "title: 2024-04-21 | ✍️ Blog | 🌋 Obsidian | 🤖 Automation | 🌓 Solarized | 💬 Comments 🪞",
    "aliases:",
    "  - 2024-04-21 | ✍️ Blog | 🌋 Obsidian | 🤖 Automation | 🌓 Solarized | 💬 Comments 🪞",
    "---",
    "[[/index|Home]] > [[reflections/index|Reflections]] | [[reflections/2024-04-19|⏮️]] [[reflections/2024-04-23|⏭️]]",
    "# 2024-04-21 | ✍️ Blog | 🌋 Obsidian | 🤖 Automation | 🌓 Solarized | 💬 Comments 🪞",
    "## 🏁 Hello, World!",
    "I recently [[reflections/2024-04-19#|started blogging]].",
    "",
    "### ✍ Blogging From Obsidian",
    "To get started quickly, I",
    "1. installed the [GitHub Publisher](https://github.com/ObsidianPublisher/obsidian-github-publisher) plugin for [[software/obsidian|💾✍️🌋⚫️ Obsidian]]",
    "    - this allows me to easily publish notes from my Obsidian app to a GitHub repository",
    "2. configured [GitHub Pages](https://pages.github.com) for the new repository",
    "3. copied some default [[software/quartz|💎🔬🔍📈 Quartz]] files and a corresponding [GitHub Action](https://github.com/features/actions) into the new repository",
    "",
    "🔮 Maybe we'll borrow some ideas from [[books/planning-for-everything|🗺️🎯🪜🏗️ Planning for Everything: The Design of Paths and Goals]].",
    "🔜™️ To be continued... on [[reflections/2024-11-20|2024-11-20 | 🪄 Let There Be Comments 💬]]",
  ].join("\n");

  it("transforms the navigation line correctly", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    assert.ok(
      result.includes(
        "[Home](../index.md) > [Reflections](./index.md) | [⏮️](./2024-04-19.md) [⏭️](./2024-04-23.md)",
      ),
    );
  });

  it("transforms the internal link with empty heading", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    assert.ok(result.includes("[started blogging](./2024-04-19.md#)"));
  });

  it("transforms cross-directory links", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    assert.ok(result.includes("[💾✍️🌋⚫️ Obsidian](../software/obsidian.md)"));
    assert.ok(result.includes("[💎🔬🔍📈 Quartz](../software/quartz.md)"));
  });

  it("transforms books link correctly", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    assert.ok(
      result.includes(
        "[🗺️🎯🪜🏗️ Planning for Everything: The Design of Paths and Goals](../books/planning-for-everything.md)",
      ),
    );
  });

  it("transforms link with pipe in alias", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    assert.ok(
      result.includes(
        "[2024-11-20 | 🪄 Let There Be Comments 💬](./2024-11-20.md)",
      ),
    );
  });

  it("preserves standard markdown links unchanged", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    assert.ok(
      result.includes(
        "[GitHub Publisher](https://github.com/ObsidianPublisher/obsidian-github-publisher)",
      ),
    );
    assert.ok(result.includes("[GitHub Pages](https://pages.github.com)"));
    assert.ok(
      result.includes("[GitHub Action](https://github.com/features/actions)"),
    );
  });

  it("preserves frontmatter unchanged", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    assert.ok(result.startsWith("---\nshare: true\n"));
    assert.ok(
      result.includes("URL: https://bagrounds.org/reflections/2024-04-21\n"),
    );
  });

  it("adds hard breaks to body lines", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    const { body } = splitFrontmatter(result);
    const bodyLines = body.split("\n");
    bodyLines.forEach((line) => {
      assert.ok(line.endsWith("  "), `Expected trailing spaces on: "${line}"`);
    });
  });

  it("ensures no wikilinks remain in body", () => {
    const result = transformFile(vaultContent, "reflections/2024-04-21.md");
    assert.ok(result);
    const { body } = splitFrontmatter(result);
    assert.ok(
      !body.includes("[["),
      `Found unconverted wikilink in body: ${body}`,
    );
  });
});

// --- Integration: Deeply Nested File ---

describe("integration: deeply nested file transformation", () => {
  const vaultContent = [
    "---",
    "share: true",
    "title: 🔢➕ 2 Sum",
    "---",
    "[[/index|Home]] > [[topics/index|Topics]] > [[topics/programming-problems/index|Programming Problems]]",
    "# 🔢➕ 2 Sum",
    "## Problem Statement",
    "Given an array of integers.",
  ].join("\n");

  it("resolves navigation links from 3-level depth", () => {
    const result = transformFile(
      vaultContent,
      "topics/programming-problems/2-sum.md",
    );
    assert.ok(result);
    assert.ok(result.includes("[Home](../../index.md)"));
    assert.ok(result.includes("[Topics](../index.md)"));
    assert.ok(result.includes("[Programming Problems](./index.md)"));
  });
});

// --- Integration: Root-level File ---

describe("integration: root-level file transformation", () => {
  const vaultContent = [
    "---",
    "share: true",
    "title: Home",
    "---",
    "# Home",
    "- [[reflections/index|Reflections]]",
    "- [[books/index|Books]]",
  ].join("\n");

  it("resolves links from root", () => {
    const result = transformFile(vaultContent, "index.md");
    assert.ok(result);
    assert.ok(result.includes("[Reflections](./reflections/index.md)"));
    assert.ok(result.includes("[Books](./books/index.md)"));
  });
});

// --- Integration: Code Block Protection ---

describe("integration: code block protection", () => {
  const vaultContent = [
    "---",
    "share: true",
    "---",
    "Here is [[note|a link]]",
    "```javascript",
    "const x = '[[not a link]]'",
    "```",
    "After code: [[other|another link]]",
  ].join("\n");

  it("transforms links outside code blocks only", () => {
    const result = transformFile(vaultContent, "test.md");
    assert.ok(result);
    assert.ok(result.includes("[a link](./note.md)"));
    assert.ok(result.includes("[[not a link]]"));
    assert.ok(result.includes("[another link](./other.md)"));
  });
});

// --- Property-Based Invariant Tests ---

describe("property: resolveRelativePath", () => {
  const directories = [
    ".",
    "reflections",
    "books",
    "topics/programming-problems",
    "ai-blog",
  ];
  const targets = [
    "index",
    "reflections/2024-04-21",
    "books/dune",
    "topics/ai",
    "/index",
  ];

  directories.forEach((dir) => {
    targets.forEach((target) => {
      it(`${target} from ${dir} starts with ./ or ../`, () => {
        const result = resolveRelativePath(target, dir);
        assert.ok(
          result.startsWith("./") || result.startsWith("../"),
          `Expected relative prefix, got: "${result}"`,
        );
      });

      it(`${target} from ${dir} ends with .md`, () => {
        const result = resolveRelativePath(target, dir);
        assert.ok(
          result.endsWith(".md"),
          `Expected .md extension, got: "${result}"`,
        );
      });
    });
  });
});

describe("property: convertWikilink always removes [[", () => {
  const wikilinks = [
    "[[note]]",
    "[[folder/note|Alias]]",
    "[[note#heading]]",
    "[[note#heading|Alias]]",
    "[[/absolute|Home]]",
    "[[deep/path/note|Display]]",
    "[[note#Emoji 🎉 Heading|Text]]",
  ];

  wikilinks.forEach((wl) => {
    it(`${wl} produces no [[ in output`, () => {
      const result = convertWikilink(wl, "reflections");
      assert.ok(
        !result.includes("[["),
        `Output still contains [[: "${result}"`,
      );
    });

    it(`${wl} produces valid markdown link`, () => {
      const result = convertWikilink(wl, "reflections");
      assert.ok(
        /\[.*\]\(.*\)/.test(result),
        `Not a valid markdown link: "${result}"`,
      );
    });
  });
});

describe("property: transformFile preserves frontmatter", () => {
  const frontmatters = [
    "---\nshare: true\ntitle: Test\n---",
    '---\nshare: true\nAuthor: "[[someone]]"\ntags:\n  - a\n  - b\n---',
    "---\nshare: true\nURL: https://example.com\naliases:\n  - Alias\n---",
  ];

  frontmatters.forEach((fm, i) => {
    it(`frontmatter variant ${i + 1} is preserved exactly`, () => {
      const content = `${fm}\n[[note|Link]]`;
      const result = transformFile(content, "test.md");
      assert.ok(result);
      assert.ok(
        result.startsWith(fm),
        `Frontmatter was modified: "${result.slice(0, fm.length)}"`,
      );
    });
  });
});

describe("property: transformFile body has no wikilinks", () => {
  const bodies = [
    "[[a]] and [[b|B]] and [[c#d|E]]",
    "Mixed [[link]] and [md](url) content",
    "Nested [[dir/file|text]] paths [[other/dir/deep|deep]]",
    "```\n[[code block]]\n```\n[[outside]]",
  ];

  bodies.forEach((body, i) => {
    it(`body variant ${i + 1} has all wikilinks converted (outside code blocks)`, () => {
      const content = `---\nshare: true\n---\n${body}`;
      const result = transformFile(content, "test.md");
      assert.ok(result);
      const { body: resultBody } = splitFrontmatter(result);

      let inCode = false;
      resultBody.split("\n").forEach((line) => {
        if (line.trimStart().startsWith("```")) {
          inCode = !inCode;
          return;
        }
        if (!inCode) {
          assert.ok(
            !line.includes("[["),
            `Unconverted wikilink on line: "${line}"`,
          );
        }
      });
    });
  });
});

describe("property: addHardBreaks output lines end with two spaces", () => {
  const inputs = [
    "Single line",
    "Line 1\nLine 2\nLine 3",
    "With\n\nBlank lines",
    "Already trailing  \nMixed",
  ];

  inputs.forEach((input, i) => {
    it(`input variant ${i + 1}: every line ends with two spaces`, () => {
      const result = addHardBreaks(input);
      result.split("\n").forEach((line) => {
        assert.ok(
          line.endsWith("  "),
          `Line doesn't end with two spaces: "${line}"`,
        );
      });
    });
  });
});
