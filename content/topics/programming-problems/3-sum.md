---
share: true
title: 🔢➕➕ 3 Sum
aliases:
  - 🔢➕➕ 3 Sum
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-20T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
URL: https://bagrounds.org/topics/programming-problems/3-sum
updated: 2026-06-09T11:17:18
---
[Home](../../index.md) > [Topics](../index.md) > [Programming Problems](./index.md)  
# 🔢➕➕ 3 Sum  
## Problem Statement  
Given an array of integers, return 3 integers that sum to zero if possible.  
  
## Clarifications  
1. If multiple solutions exist, return any of them  
2. Each element can only be used once  
  
## Examples  
0 0 0 -> 0 0 0  
0 0 -> None  
1 0 1 -> None  
-1 0 1 -> -1 0 1  
-1 5 1 6 0 -> -1 1 0  
  
## Potential Solutions  
### Brute Force  
#### Algorithm  
1. Generate all possible triples  
2. Compute the sum of each  
3. When finding a triple that sums to zero, return it  
4. If none is found, indicate as much  
#### Time Complexity  
To generate all triples, use 3 nested for-loops  
O(N^3)  
#### Space Complexity  
There's no need to store the triples, as we'll return as soon as we find one.  
O(1)  
  
### 1 + Naive 2 Sum  
#### Algorithm  
1. For each integer i, examine the remaining integers looking for 2 that sum to -i  
2. As each integer is examined, it never needs to be examined again, thus each iteration gets smaller  
3.   
  
#### Time Complexity  
O(N) + O(N - 1) + O(N - 2) + ... + O(1)  
= O(N + N - 1 + N - 2 + ... + 1)  
* Sum of integers from 1 to n: S(N) = N * (N + 1) / 2 = (N^2 + N)/2  
= O((N^2 + N)/2)  
= O(N^2 + N)  
= O(N^2)  
-1 5 1 6 0 -> -1 1 0  
  
A = -1  
B = 5  
5 + 1 = 6 != 1  
5 + 6 = 11 != 1  
5 + 0 = 5 != 1  
=> No solution for -1,5 exists  
B = 1  
1 + 6 = 7 != 1  
1 + 0 = 1 == 1  
=> Solution found!  
  
### O(N^2 * log(N)) - Presort; 2-sum binary search  
1. O(N * log(N)) - Sort the input array  
2. O(N^2 * log(N)) - For each element A, search for 2-sum = -A; -A = (B + C)  
  1.  O(N * log(N)) - 2-sum: for each element B, binary-search for C = -A - B  
      1. O(log(N)) - binary-search  
// log(N) + log(N - 1) + ... + log(1)  
Fact: log(M) + log(N) = log(M * N)  
// Sum i=1 -> N { log(i) } = log(N!)  
Stirling's approximation: log(N!) = N * log(N) - N  
  
#### Example 1  
```  
I = -1 5 1 6 0  
S = -1 0 1 5 6  
A = -1  
B = 0  
0 + 1 = 1 == 1  
```  
=> Solution found! (-1,0,1)  
  
#### Example 2  
```  
I = -11 5 1 6 0  
S = -11 0 1 5 6  
A = -11  
B = 0  
0 + 1 = 1 != 11  
0 + 5 = 5 != 11  
0 + 6 = 6 != 11  
```  
=> No solution exists for -11,0  
```  
B = 1  
1 + 5 = 6 != 11  
1 + 6 = 7 != 11  
```  
=> No solution exists for -11,1  
```  
B = 5  
5 + 6 = 11 == 11  
```  
=> Solution found! (-11,5,6)  
  
#### Example 3  
```  
I = -11 5 -12 6 -13  
S = -13 -12 -11 5 6  
A = -13  
B = -12  
-12 + -11 = -23 != 13  
-12 + 5 = -7 != 13  
-12 + 6 = -1 != 13  
```  
=> No solution exists for -13,-12  
```  
B = -11  
-11 + 5 = -6 != 13  
-11 + 6 = -5 !+ 13  
```  
=> No solution exists for -13,-11  
```  
B = 5  
5 + 6 = 11 != 13  
```  
=> No solution exists for -13,5  
=> No solution exists for -13  
```  
A = -12  
B = -11  
-11 + 5 = -6 != 12  
-11 + 6 = -5 != 12  
```  
=> No solution exists for -12,-11  
```  
B = 5  
5 + 6 = 11 != 12  
```  
=> No solution exists for -12,5  
=> No solution exists for -12  
```  
A = -11  
B = 5  
5 + 6 = 11 == 11  
```  
=> Solution found! (-11,5,6)  
  
### 1 + 2-pointer 2-sum  
#### Algorithm  
1. O(N * log(N)) - Sort the input array  
2. O(N^2) - For each element A of the input array, find the 2-sum of the remaining array equal to -A  
  1. O(N) - 2-sum: Using 2 pointers starting at beginning and end, iterate forward and backward as the sum toggles greater and less than the target  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mnrfoyin222u" data-bluesky-cid="bafyreiabh2cnyudeexbg36m446z7asr2vfn4rnhyv7p5wwfcdfoldpxom4"><p>🔢➕➕ 3 Sum  
  
#AI Q: 💻 Prefer brute force speed or elegant optimization when solving complex problems?  
  
💻 Algorithm Design | ⏱️ Big O Analysis | 🎯 Two-Pointer Technique  
https://bagrounds.org/topics/programming-problems/3-sum</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mnrfoyin222u?ref_src=embed">2026-06-08T09:48:33.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116719868072652066/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116719868072652066" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>