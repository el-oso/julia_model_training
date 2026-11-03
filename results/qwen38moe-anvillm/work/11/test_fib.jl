# ── Inline the @memoize macro definition ─────────────────────────────────────

macro memoize(line::LineNumberNode, mod::Module, expr::Expr)
    @assert expr.head == :function || expr.head == :(=) \
        "@memoize expects `function f(args...) ... end` or `f(args) = expr`"

    if expr.head == :function
        _memoize_from_func(expr)
    else
        _memoize_from_one_liner(expr)
    end
end

function _extract_args_and_types(args)
    names  = Symbol[]
    types  = Expr[]   # :Any means "no annotation"
    for a in args
        if a.head == :(::)
            push!(names, a.args[1])
            push!(types, a.args[2])
        else
            push!(names, a)
            push!(types, :Any)
        end
    end
    return names, types
end

function _sig(arg_names, arg_types)
    map(arg_names, arg_types) do nm, tp
        tp === :Any ? :($nm) : Expr(:(::), nm, tp)
    end
end

function _memoize_from_func(expr)
    head = expr.args[2]       # :((f(args)))
    name = head.args[1]       # Symbol of function name
    args = head.args[2:end]   # args as ASTs
    body = expr.args[3]       # the body Expr

    arg_names, arg_types = _extract_args_and_types(args)

    all_concrete = all(t -> t !== :Any, arg_types)
    key_type = all_concrete ? :(Tuple{$(arg_types...)}) : :(Tuple{Any})

    sig = _sig(arg_names, arg_types)
    args_expr = Expr(:tuple, arg_names...)   # (n1, n2, ...)
    body_call = Expr(:call, Symbol(string(name) * "_body"), arg_names...)
    body_name = Symbol(string(name) * "_body")

    esc(quote
        local cache = Dict{$key_type, Any}()

        function $(esc(name))($(sig...))
            key = $(args_expr)
            if haskey(cache, key)
                return cache[key]
            end
            result = $(body_call)
            cache[key] = result
            return result
        end

        function $(body_name)($(sig...))
            $(body)
        end
    end)
end

function _memoize_from_one_liner(expr)
    call_node = expr.args[1]   # :((f(args)))
    name      = call_node.args[1]
    args      = call_node.args[2:end]
    body      = expr.args[2]

    arg_names, arg_types = _extract_args_and_types(args)

    all_concrete = all(t -> t !== :Any, arg_types)
    key_type = all_concrete ? :(Tuple{$(arg_types...)}) : :(Tuple{Any})

    sig = _sig(arg_names, arg_types)
    args_expr = Expr(:tuple, arg_names...)
    body_call = Expr(:call, Symbol(string(name) * "_body"), arg_names...)
    body_name = Symbol(string(name) * "_body")

    esc(quote
        local cache = Dict{$key_type, Any}()

        function $(esc(name))($(sig...))
            key = $(args_expr)
            if haskey(cache, key)
                return cache[key]
            end
            result = $(body_call)
            cache[key] = result
            return result
        end

        function $(body_name)($(sig...))
            $(body)
        end
    end)
end

# ── Test 1: typed function form ──────────────────────────────────────────────
@memoize
function fib(n::Int)::Int
    n <= 1 ? n : fib(n - 1) + fib(n - 2)
end

println("fib(90) = $(fib(90))")
println("fib(0)  = $(fib(0))")
println("fib(10) = $(fib(10))")

# ── Test 2: one-liner form ───────────────────────────────────────────────────
@memoize
g(x::Float64) = x + 1

println("\ng(3.5) = $(g(3.5))")
println("g(3.5) again = $(g(3.5))")  # should hit cache

# ── Test 3: untyped args → fallback to Tuple{Any} (boxes) ───────────────────
@memoize
function h(x)
    x + 1
end

println("\nh(42) = $(h(42))")

# ── Test 4: multi-arg ────────────────────────────────────────────────────────
@memoize
function add(x::Int, y::Int)::Int
    x + y
end

println("\nadd(3, 4) = $(add(3, 4))")
println("add(3, 4) again = $(add(3, 4))")

# ── Show the generated code for fib ──────────────────────────────────────────
println("\n── Generated code for fib: ──")
# We show the expansion by redefining fib and expanding
println("fib method signatures:")
for m in methods(fib)
    println("  ", m)
end
println("\n_fib method signatures:")
for m in methods(_fib)
    println("  ", m)
end
