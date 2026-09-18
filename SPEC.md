# StarForge specification

This is the model-agnostic law for every child. BOOTSTRAP.md and SYNC.md are
the procedures that apply it. When a procedure and this file disagree, this
file wins and the procedure gets fixed.

Upstream: https://github.com/antirez/ds4 (MIT). Upstream is called *ds4* below.

## §A What a child is

A child `sf-<model>` is a **full git fork** of ds4 (complete history, `remote
upstream` pointing at ds4) specialized for **one model** on **one backend
(Metal, Apple Silicon)**. It is a normal GitHub repository with its own `main`,
PRs and tags.

Design decisions that follow from this:

- **Git is the source of truth for tracking upstream.** The merge-base with
  `upstream/main` says which upstream commits a child has. Nothing is recorded
  by hand. The orchestrator never keeps a copy of that information.
- **Every child merges all of `upstream/main`.** The question "which child does
  this upstream commit belong to?" is never answered by a human: code that a
  child has removed conflicts (or falls out as modify/delete) and is dropped
  in the resolution. Classification (`tools/sync-preview.sh`) only exists to
  estimate effort before starting.
- **Duplication between children is accepted.** Readability of one child beats
  sharing.
- **A child is smaller code, not the same code behind flags.** Removal is
  physical deletion, never `#ifdef SF_MODEL_X`.

## §B Always kept (product invariants)

- Binaries: CLI (`sf-<model>`), server (`-server`), bench (`-bench`), eval
  (`-eval`). Four.
- **Directional steering**: `--dir-steering-file`, `--dir-steering-ffn`,
  `--dir-steering-attn`, `/steer`, `dir-steering/` (tools, examples, README),
  the activation-capture code it depends on. Present in every child even if
  the model does not support it (DeepSeek V4.1 Flash): upstream's error path
  stays as is.
- **Speculative decoding** where the model has it: MTP for GLM 5.3 Flash and
  Qwen3.8. See the registry in AGENTS.md. Where the registry says "none", the
  whole speculative path is removed (`ds4_session_eval_speculative`,
  `ds4_engine_mtp_draft_tokens`, DSpark support GGUF, `--mtp*` flags, the
  `*-verify-depth` Makefile targets, `tests/*dspark*`, `tests/*mtp*`).
- **Vision** where the registry says so: `ds4_image.c/.h`,
  `third_party/iris`, the model's encoder code and `.metal` kernel, `--vision`,
  `/read image`, server image inputs. Where the registry says "no", all of it
  goes.
- **TP / RDMA / pipeline parallelism**: `ds4_tp.c/.h`, `ds4_distributed.c/.h`,
  `ds4_gpu_tp.h`, `docs/DISTRIBUTED.md`, `tests/test_tp_*`,
  `tests/test_metal_tp_*`. Kept in every child.
- **SSD streaming**: `ds4_ssd.c/.h`, hotlist for the child's model,
  `docs/SSD_STREAMING.md`.
- **Server disk KV cache**: `ds4_kvstore.c/.h`, `rax.c/.h`, `rax_malloc.h`.
  Used by the server, not only by the agent.
- **CPU reference path**: everything under `DS4_NO_GPU`, the `*_f32_ref` /
  `*_cpu` functions in `ds4.c`, the `make cpu` target. Model-independent tests
  (`test_session_state`, `test_sampling`, `test_prompt_prefix`, ...) link it
  and run without a GGUF; they are the fast check after every ablation batch.
- `ds4_prompt_prefix.c/.h` (`--prefix-file`, used by the CLI), `linenoise.*`,
  `ds4_help.*`, `ds4_tool_text.h` (server tool-call syntax), `ds4_layer_pack.*`,
  `ds4_engram.*` only where the model uses Engram (V4.1).
- `LICENSE`, `licenses/`, `EVAL_DATA.md`, `CONTRIBUTING.md` (trimmed),
  `AGENT.md` (trimmed, see §I), `gguf-tools/` parts for the child's model,
  `speed-bench/` parts for Metal and the child's model.
- Every test that compiles on Darwin and is not about a removed model, backend
  or binary.

## §C Always removed

**Agent and agent-only code**

- `ds4_agent.c`, `ds4_web.c/.h`, `tests/ds4_agent_test.c`,
  `tests/ds4_agent_terminal_test.py`, `tests/test_agent_*.py`,
  `tests/test_web_recovery.*`, `tests/test_server_vision_agent.py` (check: if
  it only tests the server, keep it), `misc/COMPACT.md`,
  `misc/ANTHROPIC_LIVE_CONTINUATION.md` and `misc/RESPONSE_API.md` if they
  document agent-only behaviour (server API docs stay).
- Makefile: target `ds4-agent`, `ds4_agent_test`, `test-frontends` agent part,
  `test-web-recovery`, every mention in `help`.
- Every doc paragraph about `ds4-agent`, `/save /list /switch /del /strip`,
  `/hints`, `~/.ds4/kvcache` (README, `QA_BEFORE_RELEASES.md`,
  `docs/TESTING.md`, `docs/SPECULATIVE_DECODING.md`, `docs/MODELS.md`,
  `docs/QWEN38_FLASH_NEXT.md`). `docs/CLIENTS.md` **stays**: it documents
  external agents (Pi, OpenCode, Codex, Claude Code) talking to the server.

**Non-Metal backends**

- `ds4_cuda.cu`, `cuda/`, `ds4_*_cuda.cuh`, `ds4_iq2_tables_cuda.inc`,
  `ds4_rocm*.{cu,h}`, `rocm/`, `ds4_rocm_memory.h`, `ds4_linux_memory.h` (verify
  the Darwin build does not include it; upstream Makefile lists it as a dep of
  `ds4.o`, so check the include and delete the include if it is guarded),
  `ds4_gpu_args.c/.h` and `ds4_gpu_mgpu.h` (multi-GPU placement; if the CLI
  parsing helpers in `ds4_gpu_args.c` are used by Metal builds, keep only
  those), `run-nvidia-tp-server.sh`, `STRIXHALO.md`, `docs/CUDA_MULTI_GPU.md`,
  `docs/DGX_SPARK.md`, `docs/STRIX_HALO.md`, `tests/*cuda*`, `tests/*rocm*`,
  `tests/test_gpu_*`, `tests/test_engine_mgpu_*`, `tests/test_linux_memory.c`,
  `speed-bench/gb10.csv`, `speed-bench/gfx1151-*`.
- Makefile: the whole non-Darwin branch (`else` of `ifeq ($(UNAME_S),Darwin)`),
  `NVCC*`, `HIPCC*`, `MMQ_*`, `ROCM_*`, `cuda*`/`strix-halo`/`rocm` targets.
  The `UNAME_S` check itself can go: a child builds on Darwin only, and fails
  loudly elsewhere.

**Other models**

- Shapes: every `DS4_SHAPE_*` except the child's (plus `QWEN4_MINI` in
  `sf-q3-8flash`, it is a test fixture). `g_ds4_shape` becomes `static const`
  = the child's shape. `ds4_select_shape_from_metadata` keeps **only the check
  that the GGUF matches the child's shape** and errors otherwise: this is a
  trust boundary, do not weaken it.
- Kernels: `metal/*.metal` of other models (`dsv41.metal`, `glm53_*.metal`,
  `qwen4*.metal`, `deepseek4_vision.metal`, `dsv4_*` when the child is not a
  DeepSeek V4, ...). Check each with `grep -l <kernel_name> ds4_metal.m`.
- Hotlists, `.inc` tables, `gguf-tools/<other>_*.py`, `tests/*<other>*`,
  `docs/<OTHER_MODEL>.md`, `MODEL_CARD.md` sections, `download_model.sh` targets.
- The `ds4_engine_is_<other>()` / `ds4_model_is_<other>()` bodies and every
  branch they guard (§F tells how).

**Simplifications that follow from "one model"**

- `download_model.sh` (715 lines, ~30 targets) → `download.sh` taking only a
  quantization / component name (`q2`, `q4k`, `vision`, ...). Model hardcoded.
  Keep resume, checksum and the `<default>.gguf` symlink update.
- Default `-m` hardcoded to the child's model file (`SF_DEFAULT_MODEL`); `-m`
  stays for override.
- `--help` texts, `Makefile help`, README: only what exists.
- Flags of other models go with their code: `--power` (V4 only), `--think-level`
  / `--think-max` (V4.1 only), `--backend cuda|rocm`, multi-GPU placement flags.

## §D Decided per child (recorded in the child's AGENTS.md)

- Which quantizations `download.sh` offers.
- Vision and speculative decoding per the registry.
- Default port, home dir, lock path per the registry.
- Which `speed-bench/*.csv|svg` baselines to keep (only the child's model on
  Metal machines).

## §E Conventions (identical in every child)

**Git**

- `git remote add upstream https://github.com/antirez/ds4.git`, `origin` = the
  child's GitHub repo.
- `git config rerere.enabled true` and `git config rerere.autoupdate true`
  at bootstrap, before the first ablation commit.
- Commit subjects, grep-able:
  - `ablate(<area>): ...` removal of code/docs (`<area>` ∈ `agent`, `cuda`,
    `rocm`, `glm`, `qwen`, `ds41`, `ds4`, `pro`, `vision`, `specdec`, `docs`, `build`).
  - `simplify(<area>): ...` single-model simplifications (§C last block).
  - `sync: upstream <sha7>` the merge commit of a sync (SYNC.md).
  - `fix(<area>): ...`, `perf(<area>): ...` child-local changes.
  - `sf: ...` child-identity changes (Makefile `BIN`, defines, AGENTS.md).
- Tag `sync-<sha7>` on `main` after every landed sync, where `<sha7>` is the
  upstream commit merged. `tools/status.sh` reads these.
- Branch names: `sync/<sha7>` for syncs, `ablate/<area>` for ablation work,
  anything for the rest. Land through PRs on GitHub.

**Source**

- **File names `ds4_*` never change.** Internal identifiers (`ds4_engine`,
  `DS4_*` macros, `DS4_*` env vars) never change either. Only the outside
  changes: binary names, default paths, help text.
- In-file cuts get a one-line marker at the exact spot:
  `/* sf-ablate(<area>): <what was here and why this child does not need it> */`
  Whole-file deletions get no marker (`git log` says it).
- Child-specific values are compile-time defines, all set in one commented
  block of the Makefile and read at exactly one place each in the source:

  | Define | Meaning | Used at |
  |---|---|---|
  | `SF_DEFAULT_MODEL` | default `-m` (e.g. `"ds4flash.gguf"`) | CLI/server/bench/eval config init |
  | `SF_DEFAULT_PORT` | server default port | `ds4_server.c` config init |
  | `SF_HOME` | `~/.sf/<model>` (history, suggested `--kv-disk-dir`) | `ds4_cli.c` history path |
  | `SF_LOCK_FILE` | `/tmp/sf-<model>.lock` | `ds4.c` instance lock default |

  `DS4_LOCK_FILE` env override stays. The `mkstemp` template
  `/tmp/ds4-session-payload.XXXXXX` is renamed to `/tmp/sf-<model>-...` (cosmetic,
  no collision, one line).
- `DS4_*` environment variables are **not renamed** (~160 `getenv` sites, all
  process-local debug toggles). Rule for users and agents: never `export` them,
  always set inline on the command (`DS4_METAL_CB_TIMES=1 ./sf-ds4flash ...`).
- Makefile: `BIN ?= sf-<model>`; every target and every `-o` uses `$(BIN)`,
  `$(BIN)-server`, etc. Object files keep upstream names.

**Docs**

- All `.md` in English.
- Rule: a paragraph, table row, command or link that mentions a model, backend
  or binary not present in the child is **deleted**, not adapted. Adapting
  creates text upstream never wrote and conflicts forever.
- Docs that survive in every child: `README.md` (rewritten head, trimmed body),
  `docs/METAL.md`, `docs/MODELS.md` (child's model only), `docs/SERVER.md`,
  `docs/CLIENTS.md`, `docs/SSD_STREAMING.md`, `docs/DISTRIBUTED.md`,
  `docs/PERFORMANCE.md` (Metal numbers only), `docs/TESTING.md`,
  `dir-steering/README.md`, `EVAL_DATA.md`, `CONTRIBUTING.md`, `AGENT.md`,
  `QA_BEFORE_RELEASES.md`. Plus `docs/SPECULATIVE_DECODING.md` and the model's
  own page (`docs/QWEN38_FLASH_NEXT.md`, ...) where applicable.
- `AGENT.md` (upstream's coding-agent notes) is **kept and trimmed**, not
  renamed: remove goals about CUDA/distributed-only/agent, update the Layout
  section. The child's `AGENTS.md` (from `templates/child-AGENTS.md`) explains
  the child and points to `AGENT.md` for quality rules.

## §F Ablation rule

> Remove everything that, by reasoning, is unreachable for this model on this
> backend. Small batches. Tests after every batch. If doubt stays high and no
> test resolves it, leave the code: dead code beats a regression.

Tools, in order of preference:

1. **The compiler.** Freeze `g_ds4_shape` to the child's shape (`static const`).
   `DS4_MODEL_FAMILY` / `DS4_MODEL_VARIANT` become constants, so
   `ds4_model_is_<other>()` folds to `false`. Build with `-Wunused-function`
   (already in `-Wall -Wextra`): the compiler lists the functions that became
   unreachable. Delete them, rebuild, repeat until the list is empty. For the
   `ds4_engine_is_<other>(e)` runtime variants, make them `return false;`
   first, then delete callers' dead branches, then delete the function.
2. **Tests without a model**: `make test` (the Darwin subset) after every
   batch. Seconds. Anything red → the batch was wrong, `git checkout .` and
   split it.
3. **Model-backed tests** the child keeps (`ds4_test`, `test_metal_*`, the
   model's kernel tests, `sf-<model>-eval`) at the end of a session.
4. **Parity oracle** (`tools/parity-check.sh`): upstream at the merge-base vs
   the child, same GGUF, same prompts, `--temp 0`, token-identical output,
   tokens/s within ±2%. Run at the end of every ablation session and every
   sync. It is the definition of "the ablation was correct".
5. **Doubt left after 1–4 and high** → leave the code, add
   `/* sf-keep: unsure if reachable for <model>, see <issue/commit> */`, mention
   it in the PR. Do not ask the test suite to prove a negative.

Things explicitly **not** ablated in a first pass: the CPU forward code in
`ds4.c`; anything the model's own kernels share with a removed model (shared
attention/MoE/norm kernels stay, only clearly-tagged kernels go).

## §G Sync process (summary; SYNC.md is the checklist)

1. Preview from the orchestrator: new upstream commits classified by path
   (only-removed / touches this model / ambiguous).
2. In the child: `git checkout -b sync/<sha7> main && git merge upstream/main`.
3. Modify/delete conflicts → `git rm` (scripted). Hunk conflicts → rerere
   first, then by hand. Every resolution that drops upstream code inside a live
   file gets an `sf-ablate` marker.
4. `make test` → model-backed tests → parity oracle → PR → `main` → tag.
5. Never `-X ours` / `-X theirs`.

If upstream renamed or split a `ds4_*` file: stop, ask. That is the one event
that can break the whole scheme and it needs a human decision (follow the
rename, or freeze the child at the previous upstream SHA).

## §H The orchestrator (this folder)

- Holds: `AGENTS.md`, this file, `BOOTSTRAP.md`, `SYNC.md`, `README.md`,
  `templates/`, `tools/`, and two gitignored dirs: `children/<name>` (plain
  clones) and `upstream/ds4` (plain full clone, read-only).
- **Plain clones, not submodules.** Each child's position is already recorded
  in the child (`sync-*` tags, merge-base). Submodules would duplicate that
  and add daily pointer-update commits, detached HEADs and a 4-step removal
  dance. Switching to submodules later is additive if a coordinated snapshot
  is ever needed.
- Never modifies a child directly. Analyses, proposes, and the work happens in
  `children/<name>` through that repo's PR flow.
- `tools/` are bash + git + coreutils. No new language, no dependencies. Each
  script prints what it does and is idempotent where possible.

## §I Licence and attribution

- ds4 is MIT. `LICENSE` is copied unchanged (it carries the GGML copyright
  notice too). `licenses/` unchanged.
- Child `README.md` starts with:

  > `sf-<model>` is a specialized fork of [ds4 / DwarfStar](https://github.com/antirez/ds4)
  > by Salvatore Sanfilippo and contributors, reduced to **<Model name>** on
  > **Apple Metal**. Upstream base commit: `<sha7>` (updated at every sync).
  > Everything that works here works because of ds4, llama.cpp and GGML; see
  > `LICENSE` and the acknowledgements below.

  followed by upstream's "Acknowledgements to llama.cpp and GGML" section,
  kept verbatim.

## §J Co-existence on one machine

Several children (and upstream ds4) can be installed and run on the same Mac:

- Port, home dir, lock path: per child (registry). Two children start
  together; RAM is the user's problem, not the lock's.
- `gguf/` and the default `.gguf` symlink are relative to each repo.
- Server `--kv-disk-dir`: opt-in, no default. Recommend `~/.sf/<model>/kv` in
  the child's docs. `ds4_kvstore` already rejects entries from a different
  model/quant.
- `DS4_*` env vars: inline only, never exported (§E).
