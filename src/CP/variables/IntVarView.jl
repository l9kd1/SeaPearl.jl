struct IntDomainViewMul <: IntDomainView
    orig            ::AbstractIntDomain
    a               ::Int
end


struct IntVarViewMul <: IntVarView
    x               ::AbstractIntVar
    a               ::Int
    domain          ::IntDomainViewMul
    id              ::String

    """
        IntVarViewMul(x::IntVar, a::Int, id::String)

    Create a *fake* variable `y`, such that `y == a*x`. This variable behaves like an usual one.
    """
    function IntVarViewMul(x::IntVar, a::Int, id::String)
        @assert a > 0
        dom = IntDomainViewMul(x.domain, a)
        return new(x, a, dom, id)
    end
end

struct IntDomainViewOpposite <: IntDomainView
    orig            ::AbstractIntDomain
end

struct IntVarViewOpposite <: IntVarView
    x               ::AbstractIntVar
    domain          ::IntDomainViewOpposite
    id              ::String

    """
    IntVarViewOpposite(x::IntVar, id::String)

    Create a *fake* variable `y`, such that `y = -x`. This variable behaves like an usual one.
    """
    function IntVarViewOpposite(x::IntVar, id::String)
        dom = IntDomainViewOpposite(x.domain)
        return new(x, dom, id)
    end
end

"""
    assignedValue(x::IntVarView)

Return the assigned value of `x`. Throw an error if `x` is not bound.
"""
assignedValue(x::IntVarViewMul) = x.a * assignedValue(x.x)
assignedValue(x::IntVarViewOpposite) = -1 * assignedValue(x.x)

"""
    isempty(dom::IntDomainView)

Return `true` iff `dom` is an empty set.
"""
Base.isempty(dom::IntDomainView) = isempty(dom.orig)

"""
    length(dom::IntDomainView)

Return the size of `dom`.
"""
Base.length(dom::IntDomainView) = length(dom.orig)

"""
    Base.in(value::Int, dom::IntDomainView)

Check if an integer is in the domain.
"""
function Base.in(value::Int, dom::IntDomainViewMul)
    if value % dom.a != 0
        return false
    end
    return (value ÷ dom.a) in dom.orig
end
Base.in(value::Int, dom::IntDomainViewOpposite) = -value in dom.orig

"""
    remove!(dom::IntDomainView, value::Int)

Remove `value` from `dom`.
"""
function remove!(dom::IntDomainViewMul, value::Int)
    if value % dom.a != 0
        return Int[]
    end

    return remove!(dom.orig, value ÷ dom.a)
end
remove!(dom::IntDomainViewOpposite, value::Int) = -1 * remove!(dom.orig, -value)

"""
    removeAll!(dom::IntDomainView)

Remove every value from `dom`. Return the removed values.
"""
removeAll!(dom::IntDomainViewMul) = dom.a * removeAll!(dom.orig)
removeAll!(dom::IntDomainViewOpposite) = -1 * removeAll!(dom.orig)


"""
    minimum(dom::IntDomainView)

Return the minimum value of `dom`.
"""
minimum(dom::IntDomainViewMul) = dom.a * minimum(dom.orig)
minimum(dom::IntDomainViewOpposite) = -1 * maximum(dom.orig)

"""
    maximum(dom::IntDomainView)

Return the maximum value of `dom`.
"""
maximum(dom::IntDomainViewMul) = dom.a * maximum(dom.orig)
maximum(dom::IntDomainViewOpposite) = -1 * minimum(dom.orig)


"""
    removeAbove!(dom::IntDomainView, value::Int)

Remove every integer of `dom` that is *strictly* above `value`.
"""
removeAbove!(dom::IntDomainViewMul, value::Int) = dom.a * removeAbove!(dom.orig, convert(Int, floor(value / dom.a)))
removeAbove!(dom::IntDomainViewOpposite, value::Int) = -1 * removeBelow!(dom.orig, -value)

"""
    removeBelow!(dom::IntDomainView, value::Int)

Remove every integer of `dom` that is *strictly* below `value`. Return the pruned values.
"""
removeBelow!(dom::IntDomainViewMul, value::Int) = dom.a * removeBelow!(dom.orig, convert(Int, ceil(value / dom.a)))
removeBelow!(dom::IntDomainViewOpposite, value::Int) = -1 * removeAbove!(dom.orig, -value)


"""
    assign!(dom::IntDomainView, value::Int)

Remove everything from the domain but `value`. Return the removed values. Return the pruned values.
"""
function assign!(dom::IntDomainViewMul, value::Int)
    @assert value % dom.a == 0
    return dom.a * assign!(dom.orig, value ÷ dom.a)
end
assign!(dom::IntDomainViewOpposite, value::Int) = -1 * assign!(dom.orig, -value)


"""
    Base.iterate(dom::IntDomainView, state=1)

Iterate over the domain in an efficient way. The order may not be consistent.
WARNING: Do **NOT** update the domain you are iterating on.
"""
function Base.iterate(dom::IntDomainViewMul, state=1)
    returned = iterate(dom.orig, state)
    if isnothing(returned)
        return nothing
    end

    value, newState = returned
    return value * dom.a, newState
end
function Base.iterate(dom::IntDomainViewOpposite, state=1)
    returned = iterate(dom.orig, state)
    if isnothing(returned)
        return nothing
    end

    value, newState = returned
    return -value, newState
end

"""
    updateMaxFromRemovedVal!(dom::IntDomainView, v::Int)

Knowing that `v` just got removed from `dom`, update `dom`'s maximum value.
"""
function updateMaxFromRemovedVal!(dom::IntDomainViewMul, v::Int)
    if maximum(dom) == v
        updateMaxFromRemovedVal!(dom.orig, v ÷ dom.a)
    end
end
function updateMaxFromRemovedVal!(dom::IntDomainViewOpposite, v::Int)
    if maximum(dom) == v
        updateMinFromRemovedVal!(dom.orig, -v)
    end
end

"""
    updateMinFromRemovedVal!(dom::IntDomainView, v::Int)

Knowing that `v` just got removed from `dom`, update `dom`'s minimum value.
"""
function updateMinFromRemovedVal!(dom::IntDomainViewMul, v::Int)
    if minimum(dom) == v
        updateMinFromRemovedVal!(dom.orig, v ÷ dom.a)
    end
end
function updateMinFromRemovedVal!(dom::IntDomainViewOpposite, v::Int)
    if minimum(dom) == v
        updateMaxFromRemovedVal!(dom.orig, -v)
    end
end