using Test
using CPRL
@testset "variables.jl" begin
    include("IntDomain.jl")
    include("IntVar.jl")
    include("IntVarViewMul.jl")
    include("IntVarViewOpposite.jl")
end