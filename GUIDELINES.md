# Dataset guidelines

Chat-format SFT data for a Julia-expert model. Output files live in `data/`, one JSONL file per
topic. Every line is one example:

    {"messages":[{"role":"user","content":"..."},{"role":"assistant","content":"..."}]}

Roles alternate user/assistant and end on assistant. No system message. Multi-turn (2–3 exchanges)
is allowed for workflow scenarios.

## What an example teaches

Pull **general, transferable Julia lessons** out of the source notes. The notes are written about
specific projects; the training data must not be. Rewrite each lesson so it holds for any Julia
user on any machine.

Mix these shapes (rough targets per topic file):

- ~35% **direct questions** ("How do I run only one test item?", "Why is my struct slow?").
- ~30% **fix this code / review this code**: the user pastes flawed Julia, the assistant names the
  defect and gives the corrected version.
- ~25% **workflow scenarios**: the user describes a situation in an agentic coding session ("I
  edited src/solver.jl and the test still shows the old result"); the assistant says what to do,
  in order, naming the exact tool or function.
- ~10% **misconception corrections**: the user states a wrong belief; the assistant corrects it.

Phrase each underlying lesson 2–3 different ways at most (different question, different code),
never more. Twenty distinct lessons beat sixty paraphrases.

## Correctness: don't guess, check

- **Every Julia code block must be run** in a Julia MCP session before you write it into the
  file (create a session with `julia_create_session`, which defaults to the current release,
  1.13.2; evaluate with `julia_eval_code`). If a fact may differ on the LTS (1.10), check it in a
  second session created with `julia_cmd` pointing at `julia +lts`. Outputs shown in an answer (`# → 3`,
  printed results, inferred types, error messages) must be the actual output you got.
- Facts about package APIs (TestItemRunner, Pkg, Revise, BenchmarkTools, …) must be checked
  against the installed source or docstrings (`pkgdir`, `@doc`, `methods`) when cheap. If a
  claim comes only from the source notes and you could not check it, keep it only if the notes
  say it was measured or verified; otherwise drop it.
- Never write timing numbers from one machine as facts. Say "several times slower", or show
  how to measure it. Ratios that are robust (e.g. "allocates, the other does not") are fine.
- Version-specific facts must name the version ("since Julia 1.12 …").
- Do not run Pkg operations that modify the global environment. Use a temporary environment
  (`Pkg.activate(temp=true)`) when you need to demonstrate Pkg.
- **Never background a long command and wait for it.** Run in the foreground.
- Kill your Julia session when you are done.

## Scrubbing — hard requirements

Must not appear anywhere in the output:

- host names (galen, wintermute, neuromancer, brutus, …), user names, real names, e-mail
  addresses, home-directory paths (`/home/...`, `~/Documents/...`);
- anything about ASML, LensModelTools, LensModels, NXT, CLSM, or other employer-internal
  code — skip those notes entirely;
- private/unregistered project names as if they were public packages. Refer to "a sparse
  solver package" rather than "PureSparse". Public registered packages (Revise, TestItems,
  TestItemRunner, BenchmarkTools, Chairmarks, JET, AllocCheck, Cthulhu, DispatchDoctor,
  OffsetArrays, Preferences, Reexport, …) are fine by name. If unsure whether a package is
  registered, check `Pkg.Registry` or leave it out.

## Answer style

- Concise and technical. American spelling. No marketing tone, no filler openers.
- Lead with the answer, then the code, then at most a few lines of reasoning.
- Most assistant answers under ~350 words; none over ~700.
- Code is idiomatic, generic (`AbstractVector`, `eachindex`, `zero(T)`), type-stable, with no
  `@inbounds` unless the example is specifically about it.
- At most 4 self-checks per answer (`@assert` or `@test` lines, counted over all code blocks)
  unless the user asks for a test suite. Pick the checks that cover the edge cases the prompt
  names, otherwise the most informative ones. When the user asks for tests without asking for a
  full suite, give one compact `@testset` of at most 4 tests.
- Follow a requested reply format exactly. "A single code block" means only the block;
  "only the function" or "no tests" means just the definition; "just the corrected line" means
  one line; "one sentence" means one sentence; "no explanation" means no prose. Add nothing the
  format rules out.
- State program output only when running the code in the answer produced it. Every `# → value`
  annotation, and every sentence saying what code prints or returns, must be checked against
  the real result (including how Julia displays it, e.g. `0x02` for a `UInt8`), never guessed.
  Do not repeat in prose what an annotation or check already shows. For values that vary with
  the data, version, or machine (random data, allocation counts, timings), compare instead
  (`... > 0  # → true`) or say that the number varies.
- End the answer once the question is answered: no recap of the code, no offers of more help,
  no sections nobody asked for.
- Comments in code state what is true now; no history, no "previously".
- Never suggest Python, PyCall/PythonCall, or shelling out to Python.
- Code meant to be kept (a parser, data structure, numeric routine, tool) is delivered as a
  package: `Pkg.generate`, a module in `src/` that exports only the public API, dependencies
  via `Pkg.add` + `Pkg.compat`, and `test/runtests.jl` with TestItemRunner
  (`@run_package_tests`) plus `@testitem`s. Scripts are for one-off work (a single data
  conversion, a REPL question, an exploratory snippet), and the answer says why no package.

## The agent tool surface (for workflow examples)

The model will run inside a coding agent with the JuliaMCP server. Its tools are:
`julia_create_session`, `julia_eval_code`, `julia_kill_session`, `julia_list_sessions`,
`julia_profile_code`, `julia_get_session_variables`, `julia_set_workspace_folders`,
`julia_get_diagnostics`, `julia_format_file`, `julia_list_testitems`, `julia_run_testitems`,
`julia_get_testrun_results`, `julia_get_testitem_detail`, `julia_rerun_failed`,
`julia_cancel_testrun`, `julia_list_test_processes`, `julia_terminate_test_process`,
`julia_get_coverage_results`. Workflow answers name these tools exactly, in prose or as a short
numbered list of calls. Don't invent parameters; use only ones that appear in the source notes.

## Output file

Write one JSON object per line (no pretty-printing, no trailing commas). The easy way: in your
session, `using Pkg; Pkg.activate(temp=true); Pkg.add("JSON")`, build the examples as Julia
`Dict`s, and write `JSON.json(ex)` per line. Then parse every line back to confirm structure.
A central validator also checks every file afterwards (structure, scrubbing, duplicates, and it
executes the ```julia blocks), so fence only real Julia as ```julia; use ```text for tool-call
sequences, shell commands, and expected output.

A ```julia block must be either self-contained and runnable on a fresh session with only stdlib
plus BenchmarkTools/Chairmarks loaded (and any package it `using`s itself), or be clearly
partial — then put `# partial` as its first line so the executor skips it. Blocks that modify
Pkg environments, define `@testitem`s, or call juliac must be marked `# partial`. The marker
line is stripped when the final training file is built, so it never reaches the model.
