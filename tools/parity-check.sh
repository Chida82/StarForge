#!/usr/bin/env bash
# Parity oracle: upstream at the child's merge-base vs the child, same GGUF, same prompts,
# greedy. Output must be token-identical; tokens/s within ±2%.
# Usage: tools/parity-check.sh <child> [path/to/model.gguf]
#   MODEL defaults to the first GGUF in the child. Prompts: the child's
#   tests/parity_prompts.txt (created from tools/parity/<child>.txt at bootstrap).
#   Extra per-prompt flags may follow a TAB (e.g. steering, DSpark, MTP).
source "$(dirname "$0")/lib.sh"
name="${1:?usage: parity-check.sh <child> [model.gguf]}"; require_child "$name"; require_upstream
dir="$(child_dir "$name")"
prompts="$dir/tests/parity_prompts.txt"
[ -f "$prompts" ] || prompts="$SF_ROOT/tools/parity/$name.txt"
[ -f "$prompts" ] || die "no prompt set for $name"
model="${2:-}"
if [ -z "$model" ]; then
    model="$(ls "$dir"/*.gguf 2>/dev/null | head -1)"; [ -n "$model" ] || die "no .gguf in $dir; pass the model path"
fi
model="$(cd "$(dirname "$model")" && pwd)/$(basename "$model")"
base="$(child_base_sha "$name")"
out="$SF_ROOT/tools/parity/out/$name-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$out"

log "building child ($name @ $(git -C "$dir" rev-parse --short=7 HEAD))"
( cd "$dir" && make -s -j ) || die "child build failed"
child_bin="$(ls "$dir"/sf-* 2>/dev/null | grep -vE -- '-(server|bench|eval)$' | head -1)"
[ -x "$child_bin" ] || die "child CLI binary not found in $dir"

log "building upstream baseline @ $(git -C "$UPSTREAM_DIR" rev-parse --short=7 "$base") in a worktree"
wt="$SF_ROOT/upstream/.worktrees/$(git -C "$UPSTREAM_DIR" rev-parse --short=7 "$base")"
if [ ! -d "$wt" ]; then
    mkdir -p "$(dirname "$wt")"
    git -C "$UPSTREAM_DIR" worktree add -q --detach "$wt" "$base"
fi
( cd "$wt" && make -s -j ds4 ) || die "upstream build failed"
up_bin="$wt/ds4"

fail=0; i=0
while IFS=$'\t' read -r prompt extra; do
    [ -z "$prompt" ] && continue; [[ "$prompt" == \#* ]] && continue
    i=$((i+1))
    # Both binaries load their .metal sources relative to the working directory,
    # so each one runs from its own tree. Any relative path in the extra flags
    # (a steering vector, say) belongs to the child and is made absolute first,
    # because the upstream tree does not carry the child's files.
    extra_abs=""
    for tok in $extra; do
        case "$tok" in
            /*|-*) extra_abs="$extra_abs $tok" ;;
            *) [ -e "$dir/$tok" ] && extra_abs="$extra_abs $dir/$tok" || extra_abs="$extra_abs $tok" ;;
        esac
    done
    # shellcheck disable=SC2086
    ( cd "$wt"  && "$up_bin"    -m "$model" --temp 0 --nothink -n 128 $extra_abs -p "$prompt" ) > "$out/$i.up.txt"    2> "$out/$i.up.err" || true
    # shellcheck disable=SC2086
    ( cd "$dir" && "$child_bin" -m "$model" --temp 0 --nothink -n 128 $extra_abs -p "$prompt" ) > "$out/$i.child.txt" 2> "$out/$i.child.err" || true
    if [ ! -s "$out/$i.up.txt" ] || [ ! -s "$out/$i.child.txt" ]; then
        echo "  [FAIL] $i: $prompt  → a binary produced no output, see $out/$i.*.err"; fail=1
    elif cmp -s "$out/$i.up.txt" "$out/$i.child.txt"; then
        echo "  [ok ] $i: $prompt"
    else
        echo "  [DIFF] $i: $prompt  → diff $out/$i.up.txt $out/$i.child.txt"; fail=1
    fi
    # tokens/s: both binaries print generation speed on stderr; compare if both parse.
    ut="$(grep -oE '[0-9.]+ t/s' "$out/$i.up.err" | tail -1 | cut -d' ' -f1 || true)"
    ct="$(grep -oE '[0-9.]+ t/s' "$out/$i.child.err" | tail -1 | cut -d' ' -f1 || true)"
    if [ -n "$ut" ] && [ -n "$ct" ]; then
        awk -v u="$ut" -v c="$ct" -v i="$i" 'BEGIN{ d=(c-u)/u*100; printf "        speed %s: up %.1f t/s, child %.1f t/s (%+.1f%%)%s\n", i, u, c, d, (d<-2?"  ← SLOWER >2%":"") ; if (d<-2) exit 3 }' || fail=1
    fi
done < "$prompts"
echo
[ "$fail" -eq 0 ] && log "PARITY OK ($i prompts) → $out" || { log "PARITY FAILED → $out"; exit 1; }
