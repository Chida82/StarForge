#!/usr/bin/env bash
# Where does each child stand relative to upstream/main.
source "$(dirname "$0")/lib.sh"
require_upstream
git -C "$UPSTREAM_DIR" fetch -q origin
up="$(git -C "$UPSTREAM_DIR" rev-parse --short=7 origin/main)"
echo "upstream/main: $up ($(git -C "$UPSTREAM_DIR" log -1 --format=%cs origin/main))"
printf "%-16s %-9s %-14s %-8s %s\n" CHILD BASE LAST_SYNC_TAG BEHIND DIRTY
for name in $(registry_names); do
    dir="$(child_dir "$name")"
    if [ ! -d "$dir/.git" ]; then printf "%-16s %s\n" "$name" "(not cloned)"; continue; fi
    git -C "$dir" fetch -q upstream 2>/dev/null || true
    base="$(git -C "$dir" rev-parse --short=7 "$(child_base_sha "$name")")"
    tag="$(child_last_sync_tag "$name")"; tag="${tag:--}"
    behind="$(git -C "$dir" rev-list --count main..upstream/main)"
    dirty="$([ -n "$(git -C "$dir" status --porcelain)" ] && echo yes || echo no)"
    printf "%-16s %-9s %-14s %-8s %s\n" "$name" "$base" "$tag" "$behind" "$dirty"
done
