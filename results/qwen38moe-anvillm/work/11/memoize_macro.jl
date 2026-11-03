"""
@memoize macro for Julia function definitions.

Usage:
    @memoize
    function f(x::Int)::Int
        x <= 1 ? x : f(x-1) + f(x-2)
    end

    @memoize g(x::Float64) = x + 1

Caches results by argument tuple. Recursive calls hit the cache because the
memoized method (with concrete types) is more specific than the body function
(fib_body), so dispatch picks the wrapper first.

The Dict key type is Tuple{concrete_types} when all args are concretely typed —
lookups don't box. For untyped args it falls back to Tuple{Any}.

Limitations:
  1. Only supports `function f(args...) ... end` and `f(args) = expr` syntax.
  2. No support for where-clauses (`function f(x)::Int where T<:Real ... end`).
  3. No support for keyword arguments (`function f(x; kw=1) ... end`).
  4. No support for vararg args (`function f(x::Int...) ... end`).
  5. The body function name is `f_body` — collisions with existing symbols break.
  6. Does NOT work with `@memoize` inside modules unless re-exported.
  7. Only works with concrete type annotations; untyped args fall back to boxing.
  8. Does NOT handle method definitions (`Base.:+(x::Int, y::Int) = ...`).
  9. Does NOT handle `function` without name (anonymous function definitions).
10. Cache is per-function-local; no cross-module sharing.
11. Does NOT work with `macrocall` on expressions that don't have `:function` or
    `:(=)` head (e.g., `@memoize (x->x+1)` or `@memoize x::Int = x+1`).
"""

# ─── Core macro entry point (3-arg form for Julia 1.13.2 :macrocall) ─────────

macro memoize(line::LineNumberNode, mod::Module, expr::Expr)
    @assert expr.head == :function || expr.head == :(=) \
        "@memoize expects `function f(args...) ... end` or `f(args) = expr`"
    if expr.head == :function
        _memoize_from_func(expr)
    else
        _memoize_from_one_liner(expr)
    end
end

# ─── Helpers ───────────────────────────────────────────────────────────────────

"""Parse arg names and type annotations from a list of arg ASTs."""
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

"""Build the method signature (as Expr list) for a given arg list."""
function _sig(arg_names, arg_types)
    map(arg_names, arg_types) do nm, tp
        tp === :Any ? :($nm) : Expr(:(::), nm, tp)
    end
end

"""Generate the full memoized expansion for `function f(args...) ... end`."""
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

        # Memoized dispatch — concrete types if available (no boxing)
        function $(esc(name))($(sig...))
            key = $(args_expr)
            if haskey(cache, key)
                return cache[key]
            end
            result = $(body_call)
            cache[key] = result
            return result
        end

        # Original body, named `_body` so recursive `f(x)` dispatches to
        # the memoized wrapper (which is more specific than `_body`).
        function $(body_name)($(sig...))
            $(body)
        end
    end)
end

"""Generate the expansion for `f(x) = expr` (one-liner)."""
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

# ─── Test: fib(90) ────────────────────────────────────────────────────────────

@memoize
function fib(n::Int)::Int
    n <= 1 ? n : fib(n - 1) + fib(n - 2)
end

println("fib(90) = ", fib(90))
println("fib(0)  = ", fib(0))
println("fib(10) = ", fib(10))

# One-liner form
@memoize
g(x::Float64) = x + 1
println("\ng(3.5) = ", g(3.5))
println("g(3.5) again = ", g(3.5))

# Multi-arg typed
@memoize
function add(x::Int, y::Int)::Int
    x + y
end
println("\nadd(3, 4) = ", add(3, 4))
println("add(3, 4) again = ", add(3, 4))

# Untyped → Tuple{Any} (boxes)
@memoize
function h(x)
    x + 1
end
println("\nh(42) = ", h(42))

# Show generated methods
println("\n── Generated code for fib: ──")
println("fib method signatures:")
for m in methods(fib)
    println("  ", m)
end
println("\n_fib method signatures:")
for m in methods(_fib)
    println("  ", m)
end
