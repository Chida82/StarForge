#!/usr/bin/env bash
# Classify upstream commits a child does not have yet, by the paths they touch.
#   only-removed : every touched path is absent in the child → will fall out as modify/delete
#   touches-live : touches ds4.c / ds4_metal.m / metal/ or other files the child keeps → read it
#   docs-only    : only .md files
# Usage: tools/sync-preview.sh [child]   (no argument: every cloned child, in registry order)
source "$(dirname "$0")/lib.sh"
if [ $# -eq 0 ]; then
    for c in $(registry_names); do
        [ -d "$(child_dir "$c")/.git" ] || continue
        "$0" "$c"; echo
    done
    exit 0
fi
name="$1"; require_child "$name"; dir="$(child_dir "$name")"
git -C "$dir" fetch -q upstream
range="main..upstream/main"
n="$(git -C "$dir" rev-list --count "$range")"
echo "$name: $n new upstream commit(s) in $range"
[ "$n" -eq 0 ] && exit 0
echo
git -C "$dir" rev-list --reverse "$range" | while read -r sha; do
    files="$(git -C "$dir" diff-tree --no-commit-id --name-only -r "$sha")"
    live=0; removed=0; docs=0; hot=0
    while read -r f; do
        [ -z "$f" ] && continue
        if [[ "$f" == *.md ]]; then docs=$((docs+1)); continue; fi
        if git -C "$dir" cat-file -e "main:$f" 2>/dev/null; then
            live=$((live+1))
            case "$f" in ds4.c|ds4_metal.m|metal/*|ds4.h|ds4_gpu.h) hot=$((hot+1));; esac
        else removed=$((removed+1)); fi
    done <<< "$files"
    if [ "$live" -eq 0 ] && [ "$docs" -eq 0 ]; then cls="only-removed"
    elif [ "$live" -eq 0 ]; then cls="docs-only"
    elif [ "$hot" -gt 0 ]; then cls="touches-live(HOT)"
    else cls="touches-live"; fi
    printf "%-18s %s %s\n" "$cls" "$(git -C "$dir" rev-parse --short=7 "$sha")" "$(git -C "$dir" log -1 --format=%s "$sha")"
    [ "$hot" -gt 0 ] && echo "$files" | grep -E '^(ds4\.c|ds4_metal\.m|metal/|ds4\.h|ds4_gpu\.h)' | sed 's/^/                   /'
done
echo
echo "HOT = touches ds4.c / ds4_metal.m / metal/ / ds4.h / ds4_gpu.h. Read those before merging."
