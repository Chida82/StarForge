#!/usr/bin/env bash
# Populate upstream/ds4 (full clone) and children/* (from the registry).
# Idempotent: existing clones are fetched, not re-cloned.
source "$(dirname "$0")/lib.sh"

if [ -d "$UPSTREAM_DIR/.git" ]; then
    log "upstream: fetch"; git -C "$UPSTREAM_DIR" fetch -q origin
else
    log "upstream: clone (full, needed to build any SHA for parity)"
    git clone -q "$UPSTREAM_URL" "$UPSTREAM_DIR"
fi

for name in $(registry_names); do
    repo="$(registry_field "$name" 8)"
    dir="$(child_dir "$name")"
    if [ -d "$dir/.git" ]; then
        log "$name: fetch origin + upstream"
        git -C "$dir" fetch -q origin; git -C "$dir" fetch -q upstream
    elif ! git ls-remote -q --exit-code "https://github.com/$repo.git" HEAD >/dev/null 2>&1; then
        log "$name: skipped (https://github.com/$repo not reachable: not created yet, or private and unauthenticated)"
    else
        log "$name: clone https://github.com/$repo.git"
        git clone -q "https://github.com/$repo.git" "$dir"
        git -C "$dir" remote add upstream "$UPSTREAM_URL"
        git -C "$dir" fetch -q upstream
        git -C "$dir" config rerere.enabled true
        git -C "$dir" config rerere.autoupdate true
    fi
done
