#!/usr/bin/env bash
set -euo pipefail

# Routes social media posting to the correct script.
# With --note or --date: targets a specific post via tweet-reflection.ts.
# Without args: uses BFS-based discovery via auto-post.ts.

NOTE="${1:-}"
DATE="${2:-}"

if [ -n "$NOTE" ] || [ -n "$DATE" ]; then
  ARGS=""
  [ -n "$NOTE" ] && ARGS="$ARGS --note $NOTE"
  [ -n "$DATE" ] && ARGS="$ARGS --date $DATE"
  exec npx tsx scripts/tweet-reflection.ts $ARGS
else
  exec npx tsx scripts/auto-post.ts
fi
