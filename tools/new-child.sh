#!/usr/bin/env bash
# Step 1 of BOOTSTRAP.md: create the child clone with remotes and rerere. Does NOT ablate.
# Usage: tools/new-child.sh <child> [github-org]
source "$(dirname "$0")/lib.sh"
name="${1:?usage: new-child.sh <child> [github-org]}"; require_upstream
registry_names | grep -qx "$name" || die "'$name' is not in the registry (tools/lib.sh / AGENTS.md)"
dir="$(child_dir "$name")"
[ -e "$dir" ] && die "$dir already exists"
org="${2:-}"
log "cloning upstream into $dir (full history)"
git clone -q "$UPSTREAM_DIR" "$dir"
cd "$dir"
git remote rename origin upstream
git remote set-url upstream "$UPSTREAM_URL"
git fetch -q upstream
git checkout -q -B main upstream/main
[ -n "$org" ] && git remote add origin "git@github.com:$org/$name.git"
git config rerere.enabled true
git config rerere.autoupdate true
base="$(git rev-parse --short=7 HEAD)"
git tag -a "sync-$base" -m "bootstrap base: upstream $base"
cp "$SF_ROOT/templates/child-AGENTS.md" AGENTS.md
sed -i '' -e "s/<CHILD>/$name/g" \
          -e "s/<SHAPE>/$(registry_field "$name" 2)/g" \
          -e "s/<PORT>/$(registry_field "$name" 3)/g" \
          -e "s#<HOME>#$(registry_field "$name" 4)#g" \
          -e "s#<LOCK>#$(registry_field "$name" 5)#g" \
          -e "s/<VISION>/$(registry_field "$name" 6)/g" \
          -e "s/<SPECDEC>/$(registry_field "$name" 7)/g" \
          -e "s/<BASE_SHA>/$base/g" AGENTS.md
cp "$SF_ROOT/tools/parity/$name.txt" tests/parity_prompts.txt 2>/dev/null || true
git add AGENTS.md tests/parity_prompts.txt 2>/dev/null || git add AGENTS.md
git commit -q -m "sf: bootstrap $name from upstream $base (AGENTS.md, rerere, tags)"
log "done. Base upstream $base. Continue with BOOTSTRAP.md step 2 in $dir"
[ -z "$org" ] && echo "note: no origin set. Create github.com/<org>/$name and: git remote add origin git@github.com:<org>/$name.git"
