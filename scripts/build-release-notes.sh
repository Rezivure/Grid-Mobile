#!/bin/bash
# Generates release notes from changes/pr-*.md files
# Output: compact, store-ready release notes

CHANGES_DIR="changes"
NOTES=""
FEATURES=""
FIXES=""
IMPROVEMENTS=""

for f in "$CHANGES_DIR"/pr-*.md; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      \[feature\]*)   FEATURES="$FEATURES\n• ${line#\[feature\] }" ;;
      \[fix\]*)       FIXES="$FIXES\n• ${line#\[fix\] }" ;;
      \[improvement\]*) IMPROVEMENTS="$IMPROVEMENTS\n• ${line#\[improvement\] }" ;;
      \[internal\]*)  ;; # skip
      *)              IMPROVEMENTS="$IMPROVEMENTS\n• $line" ;;
    esac
  done < "$f"
done

# Build output
OUTPUT=""
if [ -n "$FEATURES" ]; then
  OUTPUT="${OUTPUT}What's New:${FEATURES}\n\n"
fi
if [ -n "$IMPROVEMENTS" ]; then
  OUTPUT="${OUTPUT}Improvements:${IMPROVEMENTS}\n\n"
fi
if [ -n "$FIXES" ]; then
  OUTPUT="${OUTPUT}Fixes:${FIXES}\n\n"
fi

if [ -z "$OUTPUT" ]; then
  echo "Bug fixes and performance improvements."
else
  echo -e "$OUTPUT" | sed '/^$/N;/^\n$/d' | head -20
fi
