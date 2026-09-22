# StarForge — orchestrator

StarForge turns [antirez/ds4](https://github.com/antirez/ds4) (DwarfStar, a
multi-model, multi-backend inference engine) into **one specialized repo per
model, Metal only**. Each specialized repo is a *child*. This folder is the
*orchestrator*: it holds the rules, the procedures, the tools and a read-only
mirror of upstream. It never contains inference code.

Duplication between children is accepted by design. The goal is that a person
or an agent can open **one child** and find everything needed for **one model**,
with nothing else in the way.

## Layout

```
AGENTS.md        this file: always loaded, short. Registry + rules + where to look.
SPEC.md          the law. Model-agnostic specification: what a child is, what it
                 keeps, what it removes, conventions. Read before any decision
                 not covered by a checklist.
BOOTSTRAP.md     executable checklist: create a new child from upstream.
SYNC.md          executable checklist: bring new upstream commits into a child.
README.md        human entry point: how to call things.
templates/       files copied into a child at bootstrap (AGENTS.md, ...).
tools/           scripts. Every procedure step that can be a script is one.
tools/parity/    prompt sets for the parity oracle, one file per child.
children/        plain git clones of the children (gitignored). Not submodules.
upstream/ds4/    plain full clone of upstream (gitignored). Read-only.
```

## Children registry

| Child | Model | Shape (`ds4.c`) | Port | Home | Lock | Vision | Spec-dec | Repo |
|---|---|---|---|---|---|---|---|---|
| `sf-ds4flash`   | DeepSeek V4 Flash     | `DS4_SHAPE_FLASH`   | 8001 | `~/.sf/ds4flash`   | `/tmp/sf-ds4flash.lock`   | no  | DSpark only (no legacy MTP) | `Chida82/sf-ds4flash` |
| `sf-ds4-1flash` | DeepSeek V4.1 Flash   | `DS4_SHAPE_FLASH41` | 8002 | `~/.sf/ds4-1flash` | `/tmp/sf-ds4-1flash.lock` | yes | none | `Chida82/sf-ds4-1flash` |
| `sf-glm5-3flash`| GLM 5.3 Flash         | `DS4_SHAPE_GLM53`   | 8003 | `~/.sf/glm5-3flash`| `/tmp/sf-glm5-3flash.lock`| yes | MTP  | `Chida82/sf-glm5-3flash` |
| `sf-q3-8flash`  | Qwen3.8 Flash Next    | `DS4_SHAPE_QWEN4_EXP` (+`QWEN4_MINI` for tests) | 8004 | `~/.sf/q3-8flash` | `/tmp/sf-q3-8flash.lock` | yes | MTP | `Chida82/sf-q3-8flash` |

Not managed (no child, code removed from every child): DeepSeek V4 Flash Vision
Experimental, DeepSeek V4 PRO, GLM 5.2, GLM 5.3 (non-Flash).

Bootstrap order: `sf-ds4flash` first (pilot), then the others. Where a child
currently stands relative to upstream is **not** recorded in a StarForge file:
a duplicated status ledger would go stale. Git is the source of truth; read
merge-bases and `sync-<sha7>` tags with `tools/status.sh`.

## Non-negotiable rules

1. **Never edit a child from the orchestrator.** Analyze here, work in
   `children/<name>` on a branch, land through that child's own PR flow.
2. **Never rename `ds4_*` source files inside a child.** File identity is what
   keeps `git merge upstream/main` working. Binary names change via the
   Makefile `BIN` variable, not via file renames.
3. **`git config rerere.enabled true` in every child, first thing.** Ablated
   regions conflict at every sync; rerere replays the resolution. This is the
   single most important mechanism in the whole plan.
4. **Steering stays in every child.** `--dir-steering-file`, `/steer`,
   `dir-steering/`. If the model does not support it, upstream's error stays.
5. **TP / RDMA / pipeline stay in every child.** The CPU reference path stays.
6. **Speculative decoding follows the registry exactly.** In particular,
   `sf-ds4flash` keeps DSpark and its separate 0731 support GGUF, but removes
   the legacy one-stage MTP path.
7. **Every child has no `ds4-agent`.** Four binaries: CLI, server, bench, eval.
8. **No on-disk path may collide with upstream ds4 or with another child.**
   Home, lock, history, default port are per child (see registry).
9. **Models come from the shared Hugging Face cache.** A child's `download.sh`
   uses `hf download`, makes component symlinks in `gguf/`, and a root default
   symlink for the main model; it never copies a GGUF into the repository. See
   SPEC.md §C.
10. **Delete, don't `#ifdef`.** A child is smaller code, not the same code
   behind flags. In files that remain, mark every non-obvious cut or sync
   resolution at the exact site. Format: `/* sf-ablate(<area>): <what was
   removed; why this child does not need it> */` (one source line). Never add
   marker-only replacement files for whole-file deletions: Git carries that
   history.
11. **Docs follow code.** A paragraph about a model, backend or binary that is
   not in the child is deleted, not adapted. All `.md` files are in English.
12. **Never `git merge -X ours`.** It silently drops upstream fixes.
13. **Attribution stays.** `LICENSE` untouched (includes the GGML notice);
    child README opens with the fork notice (SPEC.md §I).
14. **Never commit or push without an explicit user request.** Preparing or
    staging changes is allowed; a checklist saying "commit" is not permission.
15. **Names do not decide ownership; reachability does.** Upstream identifiers
    often carry the name of the model they were first written for (`glm_mtp` is
    the built-in MTP switch every MTP child uses). Before removing code because
    its name says "another model", prove it unreachable: constant-false
    predicate, `nm` showing no referrer, or a runtime probe. Each child records
    what it has established in its own `AGENTS.md` under "Names that lie"; at a
    sync, take upstream fixes to those families even when the name looks foreign.

    **A "names that lie" finding belongs to the child that established it, not
    to the family.** `glm_graph_*` is the shared Metal graph host in
    `sf-q3-8flash`, where Qwen3.8 runs on it. In `sf-ds4-1flash` it is dead
    code: `ds4_session_create` early-returns for `DS4_MODEL_FAMILY_DEEPSEEK41`
    into `ds41_graph_alloc`, and the `glm_graph` session opens only under
    `DS4_MODEL_FAMILY_GLM_DSA`. Carrying the sibling's rule across would have
    preserved ~45 dead kernels. Read a sibling's table as a list of questions to
    ask, never as a list of answers.
16. **The child exists to be cheap to read.** The goal is a tree an agent can
    load and reason about with the fewest tokens, so model-specific
    optimisation is fast and safe. Weigh that against sync cost: whole dead
    functions are worth a permanent conflict site, scattered dead conditionals
    usually are not. There is no sync ledger file: the `sf-ablate`/`sf-keep`
    marker at the cut and the commit message are the record.

17. **A sync can turn a child's passing test into a lie.** Upstream may narrow a
    predicate to exclude the very model a child kept: `d31089d` changed a
    streaming guard to `... && model_syntax != SERVER_MODEL_SYNTAX_QWEN`, and in
    a Qwen-only child, whose enum has that one value, the guard became
    unreachable. Two inherited tests asserted it fires and started failing.
    Neither the code nor the tests were wrong -- the child's single-model
    invariant met an upstream distinction drawn along the same line. When a test
    that passed before a sync fails after it, first ask whether the behaviour it
    asserts can still occur in this child; if it cannot, the test goes, with a
    marker saying which invariant killed it. Establish the pre-sync baseline by
    running the suite in a worktree at the child's `main`, rather than assuming
    which failures are pre-existing.

18. **A trap you can only document is a trap you will hit again.** Upstream's
    `make cpu` links the CPU-reference build over the same four binary names as
    the default build. make cannot tell the flavours apart, so afterwards a
    plain `make` relinks nothing and the next model-backed run dies with
    "requires Metal" — the binaries are newer than every object. This was found,
    written into the child's `AGENTS.md` and its release QA, and then hit again
    during the `0aaea5a` sync, where it produced a full parity failure that read
    like a regression. `make clean` recovers a run; only separate names
    (`<bin>-cpu*`) make the state unreachable, which is what the child now does.
    Prefer removing the failure mode over describing it: when a note has to say
    "remember to", the build should be doing it instead.

## Which file for which task

| Task | Read | Run |
|---|---|---|
| First time here / set up the folder | README.md | `tools/clone-all.sh` |
| Create a child | BOOTSTRAP.md (and SPEC.md §B–§E) | `tools/new-child.sh` then the checklist |
| See what upstream changed since a child last synced | SYNC.md step 1 | `tools/sync-preview.sh [child]` (no arg = all children) |
| Bring upstream commits into a child (**one child at a time**) | SYNC.md | `tools/sync-start.sh`, `tools/rm-deleted-conflicts.sh`, `tools/parity-check.sh`; only when explicitly requested: `tools/sync-finish.sh <child> --push` |
| Decide whether some code can be removed | SPEC.md §F | `make test` in the child, then `tools/parity-check.sh` |
| Where does each child stand | — (no status file by design) | `tools/status.sh` |
| Anything not covered above | SPEC.md, then ask | — |

## When to stop and ask a human

- A merge conflict inside `ds4.c` or `ds4_metal.m` touches code that is *not*
  clearly tagged for a removed model/backend and is not covered by rerere.
- `make test` passes but the parity oracle fails (token drift or >2% speed loss).
- Upstream renamed or split a `ds4_*` file.
- You are about to remove something listed in SPEC.md §B ("always kept").
- SPEC.md §F step 4: the doubt is high and no test resolves it. Leave the code, note it, ask.

Small models handle the routine (SYNC.md, BOOTSTRAP.md checklists). Anything
that requires reading `ds4.c` to decide is not routine.
