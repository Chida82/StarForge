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
templates/       files copied into a child at bootstrap (child AGENTS.md, ...).
tools/           scripts. Every procedure step that can be a script is one.
tools/parity/    prompt sets for the parity oracle, one file per child.
children/        plain git clones of the children (gitignored). Not submodules.
upstream/ds4/    plain full clone of upstream (gitignored). Read-only.
```

## Children registry

| Child | Model | Shape (`ds4.c`) | Port | Home | Lock | Vision | Spec-dec | Repo |
|---|---|---|---|---|---|---|---|---|
| `sf-ds4flash`   | DeepSeek V4 Flash     | `DS4_SHAPE_FLASH`   | 8001 | `~/.sf/ds4flash`   | `/tmp/sf-ds4flash.lock`   | no  | none | `<ORG>/sf-ds4flash` |
| `sf-ds4-1flash` | DeepSeek V4.1 Flash   | `DS4_SHAPE_FLASH41` | 8002 | `~/.sf/ds4-1flash` | `/tmp/sf-ds4-1flash.lock` | yes | none | `<ORG>/sf-ds4-1flash` |
| `sf-glm5-3flash`| GLM 5.3 Flash         | `DS4_SHAPE_GLM53`   | 8003 | `~/.sf/glm5-3flash`| `/tmp/sf-glm5-3flash.lock`| yes | MTP  | `<ORG>/sf-glm5-3flash` |
| `sf-q3-8flash`  | Qwen3.8 Flash Next    | `DS4_SHAPE_QWEN4_EXP` (+`QWEN4_MINI` for tests) | 8004 | `~/.sf/q3-8flash` | `/tmp/sf-q3-8flash.lock` | yes | MTP | `<ORG>/sf-q3-8flash` |

Not managed (no child, code removed from every child): DeepSeek V4 Flash Vision
Experimental, DeepSeek V4 PRO, GLM 5.2, GLM 5.3 (non-Flash).

Bootstrap order: `sf-ds4flash` first (pilot), then the others. Where a child
currently stands relative to upstream is **not** recorded here: read its
`sync-<sha7>` tags (`tools/status.sh`).

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
6. **Every child has no `ds4-agent`.** Four binaries: CLI, server, bench, eval.
7. **No on-disk path may collide with upstream ds4 or with another child.**
   Home, lock, history, default port are per child (see registry).
8. **Delete, don't `#ifdef`.** A child is smaller code, not the same code
   behind flags. Mark in-file cuts with `/* sf-ablate(<area>): ... */`.
9. **Docs follow code.** A paragraph about a model, backend or binary that is
   not in the child is deleted, not adapted. All `.md` files are in English.
10. **Never `git merge -X ours`.** It silently drops upstream fixes.
11. **Attribution stays.** `LICENSE` untouched (includes the GGML notice);
    child README opens with the fork notice (SPEC.md §I).

## Which file for which task

| Task | Read | Run |
|---|---|---|
| First time here / set up the folder | README.md | `tools/clone-all.sh` |
| Create a child | BOOTSTRAP.md (and SPEC.md §B–§E) | `tools/new-child.sh` then the checklist |
| See what upstream changed since a child last synced | SYNC.md step 1 | `tools/sync-preview.sh <child>` |
| Bring upstream commits into a child | SYNC.md | `tools/sync-start.sh`, `tools/rm-deleted-conflicts.sh`, `tools/parity-check.sh`, `tools/sync-finish.sh` |
| Decide whether some code can be removed | SPEC.md §F | `make test` in the child, then `tools/parity-check.sh` |
| Where does each child stand | — | `tools/status.sh` |
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
