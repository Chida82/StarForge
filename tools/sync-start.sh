#!/usr/bin/env bash
# Start a sync: branch sync/<sha7> from main, merge upstream/main, report conflicts.
# Usage: tools/sync-start.sh <child>
source "$(dirname "$0")/lib.sh"
name="${1:?usage: sync-start.sh <child>}"; require_child "$name"; dir="$(child_dir "$name")"
cd "$dir"
[ -z "$(git status --porcelain)" ] || die "$name has uncommitted changes; commit or stash first"
[ "$(git config rerere.enabled)" = "true" ] || die "rerere is not enabled in $name: git config rerere.enabled true"
git fetch -q upstream
sha7="$(git rev-parse --short=7 upstream/main)"
git checkout -q main
git checkout -q -b "sync/$sha7"
log "merging upstream/main ($sha7) into sync/$sha7"
if git merge --no-ff --no-edit -m "sync: upstream $sha7" upstream/main; then
    log "clean merge. Next: make test, tools/parity-check.sh $name, then tools/sync-finish.sh $name"
    exit 0
fi
echo
log "conflicts:"
git status --porcelain | grep -E '^(DU|UD|AU|UA|DD|AA|UU)' || true
echo
md="$(git status --porcelain | grep -cE '^(DU|UD)' || true)"
uu="$(git status --porcelain | grep -cE '^UU' || true)"
echo "modify/delete: $md  (run tools/rm-deleted-conflicts.sh $name)"
echo "content:       $uu  (rerere may have pre-resolved some: git rerere status; then edit, git add)"
echo "Then: git commit --no-edit ; make test ; tools/parity-check.sh $name ; tools/sync-finish.sh $name"
