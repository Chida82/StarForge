#!/usr/bin/env bash
# Resolve modify/delete conflicts where the child deleted the file: keep it deleted.
# (Upstream touched a file this child removed. The deletion wins by definition, SPEC §A.)
# Usage: tools/rm-deleted-conflicts.sh <child>
source "$(dirname "$0")/lib.sh"
name="${1:?usage: rm-deleted-conflicts.sh <child>}"; require_child "$name"; cd "$(child_dir "$name")"
n=0
while read -r st path; do
    # DU = deleted by us (child), modified by them (upstream)
    [ "$st" = "DU" ] || continue
    git rm -q --cached -- "$path" 2>/dev/null || true
    rm -f -- "$path"
    echo "kept deleted: $path"; n=$((n+1))
done < <(git status --porcelain | grep -E '^(DU) ' | sed -E 's/^(..) (.*)$/\1 \2/')
echo "$n modify/delete conflict(s) resolved as deletions."
ud="$(git status --porcelain | grep -cE '^UD' || true)"
[ "$ud" -gt 0 ] && echo "note: $ud file(s) deleted by UPSTREAM but modified in child (UD). Decide by hand: usually git rm them too, unless the child depends on them."
exit 0
