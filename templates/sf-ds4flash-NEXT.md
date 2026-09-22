# Next steps — sf-ds4flash

Temporary handoff for the next agent. This is **not** product documentation,
not a sync trace, and not a status authority. It is intentionally untracked.
Use it to finish the initial bootstrap, then delete it before requesting a
commit.

## Current state

- StarForge is at `/Users/dchini/github/chida82/StarForge`.
- The orchestrator remote is `https://github.com/Chida82/StarForge`.
- Upstream ds4 is a full, read-only clone at `upstream/ds4`. This file records
  no upstream SHA on purpose: read it with `git -C upstream/ds4 rev-parse
  origin/main` or `tools/status.sh`.
- `sf-q3-8flash` is already bootstrapped and landed on its `main`; read its
  `AGENTS.md` before starting here. In particular its "Names that lie" table
  lists identifier families whose model name does not describe what they serve
  (`glm_graph_*` is the shared Metal graph host, `glm_mtp` the built-in MTP
  switch): the same traps apply to this child. This file is copied by
  `tools/new-child.sh sf-ds4flash Chida82`.
- The planned child is `sf-ds4flash`: DeepSeek V4 Flash, Metal only,
  `DS4_SHAPE_FLASH`, port 8001, home `~/.sf/ds4flash`, lock
  `/tmp/sf-ds4flash.lock`, no vision, **DSpark only** and no legacy one-stage
  MTP.
- The standard main model to use is:
  `antirez/deepseek-v4-gguf` /
  `DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf`
  (about 86.7 GB). It was requested in another terminal with `hf download`.
  Check cache/download completion before relying on it.
- The discarded DeepSeek V4 Flash Vision Experimental cache repo was removed.
  Do not restore it: Vision Experimental is not managed by any child.
- DSpark needs a separate matching support GGUF:
  `DeepSeek-V4-Flash-DSpark-support-0731.gguf` (about 6 GB). Download it via
  `hf download antirez/deepseek-v4-gguf <exact-file>` when the child reaches
  model-backed DSpark checks. Do not download or support
  `DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf`.

## Rules that matter here

1. Read `AGENTS.md`, then `BOOTSTRAP.md` and `SPEC.md` before changing code.
2. Do not rename any `ds4_*` source file or `ds4_` / `DS4_` identifier.
3. Set rerere first; `tools/new-child.sh` already does it.
4. Keep steering, TP/RDMA/pipeline, CPU reference/tests, CLI/server/bench/eval.
5. Remove agent, CUDA, ROCm, all other models, and Vision Experimental.
6. Keep DSpark, its loader/tests/flags and shared speculative helpers even when
   their names contain `mtp`. Remove only the legacy MTP path and its surface.
7. Model files stay in the shared Hugging Face cache. `download.sh` calls
   `hf download` and creates only symlinks in `gguf/` plus the root default
   model symlink. Never copy a GGUF into this repository.
8. In a file that remains, mark every non-obvious cut or dropped upstream hunk
   at the exact site:
   `/* sf-ablate(<area>): <what was removed; why this child does not need it> */`
   Do not create marker-only files for deletions.
9. Never commit or push unless the user explicitly requests that action.

## Work to do

1. Ensure the GitHub repository `Chida82/sf-ds4flash` exists.
2. From StarForge root, run:
   ```sh
   tools/new-child.sh sf-ds4flash Chida82
   cd children/sf-ds4flash
   git checkout -b bootstrap/$(git rev-parse --short=7 HEAD)
   ```
   This prepares files but does not commit, tag, or push.
3. Follow every step in `../../BOOTSTRAP.md`, in order:
   - Makefile identity: `BIN`, four `SF_*` defines, Darwin/Metal only, four
     binaries, agent target removed.
   - Per-child model/default paths and lock/history paths.
   - Remove agent and non-Metal backends.
   - Freeze `g_ds4_shape` to Flash and ablate compiler-discovered dead code in
     small tested batches.
   - Remove Vision Experimental and all other models.
   - Keep DSpark; remove legacy MTP exactly as SPEC.md §B and BOOTSTRAP.md §7
     require.
   - Replace `download_model.sh` with the small cache-backed `download.sh`.
   - Trim all docs to this child, preserving licence/attribution.
4. After each non-trivial batch run `make test`. At the end, run model-backed
   tests, DSpark checks, and `tools/parity-check.sh sf-ds4flash` from the
   StarForge root.
5. Replace the absolute placeholders in `tests/parity_prompts.txt` with a real
   steering vector and the real cached DSpark GGUF path before parity.
6. Delete this `NEXT.md` only once the handoff is no longer needed. Do not add
   it to a product commit.

## Lessons from the sf-q3-8flash bootstrap

- `make cpu` links the CPU-reference build over the same four binary names. A
  model-backed run straight after it fails with "requires Metal"; rebuild with
  `make` first.
- The compiler is the ablation oracle, but `-Wunused-function` never reports a
  cluster whose members reference each other: find the entry point, remove it,
  and the cluster then falls out. Mechanical tools also break on blocks whose
  braces interleave with `#if`/`#else`/`#endif`; skip those and do them by hand.
- A preprocessor-output diff cannot see the removal of an `#error` guard or of
  an `#else` fallback whose condition is true in the tested configuration.
  Check those with a negative compile.
- Prove unreachability before deleting: constant-false predicate, `nm` with no
  referrer, or a runtime probe. Record what you establish in the child's
  `AGENTS.md`, not in a separate ledger.
