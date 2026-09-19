# Parity prompt sets

One template per child, `<child>.txt`, copied to
`tests/parity_prompts.txt` by `tools/new-child.sh`; the oracle prefers the
child's editable copy. One prompt per line. Optional extra CLI flags after a
TAB (applied to both binaries). Lines starting with `#` are ignored. Keep
8–12 prompts: short factual, code, long-ish reasoning with `--nothink` already
forced by the script, one multilingual, one that exercises
steering, and one that exercises the child's speculative mechanism: DSpark
with its separate 0731 support GGUF for `sf-ds4flash`, built-in MTP for
GLM/Qwen, none for V4.1. Replace path placeholders with real absolute paths at
bootstrap.

Written at bootstrap with the model at hand; refined when a diff shows a
prompt that is flaky under greedy decoding (there should be none, greedy is
deterministic; if one is, that IS a finding).
