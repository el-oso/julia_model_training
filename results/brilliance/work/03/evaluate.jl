# evaluate.jl
#
# A hand-written arithmetic expression evaluator.
#
#   evaluate(s::AbstractString)::Float64
#
# Grammar (precedence low → high):
#
#   expr   := term (('+' | '-') term)*
#   term   := factor (('*' | '/') factor)*
#   factor := '-'* power              (unary minus)
#   power  := atom ('^' factor)*      (right-associative)
#   atom   := NUMBER | '(' expr ')'
#
# `^` binds tighter than unary minus, so `-2^2 == -4`, and it is
# right-associative, so `2^3^2 == 2^(3^2) == 512`.
#
# The tokenizer and the recursive-descent parser are hand-written (no
# Meta.parse / eval).  The parser is organized so that a nested paren group
# adds exactly one call frame: `parse_expr` is the only recursive function,
# and the `term` level (the `* /` loop) as well as the right-associative `^`
# chain are written iteratively (the `^` chain is collected into a vector and
# folded from the right).  A parenthesized atom re-enters `parse_expr`, the
# single recursion point.  This keeps even a 10^5-character expression made
# of tens of thousands of nested parentheses within the call stack, while
# staying fast.

# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------

"""
    ParseError(msg, pos)

Thrown by `evaluate` for malformed input. `msg` names the problem (it also
mentions the position); `pos` is the 1-based character position in the input
string where the problem was detected.
"""
struct ParseError <: Exception
    msg::String
    pos::Int
end

Base.showerror(io::IO, e::ParseError) = print(io, "ParseError: ", e.msg)
Base.show(io::IO, e::ParseError) =
    print(io, "ParseError(", e.msg, ", ", e.pos, ')')

# ---------------------------------------------------------------------------
# Tokenizer
# ---------------------------------------------------------------------------

# Token kinds (small integers: cheap to compare, compact in the token vector).
const TK_NUM = 0x01
const TK_PLUS = 0x02
const TK_MINUS = 0x03
const TK_STAR = 0x04
const TK_SLASH = 0x05
const TK_CARET = 0x06
const TK_LPAREN = 0x07
const TK_RPAREN = 0x08
const TK_EOF = 0x09

"""
    Token(kind, val, pos)

A scanned token. `kind` is one of the `TK_*` constants; `val` is the numeric
value for `TK_NUM` tokens (0.0 otherwise); `pos` is the 1-based character
position of the token's first character.
"""
struct Token
    kind::UInt8
    val::Float64
    pos::Int
end

"""
    tokenize(s)

Hand-written scanner. Skips spaces/tabs/newlines, reads integers and decimals
(converted to `Float64` while scanning), and the tokens `+ - * / ^ ( )`.
The result always ends with an EOF token whose position is `length(s) + 1`.
Throws a `ParseError` naming the offending character and its position.
"""
function tokenize(s::AbstractString)
    toks = Token[]
    n = ncodeunits(s)
    i = 1       # codeunit index
    cpos = 1    # 1-based character index of codeunit i
    while i <= n
        cu = codeunit(s, i)
        if cu == 0x20 || cu == 0x09 || cu == 0x0a || cu == 0x0d
            i += 1
            cpos += 1
            continue
        end
        start = cpos
        if 0x30 <= cu <= 0x39 ||
           (cu == 0x2e && i < n && 0x30 <= codeunit(s, i + 1) <= 0x39)
            # A number: digits with at most one '.' (e.g. "123", "0.5",
            # "123.456", ".5", "12.").  Convert while scanning so no
            # intermediate string is needed.
            val = 0.0
            frac = 0          # digits seen after the '.'
            seen_dot = false
            while i <= n
                c = codeunit(s, i)
                if 0x30 <= c <= 0x39
                    val = val * 10 + (c - 0x30)
                    if seen_dot
                        frac += 1
                    end
                elseif c == 0x2e && !seen_dot
                    seen_dot = true
                else
                    break
                end
                i += 1
                cpos += 1
            end
            if frac > 0
                val /= 10.0 ^ frac
            end
            push!(toks, Token(TK_NUM, val, start))
            continue
        end
        kind = if cu == 0x2b; TK_PLUS
               elseif cu == 0x2d; TK_MINUS
               elseif cu == 0x2a; TK_STAR
               elseif cu == 0x2f; TK_SLASH
               elseif cu == 0x5e; TK_CARET
               elseif cu == 0x28; TK_LPAREN
               elseif cu == 0x29; TK_RPAREN
               else 0x00
               end
        if kind != 0x00
            push!(toks, Token(kind, 0.0, start))
            i += 1
            cpos += 1
            continue
        end
        # Anything else is not part of the grammar.
        if cu < 0x80
            name = string(Char(cu))
        else
            name = try
                string(s[cpos])
            catch
                "invalid UTF-8 byte"
            end
        end
        throw(ParseError("unexpected character \"$name\" at position $cpos", cpos))
    end
    push!(toks, Token(TK_EOF, 0.0, cpos))
    return toks
end

# ---------------------------------------------------------------------------
# Parser (recursive descent, evaluating as it parses)
# ---------------------------------------------------------------------------

@inline function tokname(t::Token)
    k = t.kind
    if k == TK_NUM; return "number"
    elseif k == TK_PLUS; return "'+'"
    elseif k == TK_MINUS; return "'-'"
    elseif k == TK_STAR; return "'*'"
    elseif k == TK_SLASH; return "'/'"
    elseif k == TK_CARET; return "'^'"
    elseif k == TK_LPAREN; return "'('"
    elseif k == TK_RPAREN; return "')'"
    end
    return "end of input"
end

@inline function expect_rparen(t::Vector{Token}, i::Int)
    if t[i].kind != TK_RPAREN
        throw(ParseError(
            "expected ')' but found $(tokname(t[i])) at position $(t[i].pos)",
            t[i].pos))
    end
end

@inline function expect_number(t::Vector{Token}, i::Int)
    throw(ParseError(
        "expected a number or '(' but found $(tokname(t[i])) at position $(t[i].pos)",
        t[i].pos))
end

"""
    parse_power(t, i, base)

Handles `power := atom ('^' factor)*` given an already-parsed base atom and
the token index `i` just past it.  The right-associative chain
`a0 ^ s1*a1 ^ s2*a2 ...` (sj ∈ {+1,-1}) is collected as the vector
`[a0, s1*a1, s2*a2, ...]` and folded from the right, so a long `^` chain
does not recurse.  A parenthesized exponent re-enters `parse_expr`.
Returns `(value, next_i)`.
"""
function parse_power(t::Vector{Token}, i::Int, base::Float64)
    if t[i].kind != TK_CARET
        return base, i
    end
    chain = Float64[base]
    while t[i].kind == TK_CARET
        i += 1
        s = 1
        while t[i].kind == TK_MINUS   # exponent is a full factor: '-'* power
            i += 1
            s = -s
        end
        # exponent base atom
        k = t[i].kind
        if k == TK_NUM
            a = t[i].val
            i += 1
        elseif k == TK_LPAREN
            a, i = parse_expr(t, i + 1)
            expect_rparen(t, i)
            i += 1
        else
            expect_number(t, i)
        end
        push!(chain, s * a)
    end
    acc = chain[end]
    for j in (length(chain) - 1):-1:2
        acc = chain[j] ^ acc
    end
    return chain[1] ^ acc, i
end

"""
    parse_expr(t, i)

Recursive-descent parser for the whole grammar, starting at token index `i`:

    expr   := term (('+' | '-') term)*
    term   := factor (('*' | '/') factor)*
    factor := '-'* power
    power  := atom ('^' factor)*        (handled by parse_power)
    atom   := NUMBER | '(' expr ')'

Returns `(value, next_i)`.

`parse_expr` is the single function on the recursion path for nested
parentheses: `expr`, `term`, and `factor` are all inlined as pending-operator
loops (so the factor code appears exactly once), and a parenthesized base
atom re-enters `parse_expr` directly.  Each paren level therefore costs exactly
one `parse_expr` frame — the leanest possible frame, since the right-associative
`^` chain is delegated to `parse_power` *after* the base atom is parsed, so the
chain's collected vector lives in `parse_power`'s frame, not here.  That keeps
`((((...1...))))`-style expressions (tens of thousands of nested parens) well
within the call stack, while a long `^` chain is handled iteratively by
`parse_power`.
"""
function parse_expr(t::Vector{Token}, i::Int)
    op = 0          # pending '+'/'-' operator (0 = none yet)
    v = 0.0         # running expression value
    while true
        # ===================== one term =====================
        # term := factor (('*'|'/') factor)*, as a pending-operator loop so the
        # factor code below appears exactly once in this function.
        op2 = 0     # pending '*'/'/' operator (0 = none yet)
        f = 0.0     # running term value
        while true
            # ---- one factor: '-'* power ----
            negs = 0
            while t[i].kind == TK_MINUS
                i += 1
                negs += 1
            end
            # ---- base atom (inlined: the nested-paren recursion point) ----
            if t[i].kind == TK_NUM
                g = t[i].val
                i += 1
            elseif t[i].kind == TK_LPAREN
                g, i = parse_expr(t, i + 1)
                expect_rparen(t, i)
                i += 1
            else
                expect_number(t, i)
            end
            # ---- '^' chain (delegated; not on the nested-paren path) ----
            g, i = parse_power(t, i, g)
            if isodd(negs)
                g = -g
            end
            # ---- apply pending '*'/'/' ----
            if op2 == 0
                f = g
            elseif op2 == TK_STAR
                f = f * g
            else
                f = f / g
            end
            # ---- look ahead within the term ----
            if t[i].kind == TK_STAR || t[i].kind == TK_SLASH
                op2 = t[i].kind
                i += 1
                continue
            end
            break
        end
        # ===================== apply pending '+'/'-' =====================
        if op == 0
            v = f
        elseif op == TK_PLUS
            v = v + f
        else
            v = v - f
        end
        # ===================== look ahead for the next term =====================
        if t[i].kind == TK_PLUS || t[i].kind == TK_MINUS
            op = t[i].kind
            i += 1
            continue
        end
        break
    end
    return v, i
end

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

"""
    evaluate(s)

Parse and evaluate the arithmetic expression in `s`, returning a `Float64`.

Supports integers and decimals, the operators `+ - * / ^`, parentheses, and
unary minus.  `^` is right-associative and binds tighter than unary minus,
so `-2^2 == -4` and `2^3^2 == 512`.

Throws a [`ParseError`](@ref) naming the problem and the 1-based character
position for malformed input (unexpected characters, missing operands,
unbalanced parentheses, empty input, ...).  Division and powers follow
`Float64` semantics (`1/0` is `Inf`, `0.0^-1` is `Inf`, `(-1.0)^0.5` is
`NaN`), consistent with Julia itself.
"""
function evaluate(s::AbstractString)::Float64
    toks = tokenize(s)
    if toks[1].kind == TK_EOF
        throw(ParseError("empty expression at position 1", 1))
    end
    v, i = parse_expr(toks, 1)
    if toks[i].kind != TK_EOF
        throw(ParseError(
            "unexpected $(tokname(toks[i])) at position $(toks[i].pos)",
            toks[i].pos))
    end
    return v
end
