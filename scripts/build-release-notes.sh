#!/bin/bash
# Generates store-ready release notes from changes/pr-*.md files.
#
# Only counts files ADDED SINCE THE PREVIOUS RELEASE TAG, so the notes describe
# this release and nothing else.
#
# Why not just glob changes/: the release job deletes those files after a
# successful release, but that step pushes to a protected branch and the push
# can be rejected. It historically was, silently — no cleanup commit ever
# landed, so the files accumulated and a plain glob replayed every past
# release's notes. By v2.0.1+840 that was 50 files going back to PR #177.
#
# Scoping to the previous tag makes that impossible: even if cleanup never
# runs, notes stay correct and bounded. Cleanup becomes housekeeping rather
# than something correctness depends on.
#
# Targets bash 3.2 (stock macOS on the self-hosted runner): no mapfile, no
# associative arrays.

set -uo pipefail

CHANGES_DIR="changes"
FEATURES=""
FIXES=""
IMPROVEMENTS=""

# Newest existing release tag. At the point this runs the current release has
# not been tagged yet, so this resolves to the previous one.
PREV_TAG=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  PREV_TAG=$(git tag --list 'v*' --sort=-creatordate 2>/dev/null | head -1)
fi

# Collect the files this release should describe.
FILE_LIST=$(
  if [ -n "$PREV_TAG" ] && git rev-parse -q --verify "${PREV_TAG}^{commit}" >/dev/null 2>&1; then
    git diff --name-only --diff-filter=A "${PREV_TAG}..HEAD" -- "$CHANGES_DIR" 2>/dev/null \
      | grep -E "^${CHANGES_DIR}/pr-[0-9]+\.md$"
  else
    # No prior release (or not a git checkout): fall back to whatever is here.
    ls -1 "$CHANGES_DIR"/pr-*.md 2>/dev/null
  fi
)

while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      \[feature\]*)     FEATURES="$FEATURES\n• ${line#\[feature\] }" ;;
      \[fix\]*)         FIXES="$FIXES\n• ${line#\[fix\] }" ;;
      \[improvement\]*) IMPROVEMENTS="$IMPROVEMENTS\n• ${line#\[improvement\] }" ;;
      \[internal\]*)    ;; # never shown in store notes
      *)                IMPROVEMENTS="$IMPROVEMENTS\n• $line" ;;
    esac
  done < "$f"
done <<EOF
$FILE_LIST
EOF

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
