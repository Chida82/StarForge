# Next steps — sf-ds4-1flash

Temporary handoff for the next agent. This is **not** product documentation, not
a sync trace, and not a status authority. Delete it before requesting a commit.

## What this child is

DeepSeek V4.1 Flash, Metal only. `DS4_SHAPE_FLASH41`, port 8002, home
`~/.sf/ds4-1flash`, lock `/tmp/sf-ds4-1flash.lock`, **vision yes**, **speculative
decoding none**, Engram **kept** (it is V4.1's own feature). Models are already in
the shared Hugging Face cache under `models--antirez--deepseek-v4.1-flash-gguf`:
`DeepSeek-V4.1-Flash-Q2.gguf` and `DeepSeek-V4.1-Flash-Vision.gguf`. Nothing to
download.

Read `AGENTS.md`, then `BOOTSTRAP.md` and `SPEC.md`. Never commit or push without
an explicit user request.

## Where the bootstrap stands

Steps 1–4 are done (Makefile identity and Darwin-only; the four `SF_*` defines;
the agent removal). `make test` is green and is the check after every batch.
Steps 5–11 remain. Nothing has been committed.

## Findings that cost real time to establish

These came out of a seven-agent read-only survey plus a completeness critic. They
are not in any checklist, and several contradict what the sibling child learned.

**`glm_graph_*` is dead here, unlike in `sf-q3-8flash`.** The sibling's
`AGENTS.md` lists `glm_graph_*` as "the shared Metal graph host", and the
orchestrator's rule 15 repeats it. In *this* tree that is false:
`ds4_session_create` early-returns for `DS4_MODEL_FAMILY_DEEPSEEK41` into
`ds41_graph_alloc` (`ds4.c:72825-72868`), and the `glm_graph` session is opened
only under `if (DS4_MODEL_FAMILY == DS4_MODEL_FAMILY_GLM_DSA)` (`ds4.c:72948`).
Inheriting the sibling's rule would preserve about 45 dead kernels. The one
crossover is `ds4_gpu_glm_indexer_score_one_tensor`.

**But `glm_graph_env_value`, `glm_graph_host_memory_bytes` and
`qwen4_prefill_chunk_tokens` are shared helpers wearing a foreign name**
(`ds4.c:474`, `:44956`, `:39635`), with call sites in live V4.1 paths. A
prefix sweep breaks memory admission. Names still do not decide ownership;
reachability does.

**`ds4_gpu_mgpu.h` must survive the CUDA/ROCm step.** It looks like a multi-GPU
header, but `ds4.c:86` includes it unconditionally and it is the only reachable
definer of `DS4_MAX_GPUS`, `struct ds4_gpu_tensor` and `ds4_gpu_config` for both
the Metal and the CPU build — it sizes roughly 190 live graph arrays. Deleting it
breaks `make` *and* `make cpu`. `ds4_gpu_args.c/.h` is the opposite: the name
says CUDA, `nm` says two pure-C string functions. It is removable because the
`--gpu-vram`/`--gpu-devices` flags go, not because it is CUDA code — and it has a
fifth caller the checklist does not name,
`gguf-tools/quality-testing/score_official.c`.

**The trust boundary is `config_validate_model` (`ds4.c:7150-7171`), not
`ds4_select_shape_from_metadata`.** The latter never selects FLASH41 and is
deleted. `config_validate_model` is a fall-through, not a whitelist: delete the
removed-model branches and every GGUF is accepted unvalidated. It must become a
positive `arch == "deepseek41"` check.

**`DS4_VARIANT_FLASH41 = 4` is a persisted and wire constant**, not a label. It is
byte 7 of the on-disk KV cache header (`ds4_kvstore.c:407`) and the distributed
handshake model id. Renumbering it while trimming the enum would make this child
accept an upstream V4-Flash cache as its own. Keep the literal 4. The same holds
for the `DS4_TP_FRAME_*` numbers: leave the numeric holes.

**Eight conditions fuse FLASH41 with a removed family**, so "delete the block that
mentions GLM" silently deletes this child's own behaviour: `ds4.c:1359`, `:5343`,
`:5359`, `:7657`, `:43548`, `:64239`, `:70630`, `:72564`. Read each body.
`ds4.c:70630-70638` is the sharpest: the warm-weights suppression must STAY
(Engram's 189 GiB must not be faulted in) while the `--vision requires GLM-5.3,
Qwen3.8...` refusal four lines below must GO, because this child has vision.

**Metal is judged by symbol, never by filename.** `metal/dsv4_misc.metal` holds 45
glm-named kernels, one of which — `kernel_glm_indexer_score_one_direct` — is
called by the V4.1 decoder under `#ifdef __APPLE__` (`ds4.c:40684`);
`metal/deepseek4_vision.metal` holds this child's own kernels; and
`metal/glm53_bf16.metal` + `metal/glm53_vision.metal` are required by V4.1's
vision encoder. All 26 `.metal` files are concatenated into one runtime library
from a hard-coded table at `ds4_metal.m:4762-4789`: delete a file without its row
and startup fails with "Metal source not found", which no build step catches.
`ds4_gpu_init` also prewarms GLM pipelines unconditionally and then null-checks
them (`ds4_metal.m:8951-9149`), so kernels, prewarm and check must go in one
commit.

**Speculative decoding is mostly the removed model's, not the removed feature's.**
Nearly the whole DSpark engine lives on `ds4_gpu_graph`, which V4.1 never
allocates, so if the model ablation runs first, step 7 shrinks enormously. Decide
the order before touching `ds4.c`. Built-in MTP is already inert because
`DS4_N_NEXTN_PREDICT` is 0 for this shape. Unlike in the sibling, `spec_frontier_*`
can go here — all five of its callers die — but verify each one yourself.

**Tests that pass while being wrong.** `tests/test_sampling.c:279-355` keeps
passing after all speculative decoding is removed (its hooks sit on generic
sampling helpers), and it is inside `make test`. `tests/test_gpu_args_cli.sh`
guards its agent block with `[ -x ./ds4-agent ]`, so it silently skips instead of
failing. Green is not evidence.

**Ordering hazards against the gating `make test`.**
`tests/test_deepseek4_vision_image` is built and run by `make test` and calls
`ds4_image_preprocess_deepseek4`; trim the test in the same change that touches
the preprocessor. Same for `tests/test_gpu_args` and
`tests/test_engine_mgpu_placement` when `ds4_gpu_args` goes.

**Directories git will not show you.** `misc/` and `dir-steering/out/` are
gitignored but their files are tracked; a clean `git status` there means nothing.
And never sweep `gguf-tools/imatrix/dataset/` or
`gguf-tools/quality-testing/data/`: they quote this repo's own source verbatim,
so a tree-wide rename hits 64 false positives.

## Open decisions

- **Parity and steering.** V4.1 refuses to start with `--dir-steering-file`
  (`ds4.c:70605-70619`), so a steering prompt would make both binaries exit
  without output and the oracle would read it as a FAIL. This is the only child
  where the steering check cannot be a generation prompt; it has to be expressed
  as "both binaries refuse identically". `tools/parity/sf-ds4-1flash.txt` ships
  8 prompts and no steering line.
- **MXFP4** gates four things at once (`tests/test_mxfp4_dot.c`,
  `tests/test_mxfp4_metal.c`, `metal/generate_mxfp4_half_lut.py`, and the
  `mxfp4-dot-test` step inside `make test`). No V4.1 target is MXFP4, but every
  MXFP4 predicate in `ds4.c` is shape-agnostic. Settle it from the V4.1
  tensor-load path before deleting anything.
- **`dir-steering/out/verbosity.f32`** declares `shape: [43, 4096]`; FLASH41 is
  40 layers × 5120. The checked-in steering vector is another model's.
- **README head.** SPEC §I's template wants `Upstream base commit: <sha7>` while
  SPEC §A and the child template say the base is never written down. Resolve
  before rewriting the README.
- **No V4.1 speed data exists** anywhere in the repo. Do not relabel the V4 Flash
  numbers in `speed-bench/`; regenerate or leave the section empty.
