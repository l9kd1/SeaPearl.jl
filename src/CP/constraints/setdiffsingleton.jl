"""
    SetDiffSingleton(a::IntSetVar, b::IntSetVar, x::AbstractIntVar, trailer::Trailer)

SetDiffSingleton constraint, states that a = b - {x}
"""
struct SetDiffSingleton <: Constraint
    a       ::IntSetVar
    b       ::IntSetVar
    x       ::AbstractIntVar
    active  ::StateObject{Bool}
    function SetDiffSingleton(a::IntSetVar, b::IntSetVar, x::AbstractIntVar, trailer)
        constraint = new(a, b, x, StateObject{Bool}(true, trailer))
        addOnDomainChange!(a, constraint)
        addOnDomainChange!(b, constraint)
        addOnDomainChange!(x, constraint)
        return constraint
    end
end

"""
    propagate!(constraint::SetDiffSingleton, toPropagate::Set{Constraint}, prunedDomains::CPModification)

`SetDiffSingleton` propagation function. Pretty ugly. Inspired from OscaR.
"""
function propagate!(constraint::SetDiffSingleton, toPropagate::Set{Constraint}, prunedDomains::CPModification)
    a = constraint.a
    b = constraint.b
    x = constraint.x


    # For all b possible, exlucde if not possible in a and not in x domain
    for v in possible_not_required_values(b.domain)
        if !is_possible(a.domain, v) && !(isbound(x) && assignedValue(x) != v)
            if is_possible(b.domain, v)
                if !is_required(b.domain, v)
                    exclude!(b.domain, v)
                    triggerDomainChange!(toPropagate, b)
                else
                    return false
                end
            end
        end
    end

    # For all b required, require in a if not in x domain, remove from x domain if required in a
    for v in required_values(b.domain)
        if !(v in x.domain)
            if is_possible(a.domain, v)
                if !is_required(a.domain, v)
                    require!(a.domain, v)
                    triggerDomainChange!(toPropagate, a)
                end
            else
                return false
            end
        else
            if !is_possible(a.domain, v)
                removed = assign!(x, v)
                if !isempty(removed)
                    addToPrunedDomains!(prunedDomains, x, removed)
                    triggerDomainChange!(toPropagate, x)
                end
            end
        end
        if is_required(a.domain, v)
            if v in x.domain
                removed = remove!(x.domain, v)
                addToPrunedDomains!(prunedDomains, x, removed)
                triggerDomainChange!(toPropagate, x)
            end
        end
    end

    # For all possible in a, exclude from a if not possible in b
    for v in possible_not_required_values(a.domain)
        if !is_possible(b.domain, v)
            if is_possible(a.domain, v)
                if !is_required(a.domain, v)
                    exclude!(a.domain, v)
                    triggerDomainChange!(toPropagate, a)
                else
                    return false
                end
            end
        end
    end

    # For all required in a, require in b and remove from x domain
    for v in required_values(a.domain)
        if is_possible(b.domain, v)
            if !is_required(b.domain, v)
                require!(b.domain, v)
                triggerDomainChange!(toPropagate, b)
            end
        else
            return false
        end
        if v in x.domain
            removed = remove!(x.domain, v)
            addToPrunedDomains!(prunedDomains, x, removed)
            triggerDomainChange!(toPropagate, x)
        end
    end

    # If x is assigned v, exclude from a if not possible in b
    if isbound(x)
        v = assignedValue(x)
        if is_possible(a.domain, v)
            if !is_required(a.domain, v)
                exclude!(a.domain, v)
                triggerDomainChange!(toPropagate, a)
            else
                return false
            end
        end
    end

    # Deactivation
    if isbound(x)
        if (isbound(a) && isbound(b)) || possible_not_required_values(b.domain) == Set{Int}([assignedValue(x)])
            setValue!(constraint.active, false)
        end
    end

    return !isempty(x.domain)
end

variablesArray(constraint::SetDiffSingleton) = [constraint.a, constraint.b, constraint.x]