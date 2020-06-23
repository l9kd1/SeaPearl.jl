using CPRL
using ReinforcementLearning
const RL = ReinforcementLearning
using Flux

using Plots
gr()


problem_generator = Dict(
    :coloring => CPRL.fill_with_coloring!,
    :filecoloring => CPRL.fill_with_coloring_file!
)

coloring_file_params = Dict(
    "input_file" => "examples/coloring/data/gc_4_1"
)

coloring_params = Dict(
    "nb_nodes" => 10,
    "density" => 1.5
)

state_size = (46,93, 1)

agent = RL.Agent(
        policy = RL.QBasedPolicy(
            learner = RL.DQNLearner(
                approximator = RL.NeuralNetworkApproximator(
                    model = Chain(
                        Flux.flatten,
                        Dense(state_size[1]*state_size[2], 100, Flux.relu),
                        Dense(100, 50, Flux.relu),
                        Dense(50, 10, Flux.relu)
                    ),
                    optimizer = ADAM(0.001f0)
                ),
                target_approximator = RL.NeuralNetworkApproximator(
                    model = Chain(
                        Flux.flatten,
                        Dense(state_size[1]*state_size[2], 500, Flux.relu),
                        Dense(500, 100, Flux.relu),
                        Dense(100, 10, Flux.relu)
                    ),
                    optimizer = ADAM(0.001f0)
                ),
                loss_func = huber_loss,
                stack_size = nothing,
                γ = 0.99f0,
                batch_size = 32,
                update_horizon = 1,
                min_replay_history = 1,
                update_freq = 1,
                target_update_freq = 100,
                seed = 22,
            ), 
            explorer = RL.EpsilonGreedyExplorer(
                ϵ_stable = 0.01,
                kind = :exp,
                ϵ_init = 1.0,
                warmup_steps = 0,
                decay_steps = 500,
                step = 1,
                is_break_tie = false, 
                #is_training = true,
                seed = 33
            )
        ),
        trajectory = RL.CircularCompactSARTSATrajectory(
            capacity = 1000, 
            state_type = Float32, 
            state_size = state_size,
            action_type = Int,
            action_size = (),
            reward_type = Float32,
            reward_size = (),
            terminal_type = Bool,
            terminal_size = ()
        ),
        role = :DEFAULT_PLAYER
    )

learnedHeuristic = CPRL.LearnedHeuristic(agent)

basicHeuristic = CPRL.BasicHeuristic((x) -> CPRL.minimum(x.domain))

function selectNonObjVariable(model::CPRL.CPModel)
    selectedVar = nothing
    minSize = typemax(Int)
    for (k, x) in model.variables
        if length(x.domain) > 1 && length(x.domain) < minSize# && k != "numberOfColors"
            selectedVar = x
            minSize = length(x.domain)
        end
    end
    # @assert !isnothing(selectedVar)
    return selectedVar
end


function trytrain()
    
    bestsolutions, nodevisited = CPRL.train!(
        learnedHeuristic=learnedHeuristic, 
        problem_type=:filecoloring,
        problem_params=coloring_params,
        nb_episodes=50,
        strategy=CPRL.DFSearch,
        variableHeuristic=selectNonObjVariable
    )
    println(bestsolutions)
    # nodevisited = Array{Any}([35, 51])
    nodevisited = convert(Array{Int}, nodevisited)
    println(nodevisited)

    bestsolutions, nodevisitedbasic = CPRL.train!(
        learnedHeuristic=basicHeuristic, 
        problem_type=:filecoloring,
        problem_params=coloring_params,
        nb_episodes=1,
        strategy=CPRL.DFSearch,
        variableHeuristic=selectNonObjVariable
    )


    linebasic = [convert(Int, nodevisitedbasic[1]) for i in 1:length(nodevisited)]
    linebasic = ones(length(nodevisited))
    linebasic *= nodevisitedbasic[1]


    
    # plot 
    x = 1:length(nodevisited)

    p = plot(x, [nodevisited linebasic], xlabel="Episode", ylabel="Number of nodes visited", ylims = (0,100))
    display(p)
end

