# Validate data/*.jsonl and assemble dist/train.jsonl.
#
#     julia --project=. build.jl            # validate + execute code blocks + build
#     julia --project=. build.jl --no-exec  # skip code-block execution
#
# Exits nonzero if any example has a structural or scrubbing error; such examples are
# also left out of dist/. Code blocks that fail to run are reported, not dropped:
# some answers deliberately show code that throws.

using JSON, Random, SHA

const ROOT = @__DIR__
const DATA = get(ENV, "JT_DATA", joinpath(ROOT, "data"))
const DIST = get(ENV, "JT_DIST", joinpath(ROOT, "dist"))

# Hard errors: private hosts, people, paths, employer material.
const BANNED = [
    r"/home/"i, r"~/Documents", r"\b(galen|wintermute|neuromancer|brutus)\b"i,
    r"\b(asml|lensmodel\w*|nxt\d*|clsm)\b"i, r"\bel_oso\b"i, r"\b(jorge|vieyra)\b"i,
    r"[\w.+-]+@(?!example\.)[\w-]+(\.[\w-]+)*\.[a-z]{2,}\b"i,
]
# Warnings: names of the user's unregistered/private packages.
const PRIVATE = r"\b(Pure(BLAS|FFT|Sparse|OSQP|LSQP|QP\w*|Litho|Adsorb)|BlazingPorts|Mexicah|Mjolnir|Tonalli|LibMx|LowObservables)\b"

const SKIP_EXEC = r"^\s*#\s*partial|Pkg\.|\brun\(|@testitem|@testmodule|@testsnippet|juliac|\bexit\("m

approx_tokens(s) = cld(length(s), 4)

function check_example(ex)
    errs = String[]
    haskey(ex, "messages") || return ["no messages"]
    msgs = ex["messages"]
    toolnames = haskey(ex, "tools") ?
        Set(String(t["function"]["name"]) for t in ex["tools"]) : Set{String}()
    expect_user = true
    for (k, m) in pairs(msgs)
        role = get(m, "role", "")
        content = something(get(m, "content", ""), "")
        calls = get(m, "tool_calls", nothing)
        if role == "system"
            k == firstindex(msgs) || push!(errs, "system message not first")
        elseif role == "user"
            expect_user || push!(errs, "user at $k follows user")
            isempty(strip(content)) && push!(errs, "empty user at $k")
            expect_user = false
        elseif role == "assistant"
            expect_user && push!(errs, "assistant at $k without user")
            if isnothing(calls)
                isempty(strip(content)) && push!(errs, "empty assistant at $k")
                expect_user = true
            else
                for c in calls
                    n = c["function"]["name"]
                    n in toolnames || push!(errs, "tool_call $n not in tools")
                    c["function"]["arguments"] isa AbstractDict ||
                        push!(errs, "tool_call $n arguments not an object")
                end
            end
        elseif role == "tool"
            haskey(m, "tool_call_id") || push!(errs, "tool message without tool_call_id")
        else
            push!(errs, "unknown role '$role' at $k")
        end
    end
    last = msgs[end]
    (last["role"] == "assistant" && isnothing(get(last, "tool_calls", nothing))) ||
        push!(errs, "does not end on a final assistant message")
    text = JSON.json(ex)
    for r in BANNED
        m = match(r, text)
        isnothing(m) || push!(errs, "banned text: $(m.match)")
    end
    return errs
end

assistant_text(ex) = join(
    (
        something(get(m, "content", ""), "") for m in ex["messages"]
            if m["role"] == "assistant"
    ), "\n"
)

julia_blocks(s) = [String(m.captures[1]) for m in eachmatch(r"```julia\n(.*?)```"s, s)]

strip_partial(s) = replace(s, r"```julia\n\s*#\s*partial[^\n]*\n" => "```julia\n")

function strip_partial!(ex)
    for m in ex["messages"]
        c = get(m, "content", nothing)
        c isa AbstractString && (m["content"] = strip_partial(c))
    end
    return ex
end

# Runs blocks in a child process (exec_blocks.jl), one fresh module per block,
# restarting the child after a block exceeds `timeout` seconds.
function exec_blocks(blocks; timeout = parse(Int, get(ENV, "JT_TIMEOUT", "120")))
    results = Dict{Int, String}()
    isempty(blocks) && return results
    input = tempname() * ".json"
    write(input, JSON.json(blocks))
    start = 1
    while start <= length(blocks)
        out = Pipe()
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$ROOT $(joinpath(ROOT, "exec_blocks.jl")) $input $start`
        p = run(pipeline(cmd; stdout = out, stderr = devnull); wait = false)
        close(out.in)
        current = start
        done = Channel{Nothing}(1)
        @async begin
            for line in eachline(out)
                if startswith(line, "BEGIN ")
                    current = parse(Int, line[7:end])
                elseif startswith(line, "FAIL ")
                    i, msg = split(line[6:end], ' '; limit = 2)
                    results[parse(Int, i)] = msg
                end
            end
            put!(done, nothing)
        end
        status = timedwait(() -> isready(done), timeout * (length(blocks) - start + 1))
        if status === :timed_out || !success(p)
            kill(p)
            haskey(results, current) || (results[current] = "timeout or crash")
            start = current + 1
        else
            break
        end
    end
    rm(input; force = true)
    return results
end

# prompts/messy.jsonl maps an example's exact first user message to a rewrite in the style
# real users type (terse, typos, pasted errors). The data files keep the clean originals.
const MESSY = joinpath(ROOT, "prompts", "messy.jsonl")

function load_messy()
    isfile(MESSY) || return Dict{String, String}()
    pairs = (JSON.parse(l) for l in eachline(MESSY) if !isempty(strip(l)))
    return Dict{String, String}(String(p["original"]) => String(p["messy"]) for p in pairs)
end

function apply_messy!(ex, messy)
    for m in ex["messages"]
        m["role"] == "user" || continue
        new = get(messy, m["content"], nothing)
        isnothing(new) && return false
        m["content"] = new
        return true
    end
    return false
end

# About 10% of examples are held out for evaluation, chosen by a SHA-1 digest of the clean
# first user message. `hash` is not stable across Julia versions, so it must not pick the split.
function is_holdout(ex)
    first_user = first(m["content"] for m in ex["messages"] if m["role"] == "user")
    return iszero(first(sha1(first_user)) % 10)
end

function main(args)
    doexec = !("--no-exec" in args)
    files = sort(filter(endswith(".jsonl"), readdir(DATA; join = true)))
    keep = Any[]
    seen = Dict{String, String}()
    messy = load_messy()
    nerr = 0
    report = IOBuffer()
    for f in files
        name = basename(f)
        exs = Any[]
        for (ln, line) in enumerate(eachline(f))
            isempty(strip(line)) && continue
            ex = try
                JSON.parse(line)
            catch e
                println(report, "ERROR $name:$ln invalid JSON: ", first(sprint(showerror, e), 120))
                nerr += 1
                continue
            end
            errs = check_example(ex)
            if !isempty(errs)
                println(report, "ERROR $name:$ln ", join(errs, "; "))
                nerr += 1
                continue
            end
            key = JSON.json(ex["messages"])
            if haskey(seen, key)
                println(report, "DUP   $name:$ln duplicates ", seen[key])
                continue
            end
            seen[key] = "$name:$ln"
            m = match(PRIVATE, key)
            isnothing(m) || println(report, "WARN  $name:$ln private package name: ", m.match)
            ntok = approx_tokens(key)
            ntok > 2500 && println(report, "WARN  $name:$ln long example (~$ntok tokens)")
            push!(exs, (ln, ex))
        end
        if doexec
            blocks = String[]; owners = Int[]
            for (ln, ex) in exs, b in julia_blocks(assistant_text(ex))
                occursin(SKIP_EXEC, b) && continue
                push!(blocks, b); push!(owners, ln)
            end
            fails = exec_blocks(blocks)
            for (i, msg) in sort(collect(fails))
                println(report, "EXEC  $name:$(owners[i]) block failed: ", first(msg, 160))
            end
            println(stderr, "$name: $(length(exs)) examples, $(length(blocks)) blocks run, $(length(fails)) failed")
        else
            println(stderr, "$name: $(length(exs)) examples")
        end
        for (_, ex) in exs
            ex["_holdout"] = is_holdout(ex)
            # Harness = file-name prefix before "_agent": pi_agent_verify.jsonl belongs to pi.
            ex["_harness"] = haskey(ex, "tools") ? first(split(splitext(name)[1], "_agent")) : ""
        end
        nmessy = count(ex -> apply_messy!(ex, messy), (ex for (_, ex) in exs))
        nmessy > 0 && println(stderr, "  $name: $nmessy prompts replaced by messy rewrites")
        append!(keep, (strip_partial!(ex) for (_, ex) in exs))
    end
    mkpath(DIST)
    shuffle!(Xoshiro(20261020), keep)
    # Tool-calling examples go to one file per harness (pi, opencode): each harness has its
    # own tool set, and `datasets` unifies row schemas, so mixing them with each other or with
    # plain chat rows adds null fields to `tools`/`tool_calls`.
    foreach(f -> rm(joinpath(DIST, f)), filter(endswith(".jsonl"), readdir(DIST)))
    held = Dict{String, Int}()
    for ex in keep
        suffix = isempty(ex["_harness"]) ? "" : "_" * ex["_harness"]
        file = (ex["_holdout"] ? "eval_holdout" : "train") * suffix * ".jsonl"
        open(joinpath(DIST, file), "a") do io
            println(io, JSON.json(delete!(delete!(copy(ex), "_holdout"), "_harness")))
        end
        held[file] = get(held, file, 0) + 1
    end
    println(stderr, "split: ", join(("$f=$n" for (f, n) in sort(collect(held))), ", "))
    toks = sort([approx_tokens(JSON.json(ex["messages"])) for ex in keep])
    write(joinpath(DIST, "report.txt"), take!(report))
    println(
        stderr, "kept $(length(keep)) examples, $nerr rejected; ~tokens median ",
        isempty(toks) ? 0 : toks[cld(end, 2)], ", max ", isempty(toks) ? 0 : toks[end]
    )
    println(stderr, "report: ", joinpath(DIST, "report.txt"))
    return iszero(nerr)
end

main(ARGS) || exit(1)
