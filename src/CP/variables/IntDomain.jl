abstract type AbstractIntDomain end

struct IntDomain <: AbstractIntDomain
    values          ::Array{Int}
    indexes         ::Array{Int}
    offset          ::Int
    initSize        ::Int
    size            ::CPRL.StateObject{Int}
    min             ::CPRL.StateObject{Int}
    max             ::CPRL.StateObject{Int}
    trailer         ::CPRL.Trailer

    """
        IntDomain(trailer::Trailer, n::Int, offset::Int)

    Create an integer domain going from `ofs + 1` to `ofs + n`.
    """
    function IntDomain(trailer::Trailer, n::Int, offset::Int)

        size = CPRL.StateObject{Int}(n, trailer)
        min = CPRL.StateObject{Int}(offset + 1, trailer)
        max = CPRL.StateObject{Int}(offset + n, trailer)
        values = zeros(n)
        indexes = zeros(n)
        for i in 1:n
            values[i] = i
            indexes[i] = i
        end
        return new(values, indexes, offset, n, size, min, max, trailer)
    end
end

function Base.show(io::IO, dom::IntDomain)
    toPrint = "["
    for i in dom
        toPrint *= string(i)*" "
    end
    toPrint *= "]"
    write(io, toPrint)
end

"""
    isempty(dom::IntDomain)

Return `true` iff `dom` is an empty set.
"""
Base.isempty(dom::CPRL.IntDomain) = dom.size.value == 0



"""
    length(dom::IntDomain)

Return the size of `dom`.
"""
Base.length(dom::CPRL.IntDomain) = dom.size.value

"""
    Base.in(value::Int, dom::IntDomain)

Check if an integer is in the domain.
"""
function Base.in(value::Int, dom::IntDomain)
    value -= dom.offset
    if value < 1 || value > dom.initSize
        return false
    end
    return dom.indexes[value] <= length(dom)
end


"""
    remove!(dom::IntDomain, value::Int)

Remove `value` from `dom`.
"""
function remove!(dom::IntDomain, value::Int)
    if !(value in dom)
        return Int[]
    end

    value -= dom.offset

    exchangePositions!(dom, value, dom.values[dom.size.value])
    setValue!(dom.size, dom.size.value - 1)

    updateBoundsFromRemovedVal!(dom, value+dom.offset)

    return [value+dom.offset]
end

"""
    removeAll!(dom::IntDomain)

Remove every value from `dom`. Return the removed values.
"""
function removeAll!(dom::IntDomain)
    removed = Array{Int}(undef, dom.size.value)
    for i in 1:dom.size.value
        removed[i] = dom.values[i] + dom.offset
    end

    setValue!(dom.size, 0)
    return removed
end

"""
    removeAbove!(dom::IntDomain, value::Int)

Remove every integer of `dom` that is *strictly* above `value`.
"""
function removeAbove!(dom::IntDomain, value::Int)
    if dom.min.value > value
        return removeAll!(dom)
    end

    pruned = Int[]
    for i in (value+1):dom.max.value
        if i in dom
            remove!(dom, i)
            push!(pruned, i)
        end
    end
    return pruned
end

"""
    removeBelow!(dom::IntDomain, value::Int)

Remove every integer of `dom` that is *strictly* below `value`. Return the pruned values.
"""
function removeBelow!(dom::IntDomain, value::Int)
    if dom.max.value < value
        return removeAll!(dom)
    end

    pruned = Int[]
    for i in dom.min.value:(value-1)
        if i in dom
            remove!(dom, i)
            push!(pruned, i)
        end
    end
    return pruned
end

"""
    assign!(dom::IntDomain, value::Int)

Remove everything from the domain but `value`. Return the removed values. Return the pruned values.
"""
function assign!(dom::IntDomain, value::Int)
    @assert value in dom

    value -= dom.offset

    exchangePositions!(dom, value, dom.values[1])

    removed = Array{Int}(undef, dom.size.value - 1)
    for i in 2:dom.size.value
        removed[i-1] = dom.values[i] + dom.offset
    end

    setValue!(dom.size, 1)
    setValue!(dom.max, value + dom.offset)
    setValue!(dom.min, value + dom.offset)

    return removed
end


"""
    Base.iterate(dom::IntDomain, state=1)

Iterate over the domain in an efficient way. The order may not be consistent.
WARNING: Do **NOT** update the domain you are iterating on.
"""
function Base.iterate(dom::IntDomain, state=1)
    @assert state >= 1
    if state > dom.size.value
        return nothing
    end

    return dom.values[state] + dom.offset, state+1
end

"""
    exchangePositions!(dom::IntDomain, v1::Int, v2::Int)

Intended for internal use only, exchange the position of `v1` and `v2` in the array of the domain.
"""
function exchangePositions!(dom::IntDomain, v1::Int, v2::Int)
    @assert(v1 <= length(dom.values) && v2 <= length(dom.values))

    i1, i2 = dom.indexes[v1], dom.indexes[v2]

    dom.values[i1] = v2
    dom.values[i2] = v1
    dom.indexes[v1] = i2
    dom.indexes[v2] = i1

    return dom
end

"""
    updateMaxFromRemovedVal!(dom::IntDomain, v::Int)

Knowing that `v` just got removed from `dom`, update `dom`'s maximum value.
"""
function updateMaxFromRemovedVal!(dom::IntDomain, v::Int)
    if !isempty(dom) && maximum(dom) == v
        @assert !(v in dom)
        currentVal = v - 1
        while currentVal >= minimum(dom)
            if currentVal in dom
                break
            end
            currentVal -= 1
        end
        setValue!(dom.max, currentVal)
    end
end

"""
    updateMinFromRemovedVal!(dom::IntDomain, v::Int)

Knowing that `v` just got removed from `dom`, update `dom`'s minimum value.
"""
function updateMinFromRemovedVal!(dom::IntDomain, v::Int)
    if !isempty(dom) && minimum(dom) == v
        @assert !(v in dom)
        currentVal = v + 1
        while currentVal <= maximum(dom)
            if currentVal in dom
                break
            end
            currentVal += 1
        end
        setValue!(dom.min, currentVal)
    end
end

"""
    updateBoundsFromRemovedVal!(dom::IntDomain, v::Int)

Knowing that `v` just got removed from `dom`, update `dom`'s minimum and maximum value.
"""
function updateBoundsFromRemovedVal!(dom::IntDomain, v::Int)
    updateMaxFromRemovedVal!(dom, v)
    updateMinFromRemovedVal!(dom, v)
end

"""
    minimum(dom::IntDomain)

Return the minimum value of `dom`.
"""
minimum(dom::IntDomain) = dom.min.value

"""
    maximum(dom::IntDomain)

Return the maximum value of `dom`.
"""
maximum(dom::IntDomain) = dom.max.value