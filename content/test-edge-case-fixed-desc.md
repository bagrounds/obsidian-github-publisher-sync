---
share: true
title: Edge Case - Fixed Description
description: This is a fixed description that won't change
---

# Edge Case Test - Fixed Description

This file has an explicit description in frontmatter.
If we modify the body content but keep title and description unchanged in frontmatter,
it should be a cache hit.

## Original Content

This is the original body content. Changing this should NOT affect the OG image cache
because the description is explicitly set in frontmatter.

## Updated Content (After First Build)

This content was added AFTER the initial build to test that body-only changes
result in a cache hit when description is fixed in frontmatter.

Additional paragraphs to make the change more significant...
More text about various topics...
Even more content that shouldn't affect the OG image...
Final paragraph with lots of words...
