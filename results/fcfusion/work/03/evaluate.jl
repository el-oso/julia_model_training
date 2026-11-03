function evaluate(s::AbstractString)::Float64
    pos = 1
    len = length(s)

    function skip_whitespace()
        while pos <= len && isspace(s[pos])
            pos += 1
        end
    end

    function parse_number()
        skip_whitespace()
        start = pos
        has_dot = false

        while pos <= len
            c = s[pos]
            if '0' <= c <= '9'
                pos += 1
            elseif c == '.' && !has_dot
                has_dot = true
                pos += 1
            else
                break
            end
        end

        if pos == start
            throw(ArgumentError("Expected number at position $pos"))
        end

        return parse(Float64, s[start:pos-1])
    end

    # expr := term ((+ | -) term)*
    function parse_expr()
        val = parse_term()
        while true
            skip_whitespace()
            if pos <= len && s[pos] == '+'
                pos += 1
                right = parse_term()
                val = val + right
            elseif pos <= len && s[pos] == '-'
                pos += 1
                right = parse_term()
                val = val - right
            else
                break
            end
        end
        return val
    end

    # term := unary ((* | /) unary)*
    function parse_term()
        val = parse_unary()
        while true
            skip_whitespace()
            if pos <= len && s[pos] == '*'
                pos += 1
                right = parse_unary()
                val = val * right
            elseif pos <= len && s[pos] == '/'
                pos += 1
                right = parse_unary()
                if right == 0.0
                    throw(ArgumentError("Division by zero at position $pos"))
                end
                val = val / right
            else
                break
            end
        end
        return val
    end

    # unary := - unary | power
    # Note: unary has lower precedence than ^, so -2^2 == -4
    function parse_unary()
        skip_whitespace()
        if pos <= len && s[pos] == '-'
            pos += 1
            val = parse_unary()
            return -val
        end
        return parse_power()
    end

    # power := atom (^ unary)?
    # Right-associative: 2^3^4 == 2^(3^4)
    # Calls parse_unary after ^ to handle negative exponents like 2^-3
    function parse_power()
        val = parse_atom()
        skip_whitespace()
        if pos <= len && s[pos] == '^'
            pos += 1
            right = parse_unary()
            return val ^ right
        end
        return val
    end

    # atom := number | ( expr )
    function parse_atom()
        skip_whitespace()
        if pos > len
            throw(ArgumentError("Unexpected end of input at position $pos"))
        end

        c = s[pos]
        if '0' <= c <= '9' || c == '.'
            return parse_number()
        elseif c == '('
            pos += 1
            val = parse_expr()
            skip_whitespace()
            if pos > len || s[pos] != ')'
                throw(ArgumentError("Expected ')' at position $pos"))
            end
            pos += 1
            return val
        else
            throw(ArgumentError("Unexpected character '$c' at position $pos"))
        end
    end

    result = parse_expr()
    skip_whitespace()
    if pos <= len
        throw(ArgumentError("Unexpected character at position $pos"))
    end
    return result
end
