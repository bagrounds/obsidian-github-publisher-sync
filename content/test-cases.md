---
share: true
title: Test Cases for OG Image Caching
---

# Test Cases for OG Image Caching

This file documents the test cases created to validate the OG image caching implementation.

## Test 1: Modified Content File
- File: content/topics/pseudorange.md
- Change: Added "MODIFIED FOR TESTING" to the title
- Expected: Cache miss (content changed), regeneration

## Test 2: Deleted Content File
- File: content/topics/economics.md (to be deleted)
- Expected: OG image should not be published, removed from manifest

## Test 3: New Content File
- File: content/test-new-article.md (copied from pseudorange.md with modifications)
- Expected: Cache miss (new file), generation

## Test 4: File with No Title Change (edge case)
- File: content/test-edge-case-body-only.md
- Change: Only body content changes, title/description unchanged
- Expected: Cache hit (since only title+description affect OG image)
