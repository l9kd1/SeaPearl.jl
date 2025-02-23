using KernelAbstractions, CUDA

struct HeterogeneousGraphConv{A<:AbstractMatrix,B,G<:pool}
    weightsvar::A
    weightscon::A
    weightsval::A
    biasvar::B
    biascon::B
    biasval::B
    σ
    pool::G
end

function HeterogeneousGraphConv(ch::Pair{Int,Int}, original_dimensions::Array{Int}, σ=Flux.leakyrelu; init=Flux.glorot_uniform, bias::Bool=true, T::DataType=Float32, pool::pool=meanPooling())
    in, out = ch
    weightsvar = init(out, 3 * in + original_dimensions[1])
    biasvar = bias ? T.(init(out)) : zeros(T, out)
    weightscon = init(out, 2 * in + original_dimensions[2])
    biascon = bias ? T.(init(out)) : zeros(T, out)
    weightsval = init(out, 2 * in + original_dimensions[3])
    biasval = bias ? T.(init(out)) : zeros(T, out)
    return HeterogeneousGraphConv(weightsvar, weightscon, weightsval, biasvar, biascon, biasval, σ, pool)
end

Flux.@functor HeterogeneousGraphConv

function (g::HeterogeneousGraphConv{<:AbstractMatrix,<:Any,sumPooling})(fgs::BatchedHeterogeneousFeaturedGraph{Float32}, original_fgs::BatchedHeterogeneousFeaturedGraph{Float32})
    contovar, valtovar = fgs.contovar, fgs.valtovar
    vartocon, vartoval = permutedims(contovar, [2, 1, 3]), permutedims(valtovar, [2, 1, 3])
    H1, H2, H3 = fgs.varnf, fgs.connf, fgs.valnf
    X1, X2, X3 = original_fgs.varnf, original_fgs.connf, original_fgs.valnf
    contovarN, valtovarN, vartoconN, vartovalN = contovar, valtovar, vartocon, vartoval

    return BatchedHeterogeneousFeaturedGraph{Float32}(
        contovar,
        valtovar,
        g.σ.(g.weightsvar ⊠ vcat(X1, H1, H2 ⊠ contovarN, H3 ⊠ valtovarN) .+ g.biasvar),
        g.σ.(g.weightscon ⊠ vcat(X2, H2, H1 ⊠ vartoconN) .+ g.biascon),
        g.σ.(g.weightsval ⊠ vcat(X3, H3, H1 ⊠ vartovalN) .+ g.biasval),
        fgs.gf
    )
end

function (g::HeterogeneousGraphConv{<:AbstractMatrix,<:Any,sumPooling})(fg::HeterogeneousFeaturedGraph, original_fg::HeterogeneousFeaturedGraph)
    contovar, valtovar = fg.contovar, fg.valtovar
    vartocon, vartoval = transpose(contovar), transpose(valtovar)
    H1, H2, H3 = fg.varnf, fg.connf, fg.valnf
    X1, X2, X3 = original_fg.varnf, original_fg.connf, original_fg.valnf
    contovarN, valtovarN, vartoconN, vartovalN = contovar, valtovar, vartocon, vartoval

    return HeterogeneousFeaturedGraph(
        contovar,
        valtovar,
        g.σ.(g.weightsvar * vcat(X1, H1, H2 * contovarN, H3 * valtovarN) .+ g.biasvar),
        g.σ.(g.weightscon * vcat(X2, H2, H1 * vartoconN) .+ g.biascon),
        g.σ.(g.weightsval * vcat(X3, H3, H1 * vartovalN) .+ g.biasval),
        fg.gf
    )
end

function (g::HeterogeneousGraphConv{<:AbstractMatrix,<:Any,meanPooling})(fgs::BatchedHeterogeneousFeaturedGraph{Float32}, original_fgs::BatchedHeterogeneousFeaturedGraph{Float32})
    contovar, valtovar = fgs.contovar, fgs.valtovar
    vartocon, vartoval = permutedims(contovar, [2, 1, 3]), permutedims(valtovar, [2, 1, 3])
    H1, H2, H3 = fgs.varnf, fgs.connf, fgs.valnf
    X1, X2, X3 = original_fgs.varnf, original_fgs.connf, original_fgs.valnf

    MatVar, MatCon, MatVal = nothing,nothing,nothing
    ChainRulesCore.ignore_derivatives() do
    sumcontovar =  sum(contovar, dims = 1)
    sumvaltovar =  sum(valtovar, dims = 1)
    sumvartocon =  sum(vartocon, dims = 1)
    sumvartoval =  sum(vartoval, dims = 1)

    sumcontovar = max.(sumcontovar, device(sumcontovar) != Val{:cpu}() ? CUDA.ones(size(sumcontovar)) : ones(size(sumcontovar)))
    sumvaltovar = max.(sumvaltovar, device(sumvaltovar) != Val{:cpu}() ? CUDA.ones(size(sumvaltovar)) : ones(size(sumvaltovar)))
    sumvartocon = max.(sumvartocon, device(sumvartocon) != Val{:cpu}() ? CUDA.ones(size(sumvartocon)) : ones(size(sumvartocon)))
    sumvartoval = max.(sumvartoval, device(sumvartoval) != Val{:cpu}() ? CUDA.ones(size(sumvartoval)) : ones(size(sumvartoval)))

    contovarN = contovar ./ sumcontovar
    valtovarN = valtovar ./ sumvaltovar
    vartoconN = vartocon ./ sumvartocon
    vartovalN = vartoval ./ sumvartoval

    MatVar =  vcat(X1, H1, H2 ⊠ contovarN, H3 ⊠ valtovarN)
    MatCon = vcat(X2, H2, H1 ⊠ vartoconN)
    MatVal =  vcat(X3, H3, H1 ⊠ vartovalN) 
    end
    XX1 = g.σ.(g.weightsvar ⊠ MatVar .+ g.biasvar)
    XX2 = g.σ.(g.weightscon ⊠ MatCon .+ g.biascon)
    XX3 = g.σ.(g.weightsval ⊠ MatVal .+ g.biasval)

    ChainRulesCore.ignore_derivatives() do
        return BatchedHeterogeneousFeaturedGraph{Float32}(
        contovar,
        valtovar,
        XX1,
        XX2,
        XX3,
        fgs.gf
    )
    end
end

function (g::HeterogeneousGraphConv{<:AbstractMatrix,<:Any,meanPooling})(fg::HeterogeneousFeaturedGraph, original_fg::HeterogeneousFeaturedGraph)
    contovar, valtovar = fg.contovar, fg.valtovar
    vartocon, vartoval = permutedims(contovar, [2, 1]), permutedims(valtovar, [2, 1])
    H1, H2, H3 = fg.varnf, fg.connf, fg.valnf
    X1, X2, X3 = original_fg.varnf, original_fg.connf, original_fg.valnf

    MatVar, MatCon, MatVal = nothing,nothing,nothing
    sumcontovar,sumvaltovar,sumvartocon,sumvartoval = nothing,nothing,nothing,nothing
    ChainRulesCore.ignore_derivatives() do
        sumcontovar = sum(contovar, dims =1)
        sumvaltovar = sum(valtovar, dims =1)
        sumvartocon = sum(vartocon, dims =1)
        sumvartoval = sum(vartoval, dims =1)

        sumcontovar = max.(sumcontovar, device(sumcontovar) != Val{:cpu}() ? CUDA.ones(size(sumcontovar)) : ones(size(sumcontovar)))
        sumvaltovar = max.(sumvaltovar, device(sumvaltovar) != Val{:cpu}() ? CUDA.ones(size(sumvaltovar)) : ones(size(sumvaltovar)))
        sumvartocon = max.(sumvartocon, device(sumvartocon) != Val{:cpu}() ? CUDA.ones(size(sumvartocon)) : ones(size(sumvartocon)))
        sumvartoval = max.(sumvartoval, device(sumvartoval) != Val{:cpu}() ? CUDA.ones(size(sumvartoval)) : ones(size(sumvartoval)))


        contovarN = contovar ./ sumcontovar
        valtovarN = valtovar ./ sumvaltovar
        vartoconN = vartocon ./ sumvartocon
        vartovalN = vartoval ./ sumvartoval

        MatVar = vcat(X1, H1, H2 * contovarN, H3 * valtovarN)
        MatCon = vcat(X2, H2, H1 * vartoconN)
        MatVal =  vcat(X3, H3, H1 * vartovalN) 
    end

    XX1 = g.σ.(g.weightsvar * MatVar .+ g.biasvar)
    XX2 = g.σ.(g.weightscon * MatCon .+ g.biascon)
    XX3 = g.σ.(g.weightsval * MatVal.+ g.biasval)
    ChainRulesCore.ignore_derivatives() do
    return HeterogeneousFeaturedGraph(
        contovar,
        valtovar,
        XX1,
        XX2,
        XX3,
        fg.gf
    )
    end
end

"""
function (g::HeterogeneousGraphConv{<:AbstractMatrix,<:Any, maxPooling})(fg::HeterogeneousFeaturedGraph, original_fg::HeterogeneousFeaturedGraph)

This function operates the coordinate-wise max-Pooling technique along the neightbors of every node of the batched input BatchedHeterogeneousFeaturedGraph.
    
For more details about the operations, please look at function (g::GraphConv{<:AbstractMatrix,<:Any, maxPooling})(fg::FeaturedGraph) in graphConv.jl. The same operations are done 4 times considering type-specific embeddings and adjacency matrix. 
"""
function (g::HeterogeneousGraphConv{<:AbstractMatrix,<:Any, maxPooling})(fgs::BatchedHeterogeneousFeaturedGraph{Float32}, original_fgs::BatchedHeterogeneousFeaturedGraph{Float32})
    contovar, valtovar = fgs.contovar, fgs.valtovar
    vartocon, vartoval = permutedims(contovar, [2, 1, 3]), permutedims(valtovar, [2, 1, 3])
    H1, H2, H3 = fgs.varnf, fgs.connf, fgs.valnf
    X1, X2, X3 = original_fgs.varnf, original_fgs.connf, original_fgs.valnf
    contovarN, valtovarN, vartoconN, vartovalN = contovar, valtovar, vartocon, vartoval
    filteredembcontovar = nothing
    filteredembvartocon = nothing
    filteredembvaltovar = nothing
    filteredembvartoval = nothing

    ChainRulesCore.ignore_derivatives() do
        contovarIdx = repeat(collect(1:size(contovar,1)),1,size(contovar,2)).*contovar
        valtovarIdx = repeat(collect(1:size(valtovar,1)),1,size(valtovar,2)).*valtovar
        vartoconIdx = repeat(collect(1:size(vartocon,1)),1,size(vartocon,2)).*vartocon
        vartovalIdx = repeat(collect(1:size(vartoval,1)),1,size(vartoval,2)).*vartoval

        contovarIdx = collect.(zip(contovarIdx,cat([repeat([i],size(contovar)[1:2]...) for i in 1:size(contovar)[3]]..., dims= 3)))
        valtovarIdx = collect.(zip(valtovarIdx,cat([repeat([i],size(valtovar)[1:2]...) for i in 1:size(valtovar)[3]]..., dims= 3)))
        vartoconIdx = collect.(zip(vartoconIdx,cat([repeat([i],size(vartocon)[1:2]...) for i in 1:size(vartocon)[3]]..., dims= 3)))
        vartovalIdx = collect.(zip(vartovalIdx,cat([repeat([i],size(vartoval)[1:2]...) for i in 1:size(vartoval)[3]]..., dims= 3)))

        filteredcolcontovar = mapslices( x -> map(z-> filter(y -> y[1]!=0, z), eachcol(x)), contovarIdx, dims=[1,2])
        filteredcolvaltovar = mapslices( x -> map(z-> filter(y -> y[1]!=0, z), eachcol(x)), valtovarIdx, dims=[1,2])
        filteredcolvartocon = mapslices( x -> map(z-> filter(y -> y[1]!=0, z), eachcol(x)), vartoconIdx, dims=[1,2])
        filteredcolvartoval = mapslices( x -> map(z-> filter(y -> y[1]!=0, z), eachcol(x)), vartovalIdx, dims=[1,2])

        filteredembcontovar = mapslices(x->map(y-> !isempty(y) ? reshape(Base.maximum(mapreduce(z->H2[:,z...], hcat, y), dims =2),:) : zeros(Float32,size(H2,1)),  x), filteredcolcontovar, dims = [1,3])
        filteredembvaltovar = mapslices(x->map(y-> !isempty(y) ? reshape(Base.maximum(mapreduce(z->H3[:,z...], hcat, y), dims =2), :) : zeros(Float32,size(H3,1)),  x), filteredcolvaltovar, dims = [1,3])
        filteredembvartocon = mapslices(x->map(y-> !isempty(y) ? reshape(Base.maximum(mapreduce(z->H1[:,z...], hcat, y), dims =2), :) : zeros(Float32,size(H1,1)),  x), filteredcolvartocon, dims = [1,3])
        filteredembvartoval  = mapslices(x->map(y-> !isempty(y) ? reshape(Base.maximum(mapreduce(z->H1[:,z...], hcat, y), dims =2),:) : zeros(Float32,size(H1,1)),  x), filteredcolvartoval , dims = [1,3])
        filteredembcontovar = reshape(reduce(hcat ,filteredembcontovar), :,size(H1)[2:3]...)
        filteredembvaltovar = reshape(reduce(hcat ,filteredembvaltovar), :,size(H1)[2:3]...)
        filteredembvartocon = reshape(reduce(hcat ,filteredembvartocon), :,size(H2)[2:3]...)
        filteredembvartoval = reshape(reduce(hcat ,filteredembvartoval), :,size(H3)[2:3]...)
    end
    return BatchedHeterogeneousFeaturedGraph{Float32}(
        contovar,
        valtovar,
        g.σ.(g.weightsvar ⊠ vcat(X1, H1, filteredembcontovar, filteredembvaltovar) .+ g.biasvar),
        g.σ.(g.weightscon ⊠ vcat(X2, H2, filteredembvartocon) .+ g.biascon),
        g.σ.(g.weightsval ⊠ vcat(X3, H3, filteredembvartoval) .+ g.biasval),
        fgs.gf
    )
end
"""
function (g::HeterogeneousGraphConv{<:AbstractMatrix,<:Any, maxPooling})(fg::HeterogeneousFeaturedGraph, original_fg::HeterogeneousFeaturedGraph)

This function operates the coordinate-wise max-Pooling technique along the neightbors of every node of the non-batched input HeterogeneousFeaturedGraph.

For more details about the operations, please look at function (g::GraphConv{<:AbstractMatrix,<:Any, maxPooling})(fg::FeaturedGraph) in graphConv.jl. The same operations are done 4 times considering type-specific embeddings and adjacency matrix. 
"""
function (g::HeterogeneousGraphConv{<:AbstractMatrix,<:Any, maxPooling})(fg::HeterogeneousFeaturedGraph, original_fg::HeterogeneousFeaturedGraph)
    contovar, valtovar = fg.contovar, fg.valtovar
    vartocon, vartoval = permutedims(contovar, [2, 1]), permutedims(valtovar, [2, 1])

    H1, H2, H3 = fg.varnf, fg.connf, fg.valnf
    X1, X2, X3 = original_fg.varnf, original_fg.connf, original_fg.valnf
    filteredembcontovar = nothing
    filteredembvaltovar = nothing
    filteredembvartocon = nothing
    filteredembvartoval = nothing
    ChainRulesCore.ignore_derivatives() do      
    
        contovarIdx = device(contovar) != Val{:cpu}() ? CuArray(repeat(collect(1:size(contovar,1)),1,size(contovar,2))) : repeat(collect(1:size(contovar,1)),1,size(contovar,2))
        valtovarIdx = device(valtovar) != Val{:cpu}() ? CuArray(repeat(collect(1:size(valtovar,1)),1,size(valtovar,2))) : repeat(collect(1:size(valtovar,1)),1,size(valtovar,2))
        vartoconIdx = device(vartocon) != Val{:cpu}() ? CuArray(repeat(collect(1:size(vartocon,1)),1,size(vartocon,2))) : repeat(collect(1:size(vartocon,1)),1,size(vartocon,2))
        vartovalIdx = device(vartoval) != Val{:cpu}() ? CuArray(repeat(collect(1:size(vartoval,1)),1,size(vartoval,2))) : repeat(collect(1:size(vartoval,1)),1,size(vartoval,2))

        contovarIdx = contovarIdx.*contovar
        valtovarIdx = valtovarIdx.*valtovar
        vartoconIdx = vartoconIdx.*vartocon
        vartovalIdx = vartovalIdx.*vartoval

        filteredcolcontovar = map(x-> filter(y -> y!=0,x),eachcol(contovarIdx))
        filteredcolvaltovar = map(x-> filter(y -> y!=0,x),eachcol(valtovarIdx))
        filteredcolvartocon = map(x-> filter(y -> y!=0,x),eachcol(vartoconIdx))
        filteredcolvartoval = map(x-> filter(y -> y!=0,x),eachcol(vartovalIdx))

        filteredembcontovar = mapreduce(x->!isempty(x) ? Base.maximum(H2[:,x], dims = 2) : zeros(Float32,size(H2,1)), hcat, filteredcolcontovar)
        filteredembvaltovar = mapreduce(x->!isempty(x) ? Base.maximum(H3[:,x], dims = 2) : zeros(Float32,size(H3,1)), hcat, filteredcolvaltovar)
        filteredembvartocon = mapreduce(x->!isempty(x) ? Base.maximum(H1[:,x], dims = 2) : zeros(Float32,size(H1,1)), hcat, filteredcolvartocon)
        filteredembvartoval = mapreduce(x->!isempty(x) ? Base.maximum(H1[:,x], dims = 2) : zeros(Float32,size(H1,1)), hcat, filteredcolvartoval)
    end
    return HeterogeneousFeaturedGraph(
        contovar,
        valtovar,
        g.σ.(g.weightsvar * vcat(X1, H1, filteredembcontovar, filteredembvaltovar) .+ g.biasvar),
        g.σ.(g.weightscon * vcat(X2, H2, filteredembvartocon) .+ g.biascon),
        g.σ.(g.weightsval * vcat(X3, H3, filteredembvartoval) .+ g.biasval),
        fg.gf
    )
    
end