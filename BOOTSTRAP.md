# BOOTSTRAP — create a child from upstream

Executable checklist. Each step has a **Check** that tells you it is done.
Stop and ask when a Check fails twice or when AGENTS.md "When to stop and ask"
applies. Read SPEC.md §B–§F once before starting; this file does not repeat
the reasons.

Inputs: `<child>` from the registry (AGENTS.md), the GitHub org, a Mac with
enough RAM and the model's GGUF (needed from step 7 on).

Work in small commits with the SPEC §E subjects. Push to a branch
`bootstrap/<sha7>` and land with one PR at the end, or land each step as its
own PR: both are fine. Never work on `main` directly after step 1.

---

## 1. Clone, remotes, rerere, template

```sh
tools/clone-all.sh                       # upstream/ds4 must exist
tools/new-child.sh <child> <org>         # clone, remotes, rerere, tag sync-<base>, AGENTS.md from template
cd children/<child>
git checkout -b bootstrap/$(git rev-parse --short=7 HEAD)
```

**Check**: `git remote -v` shows `upstream` = antirez/ds4 and `origin` = your
repo; `git config rerere.enabled` = `true`; `git tag` shows `sync-<sha7>`;
`AGENTS.md` has no `<PLACEHOLDER>` left except `Chida82` if you did not pass it.

## 2. Makefile: identity and Darwin only

- Add at the top, one commented block:
  ```make
  # sf: child identity (SPEC.md §E). Everything else below is upstream's.
  BIN ?= <child>
  SF_DEFS := -DSF_DEFAULT_MODEL='"<model>.gguf"' -DSF_DEFAULT_PORT=<port> \
             -DSF_HOME='"<home>"' -DSF_LOCK_FILE='"<lock>"'
  CFLAGS += $(SF_DEFS)
  OBJCFLAGS += $(SF_DEFS)
  ```
- Replace targets and `-o` names: `ds4`→`$(BIN)`, `ds4-server`→`$(BIN)-server`,
  `ds4-bench`→`$(BIN)-bench`, `ds4-eval`→`$(BIN)-eval`. Object names unchanged.
- Delete the non-Darwin branch (`else` of `ifeq ($(UNAME_S),Darwin)` …
  `endif`), all `NVCC*`, `HIPCC*`, `MMQ_*`, `ROCM_*`, `CUDA_*` variables and
  targets, `cuda*`, `strix-halo`, `rocm`, `test-rocm`, `test-*-cuda`,
  `test-*-rocm`, `cuda-regression`. Keep `UNAME_S` only if something still
  needs it; otherwise add `ifneq ($(shell uname -s),Darwin) $(error <child> builds on macOS only) endif`.
- Delete agent targets: `ds4-agent`, `ds4_agent.o`, `ds4_agent_cpu.o`,
  `ds4_agent_test*`, `ds4_web.o`, `test-frontends` agent lines,
  `test-web-recovery`. Fix `all`, `cpu`, `test`, `clean`, `help`.
- Delete speculative targets if the registry says "none": `dspark-*`,
  `mtp-verify-depth`, `DS4_TEST_MTP`, `DS4_DSPARK_*`.

Commit: `sf: Makefile identity (BIN, SF_* defines), Darwin only, no agent`.

**Check**: `make` builds four binaries named `<child>*`; `make help` mentions
only them; `grep -c 'ds4-agent\|NVCC\|HIPCC' Makefile` = 0.

## 3. Source: the four defines and the paths

Exactly one place each (SPEC §E table):

| What | File / hint | Change |
|---|---|---|
| default model | `ds4_cli.c`, `ds4_server.c`, `ds4_bench.c`, `ds4_eval.c`: `.model_path = "ds4flash.gguf"` | `SF_DEFAULT_MODEL` |
| port | `ds4_server.c`: `.port = 8000` | `SF_DEFAULT_PORT` |
| history | `ds4_cli.c`: `"%s/.ds4_history"` | `SF_HOME "/history"` (create dir if missing) |
| lock | `ds4.c` `ds4_acquire_instance_lock`: `"/tmp/ds4.lock"` | `SF_LOCK_FILE` |
| payload tmp | `ds4.c`: `"/tmp/ds4-session-payload.XXXXXX"` | `"/tmp/<child>-session-payload.XXXXXX"` |

Add `#ifndef SF_DEFAULT_MODEL #error "build through the Makefile" #endif` near
the first use, so a stray `cc ds4_cli.c` fails clearly. Mark each spot `/* sf: */`.

Commit: `sf: default model, port, home, lock per child`.

**Check**: `strings <child> | grep -c '/tmp/ds4.lock\|\.ds4_history'` = 0;
`./<child>-server --help` shows `<port>`; two children (or child + upstream ds4)
can start at the same time.

## 4. Remove agent

```sh
git rm ds4_agent.c ds4_web.c ds4_web.h tests/ds4_agent_test.c tests/ds4_agent_terminal_test.py \
       tests/test_agent_*.py tests/test_web_recovery.c tests/test_web_recovery.py misc/COMPACT.md
```
Check `tests/test_server_vision_agent.py`, `misc/ANTHROPIC_LIVE_CONTINUATION.md`,
`misc/RESPONSE_API.md`: keep if they are about the server. Remove agent
sections from `README.md`, `QA_BEFORE_RELEASES.md`, `docs/TESTING.md`,
`docs/SPECULATIVE_DECODING.md`, `docs/MODELS.md`, the model page, `AGENT.md`
(goal "Make long local agent sessions practical…" and the layout line).
`ds4_kvstore.*`, `rax.*`, `ds4_prompt_prefix.*`, `linenoise.*`,
`ds4_tool_text.h` **stay**.

Commit: `ablate(agent): remove ds4-agent, web fetch, agent tests and docs`.

**Check**: `make && make test` green; `grep -rli 'ds4-agent' --include=*.md . | wc -l` = 0.

## 5. Remove non-Metal backends

```sh
git rm ds4_cuda.cu ds4_*_cuda.cuh ds4_iq2_tables_cuda.inc ds4_rocm*.cu ds4_rocm*.h \
       ds4_linux_memory.h run-nvidia-tp-server.sh STRIXHALO.md \
       docs/CUDA_MULTI_GPU.md docs/DGX_SPARK.md docs/STRIX_HALO.md \
       tests/*cuda* tests/*rocm* tests/test_gpu_*.c tests/test_gpu_args_cli.sh \
       tests/test_engine_mgpu_*.c tests/test_linux_memory.c tests/cuda_long_context_smoke.c \
       speed-bench/gb10.csv speed-bench/gfx1151-prefill-results.md
git rm -r cuda rocm
```
`ds4_gpu_args.c/.h`, `ds4_gpu_mgpu.h`: read them. If only multi-GPU placement
→ `git rm` and drop the includes and the `--gpu*` flags in CLI/server/bench.
If they also carry Metal-relevant argument parsing, keep those functions only.
Check `ds4.c` / `ds4_metal.m` for `#include "ds4_linux_memory.h"`; it should be
guarded by `#ifdef __linux__`; delete the include and the guard.
Remove CUDA/ROCm/Spark/Strix paragraphs from every `.md` (README platform
table, MODELS, PERFORMANCE, DISTRIBUTED, TESTING, SSD_STREAMING, AGENT.md goals).

Commits: `ablate(cuda): …`, `ablate(rocm): …`, `ablate(docs): non-Metal platforms`.

**Check**: `make && make test` green; `grep -rl 'DS4_ROCM_BUILD\|cudaMalloc\|hipcc' --include=*.c --include=*.m --include=*.h . | wc -l` = 0.

## 6. Freeze the shape (compiler-guided ablation, SPEC §F.1)

In `ds4.c`:
1. Delete every `DS4_SHAPE_*` except the child's (and `QWEN4_MINI` in
   `sf-q3-8flash`).
2. `static ds4_shape g_ds4_shape = {…}` → `static const ds4_shape g_ds4_shape = DS4_SHAPE_<child>;`
   (or keep the initializer inline). Every `g_ds4_shape = …` assignment goes.
3. `ds4_select_shape_from_metadata`: keep only "does this GGUF match
   `g_ds4_shape`?" → else `fprintf(stderr, "<child>: unsupported model shape …"); exit(1)`.
   Same for the per-family selectors (`g_ds4_shape = DS4_SHAPE_GLM53;` sites etc.).
4. `ds4_engine_is_<other>()`, `ds4_model_is_<other>()`: body → `return false;`
   for now.
5. `make 2>&1 | grep -c unused-function` — iterate: delete listed functions,
   rebuild, until 0. Then delete the `if (ds4_*_is_<other>(…)) { … }` branches
   that are now constant-false (the compiler already dropped them; you are
   removing text), then the `is_<other>` functions themselves, then their
   declarations in `ds4.h`.
6. Same loop in `ds4_metal.m` (it has ~1000 `qwen4` and ~250 `glm` mentions in
   upstream: expect several batches), `ds4_server.c` (tool-call syntax of
   other models, `--think-level` for non-V4.1), `ds4_cli.c`, `ds4_help.c`.
7. Kernels: for each `metal/<other>*.metal`, `grep -l <kernel names> ds4_metal.m`;
   if no live reference → `git rm`. `dsv4_*`/`dsv41`/`glm53_*`/`qwen4*`/
   `deepseek4_vision` are the tagged ones; shared kernels (`moe`, `dense`,
   `flash_attn`, `norm`, …) stay.
8. Tables and tools: `ds4_streaming_hotlist_glm52.inc`, `ds4_qwen4_unicode.inc`
   (only if not the child's tokenizer), `ds4_qwen4_vision.h`,
   `ds4_deepseek41_gpu.h`, `ds4_engram.*` (V4.1 only), `gguf-tools/<other>_*.py`,
   `tests/*<other>*`, `docs/<OTHER>.md`, `download_model.sh` targets,
   `MODEL_CARD.md` sections, `speed-bench/*` of other models.

**Batch discipline**: one area per commit (`ablate(glm): …`, `ablate(qwen): …`,
`ablate(ds41): …`, `ablate(pro): …`), `make test` green before each commit.
A red `make test` → `git checkout .` and split the batch. In-file cuts get
`/* sf-ablate(<area>): … */`; doubts get `/* sf-keep: … */`.

**Check** per area: `grep -ci '<other>' ds4.c ds4_metal.m` is near zero and
every remaining hit is either shared code or an `sf-keep`. Global: `make test`
green; binary size dropped; `wc -l ds4.c ds4_metal.m` dropped substantially.

## 7. Features per registry: vision, speculative decoding

- Vision = **no**: `git rm ds4_image.c ds4_image.h`, `third_party/iris`,
  `metal/<model>_vision.metal`, `tests/*vision*`, `tests/vision-fixtures`,
  `gguf-tools/*vision*`; remove `--vision`, `/read` image branch, server image
  inputs (`ds4_server.c`), `docs/MODELS.md` vision sections. Commit `ablate(vision): …`.
- Speculative = **none**: remove `ds4_session_eval_speculative`,
  `ds4_engine_mtp_draft_tokens`, `--mtp*`, DSpark support loading and flags,
  `tests/*dspark*`, `tests/*mtp*`, `docs/SPECULATIVE_DECODING.md`, README
  paragraphs. Commit `ablate(specdec): …`.
- Steering: **touch nothing**. Verify it still builds and `--dir-steering-file`
  is in `--help`.

**Check**: `make test` green; `./<child> --help | grep -c 'mtp\|vision'` matches
the registry (0 where absent); `./<child> --help | grep -c dir-steering` ≥ 1.

## 8. Single-model simplifications

- `download_model.sh` → `download.sh`: only this model's targets, first
  positional = quantization/component, model name hardcoded, keep resume /
  checksum / symlink update. `git mv` then edit (keeps history).
- Help texts and README commands use `<child>` names.
- `tests/parity_prompts.txt` present (copied by `new-child.sh`); replace the
  steering `PLACEHOLDER.bin` line with a real vector from `dir-steering/`.

Commit: `simplify(download): one model, quantization as the only argument`,
`simplify(docs): …`.

**Check**: `./download.sh` with no args lists the offered quantizations;
`./download.sh <q>` resumes an interrupted download.

## 9. Docs pass (SPEC §E "Docs")

For each surviving `.md`: delete paragraphs about removed models, backends,
binaries. Rewrite the README head with the attribution notice (SPEC §I),
keep upstream's acknowledgements verbatim. Update `AGENT.md` Layout and Goals.
`AGENTS.md` (template) is already there; fill any `Chida82`.

**Check**: `grep -rliE 'cuda|rocm|spark|strix|ds4-agent|<other model names>' --include=*.md . ` returns
only `LICENSE`-adjacent or acknowledgement text you intentionally kept.

## 10. Model-backed verification

With the GGUF in place (`./download.sh <q>`):

```sh
make test                        # model-less
make test-metal-…                # every kept Metal/kernel test target (see make help)
./ds4_test  (or the renamed target)
./<child>-eval -m <model>.gguf --suite core
./<child>-bench -m <model>.gguf
cd ../.. && tools/parity-check.sh <child>
```

**Check**: all green; parity OK with speed within ±2%; steering prompt and
(where present) MTP prompt included in the parity run.

## 11. Land

PR(s) into `main`, merge, then `tools/sync-finish.sh <child>` (it will find
`sync-<base>` already present and do nothing more), push `main` and tags.
Fill the `Repo` column in AGENTS.md registry if it still says `Chida82`.

**Check**: `tools/status.sh` shows the child with base = last sync tag,
`BEHIND` = number of upstream commits since (likely > 0 by now → SYNC.md).

---

## Expected outcome (orders of magnitude, from upstream at `8db1d1d`)

Upstream: `ds4.c` 85k lines, `ds4_metal.m` 50k, 109 files in `tests/`, 27
`.metal` kernels, 5 binaries, 715-line download script. A child should land
well below half of `ds4.c`/`ds4_metal.m`, with only its own kernels plus the
shared ones, 4 binaries, and every remaining doc about exactly one model.
If a step's Check passes but the numbers barely move, the ablation in step 6
stopped too early: go back to the `unused-function` loop.
