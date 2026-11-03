"""
    evaluate(s::AbstractString)::Float64

Evaluate an arithmetic expression containing integers, decimals, `+ - * / ^`,
parentheses, and unary minus/plus.

* `^` is right-associative and binds tighter than unary minus: `-2^2 == -4`.
* Malformed input throws `ArgumentError` naming the problem and the byte/character position.
* Designed for expressions up to 10^5 characters to run in a few milliseconds
  (no `Meta.parse`, no `eval`; hand-written lexer + recursive-descent parser).

Grammar (Python precedence, ^ tighter than unary minus):

    expr       = term (('+' | '-') term)*
    term       = factor (('*' | '/') factor)*
    factor     = ('-' | '+') factor | power
    power      = atom ('^' unary_expr)*       -- right-associative
    unary_expr = ('-' | '+') unary_expr | power
    atom       = '(' expr ')' | NUMBER

The mutual recursion power ↔ unary_expr is what makes ^ bind tighter than unary
minus: the right operand of ^ is unary_expr→power→atom (no * /), not unary_expr→term (which has * /).
"""
function evaluate(s::AbstractString)::Float64
    p = Ref{Int}(1)
    len = length(s)

    # ── helpers ───────────────────────────────────────────────────────────
    eof()    = p[] > len
    peek()   = eof() ? '\0' : s[p[]]
    next_()  = (c = peek(); p[] += 1; c)
    skip_ws() = while !eof() && isspace(s[p[]]); p[] += 1; end

    # ── grammar ──────────────────────────────────────────────────────────

    # expr = term (('+' | '-') term)*
    function expr()::Float64
        left = term()
        while !eof()
            skip_ws()
            c = peek()
            if c == '+'
                next_(); left += term()
            elseif c == '-'
                next_(); left -= term()
            else
                break
            end
        end
        return left
    end

    # term = factor (('*' | '/') factor)*
    function term()::Float64
        left = factor()
        while !eof()
            skip_ws()
            c = peek()
            if c == '*'
                next_(); left *= factor()
            elseif c == '/'
                next_()
                right = factor()
                if right == 0.0
                    error("division by zero at position $(p[])")
                end
                left /= right
            else
                break
            end
        end
        return left
    end

    # factor = ('-' | '+') factor | power
    function factor()::Float64
        skip_ws()
        c = peek()
        if c == '-'
            next_(); return -factor()
        elseif c == '+'
            next_(); return factor()
        end
        return power()
    end

    # power = atom ('^' unary_expr)*   -- right-associative
    #   left side  = atom (no unary, so -2^2 = -(2^2))
    #   right side = unary_expr (handles unary, so 2^-2 = 2^(-2))
    #   unary_expr→power→atom (no *) makes ^ bind tighter than *
    function power()::Float64
        left = atom()
        skip_ws()
        while !eof() && peek() == '^'
            next_(); skip_ws()
            right = unary_expr()   # right-associative → recurse into unary_expr
            left = left ^ right
        end
        return left
    end

    # unary_expr = ('-' | '+') unary_expr | power
    #   (same as factor but at the ^ right-operand level)
    function unary_expr()::Float64
        skip_ws()
        c = peek()
        if c == '-'
            next_(); return -unary_expr()
        elseif c == '+'
            next_(); return unary_expr()
        end
        return power()
    end

    # atom = '(' expr ')' | NUMBER
    function atom()::Float64
        skip_ws()
        c = peek()
        if c == '('
            next_()
            val = expr()
            skip_ws()
            if !eof() && peek() == ')'
                next_(); return val
            else
                error("missing closing ')' at position $(p[])")
            end
        elseif isdigit(c) || c == '.'
            return number()
        else
            throw(ArgumentError("unexpected character '$c' at position $(p[])"))
        end
    end

    # number lexer
    function number()::Float64
        start = p[]
        while !eof() && isdigit(s[p[]]); p[] += 1; end
        if !eof() && s[p[]] == '.'
            p[] += 1
            while !eof() && isdigit(s[p[]]); p[] += 1; end
        end
        if p[] == start
            throw(ArgumentError("expected number at position $(p[])"))
        end
        parse(Float64, @view s[start:p[]-1])
    end

    # ── top-level ────────────────────────────────────────────────────────
    val = expr()
    if !eof()
        throw(ArgumentError("unexpected character '$(s[p[]])' at position $(p[])"))
    end
    return val
end
