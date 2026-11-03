# Test: macro with esc()

macro make_simple()
    return esc(quote
        function hello(name::String)
            println("Hello, " * name)
        end
    end)
end

@make_simple
hello("World")