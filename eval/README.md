# Julia-expert evaluation suite

97 executable tasks in `tasks/*.toml` across 13 areas (dispatch_types, performance, trim, testing,
pkg_workflow, memory, metaprogramming, linalg_sparse, strings_io_dates, debugging, parallel,
expert_functional, lessons). Each task has a `prompt`, a `check` (Julia code using `Test`, run after the
model's code block is evaluated in a fresh module), `deps`, a `reference` solution, and a
`negative` (a flawed answer that must fail the check).

The `lessons` area holds small single-answer tasks that each probe one defect seen in model-written
Julia (byte vs. character indexing, raw byte output, cancellation, tombstones, genericity, and so on).

Checks can use the helpers in `helpers.jl`: `alloc_of(f, args...)`, `rtype(f, argtypes)`,
`is_stable(f, argtypes)`, `dynamic_calls(f, argtypes)` (run-time dispatch in the optimized IR,
descending into statically called methods), the string `SOLUTION_SOURCE` (the model's raw code),
and `TESTITEMS` (what `@testitem` blocks recorded; they are not run).

## Run

    julia --project=eval eval/run_eval.jl --endpoint http://localhost:8080 --model my-model --out a.jsonl

Options: `--api-key-env VAR` (name of an environment variable holding the key; the key is never
printed or stored), `--tasks GLOB` (e.g. `'trim*'`), `--system FILE`, `--max-tokens N` (4096),
`--timeout S` per task subprocess (180), `--request-timeout S` (600), `--threads N` for the task
subprocess (2; the `parallel` tasks need at least 2), `--jobs N` (1, sequential), `--no-thinking` (sends
`chat_template_kwargs: {"enable_thinking": false}`, for thinking models).
Temperature is 0.

- llama-server: `llama-server -m model.gguf --port 8080`, then `--endpoint http://localhost:8080`.
- Ollama: `--endpoint http://localhost:11434 --model qwen2.5-coder:7b` (its OpenAI-compatible
  `/v1/chat/completions` is used; the path is appended unless the URL already ends with it).

## Validate the suite

    julia --project=eval eval/run_eval.jl --reference    # every reference must pass
    julia --project=eval eval/run_eval.jl --negative     # every negative must fail

Both exit non-zero when the expectation is violated. No endpoint is contacted.

## Failure reasons

- `no code block`: the reply has no fenced `julia` block.
- `eval error`: the block raised while being evaluated (syntax error, undefined name, missing package).
- `test failure`: the code ran but a `@test` in the check failed or threw (including checks
  that measure allocations, inferred types, or dispatch).
- `timeout`: the subprocess exceeded `--timeout` (infinite loop, deadlock).
- `request error`: the HTTP call failed.

The JSONL record holds `id, area, mode, passed, reason, detail` (test output, truncated),
`latency_s`, and `reply`.

## Compare two models

    julia --project=eval eval/compare.jl a.jsonl b.jsonl

Prints per-area pass rates side by side, then the tasks fixed or regressed between the first and
last file.

## Notes

- The timing check in `performance_03` and the thread checks in `parallel_*` depend on a
  machine with at least two free cores.
- `dynamic_calls` flags run-time dispatch in Julia code; code that prints through the global
  `stdout` counts as dynamic, so no check applies it to I/O code.
- Julia 1.11 or newer is assumed (`@main`, `@test_throws "message"`).
