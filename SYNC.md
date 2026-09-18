# SYNC — bring upstream commits into a child

Executable checklist. Run from the StarForge root unless a step says
`cd children/<child>`. Each step has a **Check**. Routine syncs (only
`only-removed` and `docs-only` commits, rerere resolves the rest) are safe for
a small model. Anything marked **HOT** needs reading `ds4.c` / `ds4_metal.m`:
escalate if unsure.

## 0. Preconditions

```sh
tools/status.sh                       # BEHIND > 0 for the child; DIRTY = no
```

**Check**: child has no uncommitted changes; `git -C children/<child> config rerere.enabled` = `true`.

## 1. Preview

```sh
tools/sync-preview.sh <child>
```

Read the classification:

| Class | Meaning | Action |
|---|---|---|
| `only-removed` | every path is deleted in the child | nothing; falls out as modify/delete |
| `docs-only` | `.md` only | merge; trim paragraphs about removed things if any |
| `touches-live` | files the child keeps, not hot | merge; normal conflict handling |
| `touches-live(HOT)` | `ds4.c`, `ds4_metal.m`, `metal/`, `ds4.h`, `ds4_gpu.h` | **read the commit** (`git -C children/<child> show <sha>`) before merging. If it is about a removed model/backend, expect conflicts inside ablated regions (rerere). If it is shared code, expect a clean apply. If it is a rename/split of a `ds4_*` file → **stop, ask**. |

**Check**: you can say in one line per HOT commit what it does and whether it
concerns this child.

## 2. Start the merge

```sh
tools/sync-start.sh <child>           # branch sync/<sha7>, merge upstream/main, list conflicts
```

Clean merge → skip to step 5.

## 3. Resolve modify/delete

```sh
tools/rm-deleted-conflicts.sh <child> # keeps our deletions (DU). Reports UD for hand decision.
```

`UD` (upstream deleted a file we modified): almost always `git rm` it too. If
the child depends on it, that is a HOT decision → ask.

**Check**: `git -C children/<child> status --porcelain | grep -c '^DU'` = 0.

## 4. Resolve content conflicts

```sh
cd children/<child>
git rerere status                     # files rerere already resolved (staged if autoupdate)
git diff --name-only --diff-filter=U  # what is left
```

For each remaining file:

- Conflict **inside an ablated region** (you see `sf-ablate` markers nearby, or
  the upstream side is about a removed model/backend/agent): keep our side,
  drop theirs. If upstream's hunk contains a fix to code that *also* exists in
  the child (shared helper touched together with removed code): take the fix,
  drop the rest, extend the `sf-ablate` marker with one line saying what was
  dropped at sync `<sha7>`.
- Conflict in **shared/live code** with no marker: this is real. Take
  upstream's change unless it re-introduces something the child removed (then
  it is the case above). If you cannot tell → **stop, ask**.
- Conflict in **Makefile**: our `BIN`/`SF_DEFS` block and target names win;
  upstream's new objects/targets are added if they concern kept code, dropped
  otherwise.
- Conflict in **`.md`**: apply the docs rule (SPEC §E): delete, don't adapt.

Then `git add <file>` and, when none is left:

```sh
git commit --no-edit                  # keeps "sync: upstream <sha7>"
```

**Check**: `git status` clean; `git log -1 --format=%s` = `sync: upstream <sha7>`;
`git rerere gc` not needed; every dropped upstream hunk in a live file has a marker.

## 5. Post-merge cleanup

Upstream may have added new files or new code paths that belong to a removed
area (a new `metal/glm53_x.metal`, a new `tests/test_cuda_y.c`, a new
`ds4_engine_is_<other>()` branch). Merge does not conflict on additions.

```sh
git diff --stat main..HEAD | grep -Ei 'cuda|rocm|agent|<other model tags>'   # new files to remove
make 2>&1 | grep -c unused-function                                            # new dead code
```

Remove with `ablate(<area>): post-sync <sha7> …` commits on the same branch.

**Check**: the grep above is empty; `make` has no `unused-function` warnings.

## 6. Verify

```sh
make && make test                     # model-less, always
# model-backed (needs GGUF): the kept kernel/metal tests, ds4_test, eval smoke
cd ../.. && tools/parity-check.sh <child>
```

Parity **must** be token-identical and within ±2% speed against upstream at
the **new** merge-base (the script computes it). A speed regression with
identical tokens means upstream changed something in shared code and the
child's ablation interacts with it: HOT → ask.

**Check**: `PARITY OK`.

## 7. Land and tag

Push the branch, open the PR (`sync: upstream <sha7>`, body = the preview
output + notes on hand-resolved conflicts), merge on GitHub, then:

```sh
tools/sync-finish.sh <child>          # tag main sync-<sha7>, push tag, delete local branch
tools/status.sh                       # BEHIND = 0
```

Update `README.md` first line of the child ("Upstream base commit") if it
prints the SHA statically; prefer the `git describe` form from the template so
nothing needs updating.

**Check**: `git tag -l 'sync-*'` shows the new tag; `status.sh` BEHIND = 0.

## Cadence and multiple children

Sync children independently; there is no ordering constraint. A sync that is
HOT for one child (e.g. a Qwen kernel rewrite) is `only-removed` for the
others: do the easy ones first, they take minutes. Batch upstream commits:
syncing once a week is cheaper than once a commit, rerere does not care about
distance.

## Failure modes and what to do

| Symptom | Cause | Action |
|---|---|---|
| Dozens of conflicts in `ds4.c` on first sync | expected: rerere has nothing recorded yet | resolve once, carefully; next sync will be mostly automatic |
| Same conflicts again on the second sync | rerere not enabled or `.git/rr-cache` lost | `git config rerere.enabled true`; resolve; never delete `.git/rr-cache` |
| Merge clean, `make` fails | upstream added a call into removed code | find the caller, remove the call or the whole new path, `ablate(<area>): post-sync` |
| `make test` green, parity DIFF | ablation touched shared numerics, or upstream changed sampling | compare with `git bisect` between merge-base and HEAD on the child; ask if not obvious |
| Upstream renamed a `ds4_*` file | scheme at risk | **stop, ask**: follow rename in child vs freeze child at previous SHA |
| `sync-start.sh` refuses: dirty tree | local edits | commit or `git stash` first |
