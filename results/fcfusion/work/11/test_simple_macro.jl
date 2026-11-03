# Test: macro that generates a simple function definition

macro make_simple()
    return quote
        function hello(name::String)
            println("Hello, " * name)
        end
    end
end

@make_simple
hello("World")