# Prototype: single recursive function `pexpr` (1 frame per paren level).
# Precedence inlined; '^' chain done iteratively (right fold).

const NUM, PLUS, MINUS, STAR, SLASH, CARET, LP, RP, EOF = 1:9

struct Tok
    code::UInt8
    val::Float64
end

# p: (toks, i) -> (value, i)
function pexpr(t::Vector{Tok}, i::Int)
    n = length(t)
    # parse first term
    i, v = pterm(t, i)
    while i <= n
        c = t[i].code
        if c == PLUS || c == MINUS
            i += 1
            r, i2 = pterm(t, i)
            v = (c == PLUS) ? (v + r) : (v - r)
            i = i2
        else
            break
        end
    end
    return v, i
end

function pterm(t::Vector{Tok}, i::Int)
    n = length(t)
    i, v = pfactor(t, i)
    while i <= n
        c = t[i].code
        if c == STAR || c == SLASH
            i += 1
            r, i2 = pfactor(t, i)
            v = (c == STAR) ? (v * r) : (v / r)
            i = i2
        else
            break
        end
    end
    return v, i
end

function pfactor(t::Vector{Tok}, i::Int)
    n = length(t)
    negs = 0
    while i <= n && t[i].code == MINUS
        i += 1
        negs += 1
    end
    v, i = ppower(t, i)
    return (negs & 1 == 0) ? v : -v, i
end

function ppower(t::Vector{Tok}, i::Int)
    n = length(t)
    # base atom
    b, i = patom(t, i)
    if i > n || t[i].code != CARET
        return b, i
    end
    # iterative right-associative chain: collect bases and signs
    bases = Float64[b]
    signs = Int8[1]
    while i <= n && t[i].code == CARET
        i += 1
        s = Int8(1)
        if i <= n && t[i].code == MINUS
            i += 1
            s = Int8(-1)
        end
        a, i2 = patom(t, i)
        i = i2
        push!(bases, a)
        push!(signs, s)
    end
    acc = bases[end]
    for j in (length(bases)-1):-1:2
        acc = bases[j] ^ (signs[j] * acc)
    end
    return bases[1] ^ (signs[1] * acc), i
end

function patom(t::Vector{Tok}, i::Int)
    n = length(t)
    c = t[i].code
    if c == NUM
        return t[i].val, i + 1
    elseif c == LP
        v, j = pexpr(t, i + 1)   # <-- the only recursion (1 frame/level)
        @assert t[j].code == RP
        return v, j + 1
    end
    error("bad atom")
end

# ---- test depth ----
function make_parens(k::Int)
    t = Vector{Tok}(undef, 2k + 1)
    for j in 1:k
        t[j] = Tok(LP, 0.0)
    end
    t[k+1] = Tok(NUM, 1.0)
    for j in 1:k
        t[k+1+j] = Tok(RP, 0.0)
    end
    t[end] = Tok(EOF, 0.0)
    return t
end

for k in [1_000, 5_000, 10_000, 20_000, 30_000, 40_000, 50_000]
    t = make_parens(k)
    try
        v, j = pexpr(t, 1)
        println("k=$k: OK ($v)")
    catch e
        if e isa StackOverflowError
            println("k=$k: STACK OVERFLOW")
        else
            println("k=$k: ERR $e")
        end
    end
end
