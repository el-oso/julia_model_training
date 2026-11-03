# Helpers made available to every check via `using Main.EvalHelpers`.
module EvalHelpers

export alloc_of, dynamic_calls, rtype, is_stable

"""
    alloc_of(f, args...)

Bytes allocated by one call `f(args...)` after a warm-up call. Wrap keyword calls
in a closure: `alloc_of(() -> f(x; k=1))`.
"""
function alloc_of(f, args...)
    f(args...)
    return _alloc(f, args...)
end
function _alloc(f, args...)
    return @allocated f(args...)
end

"Inferred return type of `f` for the argument-type tuple `argtypes`."
rtype(f, argtypes) = only(Base.return_types(f, argtypes))

"True when the inferred return type is concrete."
is_stable(f, argtypes) = isconcretetype(rtype(f, argtypes))

function _scan!(bad, ci, seen, depth)
    for (i, st) in enumerate(ci.code)
        st isa Expr || continue
        ci.ssavaluetypes isa Vector && ci.ssavaluetypes[i] === Union{} && continue
        if st.head === :call
            callee = st.args[1]
            if callee isa GlobalRef
                v = isdefined(callee.mod, callee.name) ? getfield(callee.mod, callee.name) : nothing
                if v === Core._apply_iterate || !(v isa Core.Builtin || v isa Core.IntrinsicFunction)
                    push!(bad, st)
                end
            elseif callee isa Core.Builtin || callee isa Core.IntrinsicFunction
                callee === Core._apply_iterate && push!(bad, st)
            else
                push!(bad, st)
            end
        elseif st.head === :invoke && depth > 0
            a = st.args[1]
            mi = a isa Core.CodeInstance ? a.def : a
            mi isa Core.MethodInstance || continue
            mi in seen && continue
            push!(seen, mi)
            for c in Base.code_typed_by_type(mi.specTypes; optimize = true)
                _scan!(bad, first(c), seen, depth - 1)
            end
        end
    end
    return bad
end

"""
    dynamic_calls(f, argtypes) -> Vector

Statements in the optimized IR of `f(argtypes...)`, and of the methods it calls
statically (to depth 8), that are dispatched at run time: `:call` of a generic
function (not a builtin or intrinsic) or of a non-constant callee, and
`Core._apply_iterate` (splatting a runtime-length collection). Statements that
never return (error paths) are ignored. Code that does I/O through the global
`stdout` is flagged, so checks should not call `dynamic_calls` on printing code.
"""
function dynamic_calls(f, argtypes)
    cis = code_typed(f, argtypes; optimize = true)
    isempty(cis) && error("no method of $f for $argtypes")
    return _scan!(Any[], first(first(cis)), Base.IdSet{Any}(), 8)
end

end # module
