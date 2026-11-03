# Test: macro that generates and returns a simple function

macro make_double()
    return quote
        let
            function double(x)
                return x * 2
            end
            double
        end
    end
end

const d = @make_double
println(d(5))