#!/usr/bin/env julia
# Evaluation runner. See README.md.
#   julia --project=eval eval/run_eval.jl --endpoint URL --model NAME [options]
#   julia --project=eval eval/run_eval.jl --reference    # validate the suite: all must pass
#   julia --project=eval eval/run_eval.jl --negative     # validate the suite: all must fail
using Downloads, JSON, TOML

const EVAL_DIR = @__DIR__
const OPTS = Dict{String, Any}(
    "endpoint" => "", "model" => "", "api-key-env" => "", "tasks" => "*",
    "out" => "results.jsonl", "system" => "", "max-tokens" => "4096",
    "timeout" => "180", "request-timeout" => "600", "jobs" => "1", "threads" => "2",
    "reference" => false, "negative" => false, "no-thinking" => false,
)

function parse_args(args)
    i = 1
    while i <= length(args)
        a = args[i]
        startswith(a, "--") || error("unexpected argument $a")
        key = a[3:end]
        haskey(OPTS, key) || error("unknown option $a")
        if OPTS[key] isa Bool
            OPTS[key] = true
            i += 1
        else
            i + 1 <= length(args) || error("option $a needs a value")
            OPTS[key] = args[i + 1]
            i += 2
        end
    end
    return
end

glob_regex(g) = Regex("^" * replace(replace(g, "." => "\\."), "*" => ".*", "?" => ".") * "\$")

function load_tasks(pattern)
    rx = glob_regex(pattern)
    files = sort(filter(f -> endswith(f, ".toml"), readdir(joinpath(EVAL_DIR, "tasks"); join = true)))
    tasks = Dict{String, Any}[]
    for f in files
        rx_ok = occursin(rx, splitext(basename(f))[1]) || occursin(rx, basename(f))
        rx_ok && push!(tasks, TOML.parsefile(f))
    end
    return tasks
end

# A non-streaming reply sends no bytes until generation ends, which can take minutes; the default
# downloader aborts any transfer idle for 20 s, so this one disables that limit (`--request-timeout`
# still bounds the request).
const DOWNLOADER = Ref{Downloads.Downloader}()

function chat(messages)
    isassigned(DOWNLOADER) || (
        DOWNLOADER[] = Downloads.Downloader();
        DOWNLOADER[].easy_hook = (easy, info) -> Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_TIME, 0)
    )
    req = Dict{String, Any}(
        "model" => OPTS["model"], "messages" => messages, "temperature" => 0,
        "max_tokens" => parse(Int, OPTS["max-tokens"]), "stream" => false,
    )
    # Honored by servers that render the model's chat template (llama-server, AnviLLM).
    OPTS["no-thinking"] && (req["chat_template_kwargs"] = Dict("enable_thinking" => false))
    body = JSON.json(req)
    headers = ["Content-Type" => "application/json"]
    env = OPTS["api-key-env"]
    if !isempty(env)
        haskey(ENV, env) || error("environment variable $env is not set")
        push!(headers, "Authorization" => "Bearer " * ENV[env])
    end
    url = rstrip(OPTS["endpoint"], '/')
    endswith(url, "/chat/completions") || (url *= "/v1/chat/completions")
    out = IOBuffer()
    resp = Downloads.request(
        url; method = "POST", headers, input = IOBuffer(body), output = out,
        timeout = parse(Float64, OPTS["request-timeout"]), downloader = DOWNLOADER[]
    )
    resp.status == 200 || error("HTTP $(resp.status): " * first(String(take!(out)), 300))
    j = JSON.parse(String(take!(out)))
    return string(j["choices"][1]["message"]["content"])
end

function extract_code(reply)
    m = match(r"```julia[ \t]*\r?\n(.*?)```"s, reply)
    return isnothing(m) ? nothing : String(m.captures[1])
end

# Returns (reason, detail). reason is "pass", "eval error", "test failure" or "timeout".
function run_task(task, code)
    return mktempdir() do dir
        write(joinpath(dir, "code.jl"), code)
        write(joinpath(dir, "check.jl"), task["check"])
        logfile = joinpath(dir, "log.txt")
        cmd = `$(Base.julia_cmd()) --project=$EVAL_DIR --startup-file=no --threads=$(OPTS["threads"]) $(joinpath(EVAL_DIR, "harness.jl")) $(joinpath(dir, "code.jl")) $(joinpath(dir, "check.jl")) $(get(task, "deps", String[]))`
        proc = open(logfile, "w") do io
            run(pipeline(ignorestatus(cmd); stdout = io, stderr = io); wait = false)
        end
        limit = parse(Float64, OPTS["timeout"])
        t0 = time()
        while process_running(proc) && time() - t0 < limit
            sleep(0.05)
        end
        timed_out = process_running(proc)
        if timed_out
            kill(proc, Base.SIGKILL)
            wait(proc)
        end
        log = read(logfile, String)
        detail = length(log) > 3000 ? first(log, 1500) * "\n...\n" * last(log, 1500) : log
        timed_out && return ("timeout", detail)
        exitcode = proc.exitcode
        iszero(exitcode) && return ("pass", "")
        exitcode == 10 && return ("eval error", detail)
        return ("test failure", detail)
    end
end

function main()
    parse_args(ARGS)
    reference, negative = OPTS["reference"], OPTS["negative"]
    mode = reference ? "reference" : negative ? "negative" : "model"
    if mode == "model"
        (isempty(OPTS["endpoint"]) || isempty(OPTS["model"])) && error("--endpoint and --model are required")
    end
    tasks = load_tasks(OPTS["tasks"])
    isempty(tasks) && error("no tasks match $(OPTS["tasks"])")
    system = isempty(OPTS["system"]) ? nothing : read(OPTS["system"], String)
    results = Vector{Dict{String, Any}}(undef, length(tasks))
    sem = Base.Semaphore(parse(Int, OPTS["jobs"]))
    @sync for (i, task) in enumerate(tasks)
        @async begin
            Base.acquire(sem)
            try
                t0 = time()
                reply, code, reason, detail = "", nothing, "", ""
                if mode == "reference"
                    code = task["reference"]
                elseif mode == "negative"
                    code = task["negative"]
                else
                    try
                        msgs = Dict{String, String}[]
                        isnothing(system) || push!(msgs, Dict("role" => "system", "content" => system))
                        push!(msgs, Dict("role" => "user", "content" => task["prompt"]))
                        reply = chat(msgs)
                        code = extract_code(reply)
                    catch e
                        reason, detail = "request error", sprint(showerror, e)
                    end
                end
                if isempty(reason)
                    if isnothing(code)
                        reason, detail = "no code block", ""
                    else
                        reason, detail = run_task(task, code)
                    end
                end
                results[i] = Dict{String, Any}(
                    "id" => task["id"], "area" => task["area"], "mode" => mode,
                    "passed" => reason == "pass", "reason" => reason, "detail" => detail,
                    "latency_s" => round(time() - t0; digits = 2), "reply" => mode == "model" ? reply : code
                )
                println(rpad(task["id"], 22), reason, "  (", results[i]["latency_s"], " s)")
                # Redirected to a file, stdout is block-buffered; flush so the log shows progress.
                flush(stdout)
            finally
                Base.release(sem)
            end
        end
    end
    open(OPTS["out"], "w") do io
        for r in results
            println(io, JSON.json(r))
        end
    end
    areas = sort(unique(r["area"] for r in results))
    println("\n", rpad("area", 20), lpad("pass", 6), lpad("total", 7), lpad("rate", 8))
    for a in areas
        rs = filter(r -> r["area"] == a, results)
        p = count(r -> r["passed"], rs)
        println(rpad(a, 20), lpad(p, 6), lpad(length(rs), 7), lpad(string(round(100p / length(rs); digits = 1), "%"), 8))
    end
    p = count(r -> r["passed"], results)
    println(rpad("ALL", 20), lpad(p, 6), lpad(length(results), 7), lpad(string(round(100p / length(results); digits = 1), "%"), 8))
    println("results written to ", OPTS["out"])
    bad = reference ? filter(r -> !r["passed"], results) : negative ? filter(r -> r["passed"], results) : []
    return if !isempty(bad)
        println("\nSUITE VALIDATION FAILED for: ", join((r["id"] for r in bad), ", "))
        exit(1)
    end
end

main()
