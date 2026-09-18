#!/usr/bin/env bash
# After a sync branch is merged into main on GitHub: tag main with sync-<sha7>, push tag.
# Run this AFTER the PR is merged. Usage: tools/sync-finish.sh <child>
source "$(dirname "$0")/lib.sh"
name="${1:?usage: sync-finish.sh <child>}"; require_child "$name"; cd "$(child_dir "$name")"
git fetch -q origin; git checkout -q main; git pull -q --ff-only origin main
sha7="$(git rev-parse --short=7 "$(git merge-base main upstream/main)")"
tag="sync-$sha7"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then log "$tag already exists"; exit 0; fi
git tag -a "$tag" -m "synced with upstream $sha7"
git push -q origin "$tag"
log "tagged main as $tag and pushed"
git branch -d "sync/$sha7" 2>/dev/null && log "deleted local branch sync/$sha7" || true
