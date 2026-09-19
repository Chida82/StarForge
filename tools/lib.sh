# Shared helpers. Source, do not execute.
set -euo pipefail
SF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_URL="https://github.com/antirez/ds4.git"
UPSTREAM_DIR="$SF_ROOT/upstream/ds4"
CHILDREN_DIR="$SF_ROOT/children"

# Registry: name|shape|port|home|lock|vision|specdec|repo
# Keep in sync with AGENTS.md "Children registry". Repos are created as children are bootstrapped;
# clone-all.sh skips the ones that do not exist yet.
REGISTRY='
sf-ds4flash|DS4_SHAPE_FLASH|8001|~/.sf/ds4flash|/tmp/sf-ds4flash.lock|no|DSpark only (no legacy MTP)|Chida82/sf-ds4flash
sf-ds4-1flash|DS4_SHAPE_FLASH41|8002|~/.sf/ds4-1flash|/tmp/sf-ds4-1flash.lock|yes|none|Chida82/sf-ds4-1flash
sf-glm5-3flash|DS4_SHAPE_GLM53|8003|~/.sf/glm5-3flash|/tmp/sf-glm5-3flash.lock|yes|mtp|Chida82/sf-glm5-3flash
sf-q3-8flash|DS4_SHAPE_QWEN4_EXP|8004|~/.sf/q3-8flash|/tmp/sf-q3-8flash.lock|yes|mtp|Chida82/sf-q3-8flash
'

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

registry_names() { echo "$REGISTRY" | awk -F'|' 'NF{print $1}'; }
registry_field() { # name field-index(1-based)
    echo "$REGISTRY" | awk -F'|' -v n="$1" -v i="$2" '$1==n{print $i}'
}
child_dir() { echo "$CHILDREN_DIR/$1"; }
require_child() {
    [ -d "$(child_dir "$1")/.git" ] || die "child '$1' not cloned at $(child_dir "$1") (run tools/clone-all.sh)"
}
require_upstream() {
    [ -d "$UPSTREAM_DIR/.git" ] || die "upstream not cloned at $UPSTREAM_DIR (run tools/clone-all.sh)"
}
# Upstream SHA a child is based on: merge-base of its main with upstream/main.
child_base_sha() { git -C "$(child_dir "$1")" merge-base main upstream/main; }
# Latest sync tag, if any.
child_last_sync_tag() { git -C "$(child_dir "$1")" tag -l 'sync-*' --sort=-creatordate | head -1; }
