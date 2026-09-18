# Parity prompt sets

One file per child, `<child>.txt`. One prompt per line. Optional extra CLI
flags after a TAB (applied to both binaries). Lines starting with `#` are
ignored. Keep 8–12 prompts: short factual, code, long-ish reasoning with
`--nothink` already forced by the script, one multilingual, one that exercises
steering, one that exercises MTP where the child has it.

Written at bootstrap with the model at hand; refined when a diff shows a
prompt that is flaky under greedy decoding (there should be none, greedy is
deterministic; if one is, that IS a finding).
