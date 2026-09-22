#!/usr/bin/env bash
# After a sync PR is merged: tag main and push the tag. Explicit --push is mandatory.
# Usage: tools/sync-finish.sh <child> --push
source "$(dirname "$0")/lib.sh"
name="${1:?usage: sync-finish.sh <child> --push}"
[ "${2:-}" = "--push" ] || die "refusing to push without explicit --push: sync-finish.sh <child> --push"
require_child "$name"; cd "$(child_dir "$name")"
git fetch -q origin; git checkout -q main; git pull -q --ff-only origin main
sha7="$(git rev-parse --short=7 "$(git merge-base main upstream/main)")"
tag="sync-$sha7"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    log "$tag already exists locally"
else
    git tag -a "$tag" -m "synced with upstream $sha7"
fi
git push -q origin "$tag"
log "pushed $tag"
git branch -d "sync/$sha7" 2>/dev/null && log "deleted local branch sync/$sha7" || true
