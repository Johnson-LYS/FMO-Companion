#!/usr/bin/env bash
# Portable Loom-style documentation drift check for macOS and GNU/Linux.

set -euo pipefail

DOCS_DIR="docs"
MAIN_BRANCH="main"

if [ -f "CLAUDE.md" ]; then
    detected_branch=$(awk -F'|' '
        /Main branch|Main Branch/ {
            value=$3
            gsub(/[`[:space:]]/, "", value)
            if (value != "") { print value; exit }
        }
    ' CLAUDE.md 2>/dev/null || true)
    if [ -n "$detected_branch" ]; then
        MAIN_BRANCH="$detected_branch"
    fi
fi

date_to_epoch() {
    value="$1"
    if date -j -f "%Y-%m-%d" "$value" "+%s" >/dev/null 2>&1; then
        date -j -f "%Y-%m-%d" "$value" "+%s"
    elif date -d "$value" "+%s" >/dev/null 2>&1; then
        date -d "$value" "+%s"
    else
        return 1
    fi
}

stale_count=0
critical_count=0
today_epoch=$(date +%s)

if [ -d "$DOCS_DIR" ]; then
    while IFS= read -r -d '' file; do
        date_str=$(awk -F': *' '/^last-reviewed:/ { print $2; exit }' "$file")
        if [ -z "$date_str" ]; then
            continue
        fi

        doc_epoch=$(date_to_epoch "$date_str" 2>/dev/null || true)
        if [ -z "$doc_epoch" ]; then
            continue
        fi

        days_old=$(( (today_epoch - doc_epoch) / 86400 ))
        if [ "$days_old" -gt 90 ]; then
            critical_count=$((critical_count + 1))
        elif [ "$days_old" -gt 30 ]; then
            stale_count=$((stale_count + 1))
        fi
    done < <(find "$DOCS_DIR" -type f -name '*.md' -print0)
fi

changed_files=0
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

if [ -n "$current_branch" ] && [ "$current_branch" != "$MAIN_BRANCH" ]; then
    merge_base=$(git merge-base HEAD "$MAIN_BRANCH" 2>/dev/null || true)
    if [ -n "$merge_base" ]; then
        changed_files=$(git diff --name-only "$merge_base"..HEAD 2>/dev/null | wc -l | tr -d ' ')
    fi
fi

if [ "$stale_count" -eq 0 ] && [ "$critical_count" -eq 0 ] && [ "$changed_files" -lt 10 ]; then
    exit 0
fi

parts=()
if [ "$critical_count" -gt 0 ]; then
    parts+=("$critical_count docs critically stale (>90 days)")
fi
if [ "$stale_count" -gt 0 ]; then
    parts+=("$stale_count docs stale (>30 days)")
fi
if [ "$changed_files" -ge 10 ]; then
    parts+=("$changed_files files changed on branch '$current_branch'")
fi

message="Doc drift detected: "
for index in "${!parts[@]}"; do
    if [ "$index" -gt 0 ]; then
        message+=", "
    fi
    message+="${parts[$index]}"
done
message+=". Consider running the doc-drift-check skill for details."

escaped=${message//\\/\\\\}
escaped=${escaped//\"/\\\"}
printf '{"systemMessage":"%s"}\n' "$escaped"
