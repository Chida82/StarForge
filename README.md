# StarForge

One inference engine per model, Metal only, forked from
[antirez/ds4](https://github.com/antirez/ds4) (DwarfStar).

ds4 runs several large open models on several backends from one codebase. It
is excellent and it is also a lot to hold in your head. StarForge produces
**children**: full forks of ds4 reduced to **one model on Apple Metal**, each
a normal GitHub repo you can build, read and modify without the other models
and backends in the way. Children keep merging upstream through plain `git
merge`, so fixes and speedups from ds4 keep flowing in.

| Child | Model | Binary | Server port |
|---|---|---|---|
| `sf-ds4flash`    | DeepSeek V4 Flash   | `sf-ds4flash`    | 8001 |
| `sf-ds4-1flash`  | DeepSeek V4.1 Flash | `sf-ds4-1flash`  | 8002 |
| `sf-glm5-3flash` | GLM 5.3 Flash       | `sf-glm5-3flash` | 8003 |
| `sf-q3-8flash`   | Qwen3.8 Flash Next  | `sf-q3-8flash`   | 8004 |

Each child is a separate repository. **This** repository is the orchestrator:
rules, procedures, tools, and a read-only mirror of upstream. No inference
code lives here.

## If you just want to run a model

Go to the child's repo. Its README tells you `make`, `./download.sh <quant>`,
`./sf-<model>`. You do not need this repo.

## If you maintain the children

```sh
git clone https://github.com/<ORG>/StarForge && cd StarForge
tools/clone-all.sh          # upstream/ds4 (full) + children/* (those that exist on GitHub)
tools/status.sh             # where each child stands vs upstream/main
```

| I want to… | Read | Run |
|---|---|---|
| understand the rules | `AGENTS.md` (short), then `SPEC.md` (the law) | |
| create a child | `BOOTSTRAP.md` | `tools/new-child.sh <child> <org>` then the checklist |
| see what upstream changed for a child | `SYNC.md` §1 | `tools/sync-preview.sh <child>` |
| pull upstream into a child | `SYNC.md` | `tools/sync-start.sh <child>` → resolve → `tools/parity-check.sh <child>` → PR → `tools/sync-finish.sh <child>` |
| prove a child still matches upstream | `SPEC.md` §F.4 | `tools/parity-check.sh <child> [model.gguf]` |
| work with a coding agent | open `children/<child>` (it has its own `AGENTS.md`) or this folder | |

### Tools

All bash + git + coreutils, in `tools/`:

| Script | Does |
|---|---|
| `clone-all.sh` | clone/fetch `upstream/ds4` and every child in the registry; sets `upstream` remote and rerere |
| `status.sh` | per child: upstream merge-base, last `sync-*` tag, commits behind, dirty tree |
| `new-child.sh <child> [org]` | fresh child clone from upstream with remotes, rerere, base tag, `AGENTS.md` from template. Step 1 of BOOTSTRAP only; no ablation |
| `sync-preview.sh <child>` | classify pending upstream commits: only-removed / docs-only / touches-live / HOT |
| `sync-start.sh <child>` | branch `sync/<sha7>`, merge `upstream/main`, list conflicts by type |
| `rm-deleted-conflicts.sh <child>` | resolve modify/delete conflicts by keeping the child's deletions |
| `parity-check.sh <child> [gguf]` | build upstream at the child's merge-base and the child; same prompts, greedy; token-identical + speed ±2% |
| `sync-finish.sh <child>` | after the PR is merged: tag `main` as `sync-<sha7>`, push |
| `parity/<child>.txt` | prompt sets for the oracle (TAB → extra flags, e.g. steering, `--mtp`) |
| `lib.sh` | shared helpers and the **registry** (keep in sync with `AGENTS.md`) |

### Layout

```
AGENTS.md  SPEC.md  BOOTSTRAP.md  SYNC.md  README.md
templates/child-AGENTS.md        copied into a child at bootstrap
tools/                           scripts + parity prompt sets
children/<name>/                 plain clones (gitignored)
upstream/ds4/                    plain full clone of ds4 (gitignored, read-only)
```

Children and upstream are **plain clones, not submodules**: each child already
records its own upstream position (tags, merge-base). See `SPEC.md` §H.

## Design in five lines

1. A child is a **full git fork**; `git merge upstream/main` is how it stays current.
2. `ds4_*` file names and identifiers **never change**; only binary names, paths and help do.
3. Removal is **deletion**, not `#ifdef`. Cuts inside live files carry `/* sf-ablate(...) */`.
4. `git rerere` replays conflict resolutions, so ablated regions stop hurting after the first sync.
5. The **parity oracle** (same GGUF, same prompts, greedy, token-identical, speed ±2%) is the definition of correct.

Always kept in every child: steering, TP/RDMA, CPU reference path, server,
CLI, bench, eval. Never in a child: `ds4-agent`, CUDA, ROCm, other models.

## Status

Orchestrator ready. No child bootstrapped yet. First: `sf-ds4flash`
(`BOOTSTRAP.md`).

## Licence

Tools and documents in this repository: MIT. Children inherit ds4's MIT
licence and keep its `LICENSE` file, including the GGML notice, unchanged.
Everything works because of ds4, llama.cpp and GGML.
