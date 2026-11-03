# general_julia.jsonl

6 chat examples (`{"messages":[user, assistant]}`, no system message) intended as a
general-Julia mix-in against catastrophic forgetting. Far below the ~2000 target:
the source pools contain almost no usable material (see counts).

## Sources (read-only, in /home/el_oso/Documents/claude/julia-expert-gemma/data)

- `curated_pairs.jsonl` (23): hand-written Q&A. Source of all 6 survivors.
- `julia_instruct.jsonl` (5036): templated questions ("What does `X` do in Julia's `M` module?",
  "How do I use", "Show me an example of", "Explain '...' (from README)") whose answers are raw
  docstrings / README fragments. Also contains the 23 curated pairs (deduplicated; counted under curated).
- `rosetta_pairs_clean.jsonl` (294), `rosetta_pairs_v2.jsonl` (279): all are "Translate this MATLAB code"
  prompts; removed by the MATLAB rule (v2 is almost entirely a duplicate of clean).

## Filters, applied in order (counts: dropped at each stage)

| stage | curated | julia_instruct | rosetta_clean | rosetta_v2 |
|---|---|---|---|---|
| total | 23 | 5036 | 294 | 279 |
| 1 docstring dump (`jldoctest`, `@ref`, `!!!`, `julia>`, `# Examples`) | 0 | 4197 | 1 | 1 |
| 1 raw docs with no explanatory first sentence | 0 | 552 | 0 | 0 |
| 1 short (<15 words, no code) | 0 | 258 | 0 | 0 |
| 1 near-duplicate prompt or answer | 0 | 19 | 1 | 278 |
| 2 python/numpy/pip/MATLAB/private path or name/e-mail | 4 | 8 | 292 | 0 |
| 2 prompt already in data/*.jsonl | 0 | 0 | 0 | 0 |
| 3 julia block errors (fresh module, 30 s timeout) | 8 | 0 | - | - |
| 3 deprecated API / `1:length` / `== nothing` / unjustified `@inbounds` / global loop "fast" | 1 | 0 | - | - |
| 3 unsafe-to-run construct (`Pkg.`, `run(`, ...) | 1 | 0 | - | - |
| after stage 3 | 9 (1 kept with one block skipped: non-installed package) | 2 | 0 | 0 |
| manual drops after reading all 11 survivors | 3 | 2 | 0 | 0 |
| final | 6 | 0 | 0 | 0 |

Spot-read of all 11 stage-3 survivors (fewer than the 40 requested exist) removed 5 more:
closures example (claims `[() -> i for i in 1:3]` yields 3,3,3; verified false, gives 1,2,3),
Symbol/String example (calls String mutable; it is immutable), Holy-trait example (cites a
nonexistent "AbstractArrays" package, muddled premise), and two julia_instruct items that are a bare
docstring (Logging) and a two-sentence stub (Printf). Final: 6, all from curated_pairs.

Known harness limits: blocks run in isolation, so examples whose later blocks use names defined in
earlier blocks, or macros from InteractiveUtils (`@code_warntype`), were dropped as errors.

## Mixing ratio (starting point, not a measured fact)

With 6 examples this set cannot serve as a forgetting regularizer; do not mix it in as is.
If a larger cleaned set is built later, a common starting point is roughly 10-20% general data
by example count against the main dataset; tune against the eval set (watch general-Julia
regressions versus main-task gains).
