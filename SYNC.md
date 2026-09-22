# SYNC — bring upstream commits into a child

Executable checklist. Run from the StarForge root unless a step says
`cd children/<child>`. Each step has a **Check**. Routine syncs (only
`only-removed` and `docs-only` commits, rerere resolves the rest) are safe for
a small model. Anything marked **HOT** needs reading `ds4.c` / `ds4_metal.m`:
escalate if unsure.

## 0. Preconditions

**One child at a time.** Every script below takes `<child>`; a sync creates a
branch, resolves conflicts and runs the oracle in one repo. There is no
"sync everything" command and there should not be one: children are
independent and a conflict in one must not block the others.

The two family-wide views:

```sh
tools/status.sh                       # all children: base, last tag, commits behind
tools/sync-preview.sh                 # no argument: preview for every cloned child
```

Then pick one child and follow the rest of this file with its name. The tools
prepare changes but do not commit. **Commit and push only after the user
explicitly requests each action.**

```sh
tools/status.sh                       # BEHIND > 0 for the child; DIRTY = no
```

**Check**: child has no uncommitted changes; `git -C children/<child> config rerere.enabled` = `true`.

## 1. Preview

```sh
tools/sync-preview.sh <child>         # or with no argument: every cloned child
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
tools/sync-start.sh <child>           # branch + merge in progress; never commits
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
  drop the rest. In every file that remains, place or update a one-line marker
  at the exact cut: `/* sf-ablate(<area>): <what was dropped; child invariant
  that makes it unnecessary> */`. This gives the next agent local context.
  Whole-file deletions get no marker-only replacement file.
- Conflict in **shared/live code** with no marker: this is real. Take
  upstream's change unless it re-introduces something the child removed (then
  it is the case above). If you cannot tell → **stop, ask**.
- Conflict in **Makefile**: our `BIN`/`SF_DEFS` block and target names win;
  upstream's new objects/targets are added if they concern kept code, dropped
  otherwise.
- Conflict in **`.md`**: apply the docs rule (SPEC §E): delete, don't adapt.

Then `git add <file>`. Do **not** commit yet: cleanup, tests and parity belong
to the reviewable sync result.

**Check**: `git diff --name-only --diff-filter=U` is empty; `MERGE_HEAD` exists;
every dropped upstream hunk in a live file has a marker.

## 5. Post-merge cleanup

Upstream may have added new files or new code paths that belong to a removed
area (a new `metal/glm53_x.metal`, a new `tests/test_cuda_y.c`, a new
`ds4_engine_is_<other>()` branch). Merge does not conflict on additions.

```sh
git diff --stat main..HEAD | grep -Ei 'cuda|rocm|agent|<other model tags>'   # new files to remove
make 2>&1 | grep -c unused-function                                            # new dead code
```

Remove and stage those additions as part of this sync resolution. Do not
commit yet.

**Check**: the grep above is empty; `make` has no `unused-function` warnings.

## 6. Verify

```sh
make clean && make && make test       # model-less, always
# model-backed (needs GGUF): the kept kernel/metal tests, ds4_test, eval smoke
cd ../.. && tools/parity-check.sh <child>
```

Run the model-backed suite **also in a worktree at the child's `main`**, and
compare: a sync's failures are only the ones the baseline does not already
have. `git worktree add --detach <tmp> main` costs one build and settles it
without guesswork.

Parity **must** be token-identical and within ±2% speed against upstream at
the **new** merge-base (the script computes it). A speed regression with
identical tokens means upstream changed something in shared code and the
child's ablation interacts with it: HOT → ask.

**Check**: `PARITY OK`.

## 7. Commit, land and tag

If the user now explicitly asks for the commit:

```sh
git add -A
git commit -m "sync: upstream <sha7>"
```

Without that explicit request, stop with the tested changes prepared.

Only after explicit requests: push the branch, open the PR (`sync: upstream
<sha7>`, body = the preview output plus any necessary conflict notes), merge
on GitHub, then explicitly authorize the tag push:

```sh
tools/sync-finish.sh <child> --push   # --push is mandatory
tools/status.sh                       # BEHIND = 0
```

No file records the new base: `README.md` and the child's `AGENTS.md` point at
`git describe --tags --match 'sync-*' --abbrev=0` and `git merge-base HEAD
upstream/main` instead of printing a SHA. If a child still inscribes one, this
is the step that replaces it with the derived form -- an inscribed SHA is a
second source of truth and the first sync makes it a lie (SPEC.md §A).

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
| `PARITY FAILED`, tokens identical, one prompt >2% slower | the speed gate reads a single run, and a prompt whose answer is a few tokens long has ±15% spread of its own | the script re-samples to a median of 5 and prints the run spread when a reading trips; a trip whose spread dwarfs the delta is noise. Do not widen the 2% threshold |
| `PARITY FAILED`, every prompt "produced no output", child stderr says "requires Metal" | `make cpu` linked the CPU-reference build over the four default binary names, and a later `make` relinked nothing: the binaries were newer than every object. This cost the first parity run of the 0aaea5a sync, and it had already cost hours once before — documenting it was not enough | `make clean && make` recovers the run. The fix is structural: give the CPU flavour its own names (`<bin>-cpu`, `-cpu-server`, `-cpu-bench`, `-cpu-eval`), as `sf-q3-8flash` now does. Never run `make cpu` between a build and a model-backed run |
| Parity passes against the *old* upstream | during a sync the child's `main` has not moved, so a base taken from `main` names the previous sync | `child_base_sha` reads `MERGE_HEAD` while a merge is prepared, so step 6 grades against the commit being landed. `tools/status.sh` keeps reporting the committed base and flags the prepared sync separately |
| Upstream renamed a `ds4_*` file | scheme at risk | **stop, ask**: follow rename in child vs freeze child at previous SHA |
| `sync-start.sh` refuses: dirty tree | local edits | `git stash` first, or ask the user to authorize a commit |
