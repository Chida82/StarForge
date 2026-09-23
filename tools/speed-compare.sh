#!/usr/bin/env bash
# Compare generation and prefill speed of a child against upstream at the
# child's base, with the same bench sweep on both binaries.
#
# Usage: tools/speed-compare.sh <child> <model.gguf>
#
# Protocol: the child runs first, then the machine rests SF_SPEED_COOLDOWN
# seconds (default 180) so SSD and thermals settle, then upstream runs. The
# child running first is the conservative order: it gets the colder file cache.
#
#   SF_SPEED_FLAGS     extra flags for both benches (default: --ssd-streaming)
#   SF_SPEED_COOLDOWN  seconds between the two runs (default: 180)
#   SF_SPEED_ARGS      sweep (default: --ctx-start 2048 --ctx-max 32768
#                      --step-mul 2 --gen-tokens 128, about 4 minutes per run
#                      on an M-series Mac with V4.1 Q2 streamed from SSD)
#
# Output: tools/speed/out/<child>-<date>/{child,upstream}.csv plus a table of
# per-frontier deltas. Informational: it does not gate anything.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
name="${1:?usage: speed-compare.sh <child> <model.gguf>}"; require_child "$name"; require_upstream
model="${2:?usage: speed-compare.sh <child> <model.gguf>}"
model="$(cd "$(dirname "$model")" && pwd)/$(basename "$model")"
flags="${SF_SPEED_FLAGS:---ssd-streaming}"
cooldown="${SF_SPEED_COOLDOWN:-180}"
sweep="${SF_SPEED_ARGS:---ctx-start 2048 --ctx-max 32768 --step-mul 2 --gen-tokens 128}"
dir="$(child_dir "$name")"
base="$(child_base_sha "$name")"
out="$SF_ROOT/tools/speed/out/$name-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$out"

log "building child bench ($name @ $(git -C "$dir" rev-parse --short=7 HEAD))"
( cd "$dir" && make -s -j "$name-bench" ) || die "child bench build failed"
wt="$SF_ROOT/upstream/.worktrees/$(git -C "$UPSTREAM_DIR" rev-parse --short=7 "$base")"
if [ ! -d "$wt" ]; then
    mkdir -p "$(dirname "$wt")"
    git -C "$UPSTREAM_DIR" worktree add -q --detach "$wt" "$base"
fi
log "building upstream bench @ $(git -C "$UPSTREAM_DIR" rev-parse --short=7 "$base")"
( cd "$wt" && make -s -j ds4-bench ) || die "upstream bench build failed"

run() {   # tree binary csv log
    # shellcheck disable=SC2086
    ( cd "$1" && /usr/bin/time -p "$2" -m "$model" $flags \
        --prompt-file "$dir/speed-bench/promessi_sposi.txt" $sweep --csv "$3" ) > "$4" 2>&1
}
log "child run ($flags $sweep)"
run "$dir" "$dir/$name-bench" "$out/child.csv" "$out/child.log" || die "child bench failed, see $out/child.log"
log "cooldown ${cooldown}s"
sleep "$cooldown"
log "upstream run"
run "$wt" "$wt/ds4-bench" "$out/upstream.csv" "$out/upstream.log" || die "upstream bench failed, see $out/upstream.log"

echo
awk -F, 'FNR == 1 { next }
         FNR == NR { up_pf[$1] = $3; up_gen[$1] = $8; next }
         ($1 in up_pf) {
             printf "ctx %6s  prefill up %7.1f child %7.1f (%+6.1f%%)   decode up %5.2f child %5.2f (%+6.1f%%)\n",
                 $1, up_pf[$1], $3, ($3 - up_pf[$1]) / up_pf[$1] * 100,
                 up_gen[$1], $8, ($8 - up_gen[$1]) / up_gen[$1] * 100 }' \
    "$out/upstream.csv" "$out/child.csv" | tee "$out/summary.txt"
log "wall time: child $(awk '/^real/ {print $2}' "$out/child.log")s, upstream $(awk '/^real/ {print $2}' "$out/upstream.log")s → $out"
