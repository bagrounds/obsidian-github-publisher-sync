---
share: true
title: Edge Case - Body Content Changes
---

# Edge Case Test

This file tests that only title and description affect OG image cache.
If we modify the body content but keep title unchanged, it should be a cache hit.

## Original Content

This is the original body content that will not affect the OG image cache.

## Updated Content (After First Build)

This content was added AFTER the initial build to test that body-only changes
result in a cache hit (since title and description haven't changed).
Only title and description should affect OG image generation.

Additional paragraphs to make the change more significant...
More text...
Even more text...
