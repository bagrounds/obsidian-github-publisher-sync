---
share: true
aliases:
  - "2026-04-16 | 🛡️ Data Loss Prevention in Daily Updates 🔗"
title: "2026-04-16 | 🛡️ Data Loss Prevention in Daily Updates 🔗"
URL: https://bagrounds.org/ai-blog/2026-04-16-1-data-loss-prevention-daily-updates
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-16 | 🛡️ Data Loss Prevention in Daily Updates 🔗

## 🐛 The Problem

📉 Overnight, the daily reflection Updates table dropped from 31 entries down to 2. 🗑️ The automation silently replaced the entire section with only the new incoming entries, discarding everything that was already there.

## 🔍 Root Cause

🪑 The bug was whitespace-sensitive header detection in the table parser. 📐 The automation writes compact tables like pipe Page pipe emoji pipe, but Obsidian auto-formats tables with column-width padding when you view or edit them on the phone. 📱 After Obsidian reformatted and synced the padded table back to the vault, the header became pipe Page followed by dozens of spaces then pipe, which no longer matched the exact substring pipe Page pipe that the parser was checking for.

### 🔗 The Chain of Events

📝 Here is the exact sequence, reconstructed from Obsidian file version history and GitHub Actions run logs.

🕐 At some point before 11:27 PM Pacific on April 15, Obsidian on the phone auto-formatted the updates table with column-width padding and synced it to the vault. 📊 The table had 31 entries and 4 columns, with each row padded to align with the widest entry.

🕚 At 11:27 PM, a manual workflow dispatch (run number 546) started. 🔄 It pulled the vault with the padded table. ❌ The parser looked for the header cell Page surrounded by vertical bars with single spaces, but the padded header had dozens of spaces between Page and the next vertical bar. 🚫 The check failed, so the parser fell through to the bullet-list parser, which found nothing. 📭 With zero parsed entries, the merge produced only the new entries from that run.

🕦 At 11:36 PM, while run 546 was still running, the scheduled hourly run (number 547) also started. 📥 It pulled the same padded vault. ❌ The same parser failure occurred.

🕐 At approximately 11:47 PM, run 546 finished and pushed its vault changes, containing only its new entries.

🕐 At 11:52 PM, run 547 finished and pushed its vault changes, overwriting run 546. 📉 The result was 2 entries, matching exactly the number of new entries from run 547.

### 📊 Evidence

🔢 GHA run durations from the last 30 scheduled runs averaged 16.3 minutes with a maximum of 26.2 minutes, well under the hourly interval. ⚠️ The overlap was caused by a manual dispatch (run 546, 20 minutes) starting 9 minutes before the scheduled run (547, 16.5 minutes). 🔄 Both runs pulled the same vault snapshot, both failed to parse, and the last writer won.

📋 The Obsidian file version history confirms the BEFORE state had 31 entries in a padded table and the AFTER state (at 11:52 PM) had exactly 2 entries.

## 🛠️ The Fixes

### 🔧 Whitespace-Insensitive Header Detection

🔄 Replaced all three occurrences of the exact substring check with a new isPageHeaderLine function that splits the line by pipe characters, strips each cell, and checks whether any cell equals Page. ✅ This correctly matches both compact tables and Obsidian-formatted tables with any amount of column padding.

### 🔒 Concurrency Group

🚫 Added a concurrency group to the scheduled workflow so that only one run executes at a time. ⏳ With cancel-in-progress set to false, a queued run waits for the current one to finish rather than canceling it. 🛡️ This prevents the last-writer-wins race condition that compounded the data loss.

### 🛡️ Stats-Based Safety Check

📊 The parseStatsPageCount function extracts the expected page count from the stats line. 🚦 If zero entries were parsed but the stats line indicates entries should exist, addUpdateLinks returns the content unchanged. 📝 The I/O wrapper logs a warning when this fires, making the issue visible for diagnosis.

### 🔗 Defensive Markdown Link Parsing

🆕 As an additional defensive measure, the parser now also supports standard markdown link syntax alongside wiki links. 🧩 This prevents data loss if links are ever converted to a different format by any process.

## 🧪 Testing

✅ Seven test cases cover the changes. 📐 A new test uses an Obsidian-formatted table with padded columns and verifies all entries are preserved when adding new ones. 🛡️ Unparseable rows with a nonzero stats count trigger the safety check. 🔗 Standard markdown links are preserved when adding new entries. 🔤 Escaped pipes in markdown link titles parse correctly. 📊 Stats page count extraction handles various formats. 🗺️ Relative path resolution handles dot-slash, dot-dot-slash, and bare paths. 🔀 Mixed wiki and markdown link tables merge correctly.

## 💡 Lessons Learned

📐 Never use exact substring matching for structured text that external tools might reformat. 🔒 Concurrent vault access needs mutual exclusion, even when runs rarely overlap. 🔍 Cross-referencing GHA logs with Obsidian file version history timestamps was essential to reconstructing the actual sequence of events. 🛡️ Defense in depth matters: the header fix prevents the parser failure, the concurrency group prevents the race condition, and the stats safety check prevents data loss from any future parsing failure.

## 📚 Book Recommendations

### 📖 Similar
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it explores how concurrent writes, last-writer-wins conflicts, and data integrity challenges arise in distributed systems, directly paralleling the vault sync race condition found here.
* Release It! by Michael T. Nygard is relevant because it catalogs production failure patterns like race conditions and cascading failures, and prescribes stability patterns such as bulkheads and timeouts that echo the concurrency group fix.

### ↔️ Contrasting
* Move Fast and Break Things by Jonathan Taplin offers a contrasting philosophy where speed is prioritized over safety, the opposite of the defense-in-depth approach taken here where we added three independent safeguards.

### 🔗 Related
* The Pragmatic Programmer by David Thomas and Andrew Hunt is related because it emphasizes defensive programming, tracer bullets, and the principle of least surprise, all of which informed the approach of fixing the parser while also adding safety nets.
