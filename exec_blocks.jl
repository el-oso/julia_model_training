# Child process for build.jl: evaluates code blocks from a JSON array, each in a fresh
# module inside a temporary working directory, starting at block `start`.
# Protocol on stdout: "BEGIN i" before each block, "FAIL i <message>" on error.

using JSON

function main(input, start)
    blocks = JSON.parse(read(input, String))
    return mktempdir() do dir
        cd(dir) do
            for i in start:lastindex(blocks)
                println("BEGIN ", i); flush(stdout)
                # A `module` expression, unlike `Module(name)`, defines `eval` and `include`.
                mod = Core.eval(Main, Expr(:module, true, Symbol("block", i), Expr(:block)))
                err = try
                    redirect_stdout(devnull) do
                        redirect_stderr(devnull) do
                            Core.eval(mod, Meta.parseall(blocks[i]))
                        end
                    end
                    nothing
                catch e
                    e
                end
                if !isnothing(err)
                    msg = replace(sprint(showerror, err), '\n' => ' ')
                    println("FAIL ", i, " ", first(msg, 300)); flush(stdout)
                end
            end
        end
    end
end

main(ARGS[1], parse(Int, ARGS[2]))
