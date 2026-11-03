# Test: macro that generates a function with cache

macro make_cached()
    return quote
        let cache = Dict{Any, Any}()
            function cached_square(x)
                if haskey(cache, x)
                    return cache[x]
                end
                result = x * x
                cache[x] = result
                return result
            end
            cached_square
        end
    end
end

const cs = @make_cached
println(cs(5))
println(cs(5))  # Should be cached