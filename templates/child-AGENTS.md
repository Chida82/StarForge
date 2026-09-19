# <CHILD> — agent notes

`<CHILD>` is a specialized fork of [ds4 / DwarfStar](https://github.com/antirez/ds4)
reduced to **one model on Apple Metal**. It is one *child* of the
[StarForge](https://github.com/Chida82/StarForge) family. This file explains
what this repo is and how to work in it. For code-quality rules read
`AGENT.md` (upstream's notes, trimmed): they apply unchanged.

## Identity

| | |
|---|---|
| Model | see `README.md` first line |
| Shape (`ds4.c`) | `<SHAPE>` — `g_ds4_shape` is `static const`; a GGUF with another shape is refused |
| Backend | Metal only. No CUDA, no ROCm. CPU path kept as reference/debug and for model-less tests |
| Binaries | `<CHILD>`, `<CHILD>-server`, `<CHILD>-bench`, `<CHILD>-eval`. No agent binary |
| Server default port | `<PORT>` |
| Home dir | `<HOME>` (CLI history; suggested `--kv-disk-dir <HOME>/kv`) |
| Instance lock | `<LOCK>` (override: `DS4_LOCK_FILE`) |
| Vision | <VISION> |
| Speculative decoding | <SPECDEC> |
| Steering | yes (`--dir-steering-file`, `/steer`, `dir-steering/`) |
| TP / RDMA / pipeline | yes |
| Upstream base | `<BASE_SHA>` at bootstrap; current: `git describe --tags --match 'sync-*' --abbrev=0` |

Other children of the family may be installed on the same machine: paths and
ports above are chosen so nothing collides with them or with upstream ds4.

## What is NOT here (do not re-add)

- `ds4-agent` and agent-only code (`ds4_agent.c`, `ds4_web.c`, its tests/docs).
  Use `<CHILD>-server` with an external agent (see `docs/CLIENTS.md`).
- CUDA / ROCm / multi-GPU placement, Linux memory helpers, DGX/Strix docs.
- Every other model: shapes, kernels, tokenizer tables, tests, docs, download
  targets. Where a cut sits inside a live file there is a marker:
  `/* sf-ablate(<area>): ... */`. Where we were unsure and kept code:
  `/* sf-keep: ... */`.
- Features the registry marks as absent for this model (see Identity).

## Rules that keep upstream merges alive

1. **Never rename `ds4_*` files or `ds4_`/`DS4_` identifiers.** Only the
   outside is renamed: binaries (`BIN` in the Makefile), default paths, help.
2. **`git config rerere.enabled true`** must be on (it is; check with
   `git config rerere.enabled`). Ablated regions conflict at every upstream
   sync and rerere replays the resolution.
3. **Delete, don't `#ifdef`.** This repo is smaller code, not the same code
   behind flags.
4. **Docs follow code**: a paragraph about something not in this repo is
   deleted, not adapted. Docs are in English.
5. **Never `git merge -X ours/theirs`.**
6. Commit subjects: `ablate(<area>):`, `simplify(<area>):`, `sync: upstream <sha7>`,
   `fix(<area>):`, `perf(<area>):`, `sf:`. Tags `sync-<sha7>` on `main` after
   every landed sync.

## Child-specific values

All in one block of the `Makefile`, each read at exactly one place:

| Define | Value |
|---|---|
| `SF_DEFAULT_MODEL` | default for `-m` |
| `SF_DEFAULT_PORT` | `<PORT>` |
| `SF_HOME` | `<HOME>` |
| `SF_LOCK_FILE` | `<LOCK>` |

`DS4_*` environment variables are upstream's and are **not renamed**. Set them
inline (`DS4_METAL_CB_TIMES=1 ./<CHILD> ...`), never `export`.

## Build, test, verify

```sh
make                 # the four binaries
make test            # model-less tests: seconds, run after every change
make help            # remaining targets (model-backed tests need a GGUF in gguf/)
./download.sh        # lists the quantizations this child offers
```

Model-backed checks before a PR: the kernel tests of this model, `ds4_test`,
`./<CHILD>-eval`, and the **parity oracle** run from the StarForge
orchestrator (`tools/parity-check.sh <CHILD>`): upstream at our merge-base vs
this repo, same GGUF, same prompts (`tests/parity_prompts.txt`), greedy,
token-identical output, speed within ±2%.

## Removing code (ablation)

> Remove what is unreachable for this model on Metal, by reasoning. Small
> batches, `make test` after each. If a doubt is high and no test resolves it,
> leave the code with an `sf-keep` marker.

Order of tools: (1) the compiler — with the shape frozen, `-Wunused-function`
lists dead functions; (2) `make test`; (3) model-backed tests; (4) parity
oracle. Do not ablate in a first pass: the CPU forward code in `ds4.c`;
kernels shared with removed models (only clearly-tagged kernels go).

## Syncing with upstream

Done from the orchestrator (`SYNC.md` there), summarized:

```sh
git fetch upstream
git checkout -b sync/<sha7> main && git merge upstream/main
# modify/delete where we deleted → keep deleted (git rm)
# content conflicts → rerere first, then by hand; dropping upstream code inside a live file → sf-ablate marker
make test  →  model-backed tests  →  parity oracle  →  PR  →  main  →  tag sync-<sha7>
```

If upstream renamed or split a `ds4_*` file: stop and ask a human.

## When to stop and ask

- A conflict in `ds4.c` / `ds4_metal.m` on code not clearly tagged for a removed model.
- `make test` green but parity oracle red.
- You are about to remove steering, TP/RDMA, the CPU path, or anything in the Identity table.
