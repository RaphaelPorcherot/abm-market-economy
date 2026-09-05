# =============================================================================
# 1_agents.jl — parameters, agent type, model state
# =============================================================================
# Transcription of Parameters.java, ParametersTest0.java, Agent.java and the
# World interface implemented by VersionB.java.

# =============================================================================
# Parameters
# =============================================================================
# Java splits this across an abstract `Parameters` class with 19 getters and a
# `ParametersTest0` subclass holding the values. In Julia a single immutable
# struct with a keyword constructor does both jobs, and every field is read at
# zero cost because its type is known at compile time.
#
# Java uses `float` (32-bit) throughout except for `priceMomentum`, which is a
# `double`. We use Float64 everywhere: it is the idiomatic and generally faster
# choice on modern hardware, and since we are not reproducing Java's random
# sequence there is nothing to be gained from matching its precision. Results
# are statistically equivalent, not bit-identical.

Base.@kwdef struct Parameters
  # --- population -----------------------------------------------------
  random_seed::Int = 0      # seed of the PopulationFactory
  population_size::Int = 10_000
  n_sector::Int = 20     # number of goods
  n_productions::Int = 15     # sectors in which an agent can produce
  n_needs::Int = 5      # sectors an agent consumes from (disjoint)
  productivity_max::Float64 = 100.0
  need_max::Float64 = 9.0

  # --- version A: tatonnement -----------------------------------------
  va_momentum_gain::Float64 = 1.5
  va_momentum_brake::Float64 = 0.33
  va_max_iterations::Int = 500    # hard-coded `maxIter` in VersionA.java
  va_history_size::Int = 10     # hard-coded, marked TODO PARAMETRISER
  va_tolerance::Float64 = 1e-4   # hard-coded, marked TODO PARAMETRISER
  va_initial_price::Float64 = 100.0  # `Arrays.fill(prices, 100)`

  # --- version B: agent-based -----------------------------------------
  vb_seed::Int = 0
  vb_simulation_duration::Int = 300
  vb_price_sensitivity::Float64 = 0.1    # beta: multiplier on the price step
  vb_gamma::Float64 = 0.33   # braking factor on a reversal
  vb_momentum_gain::Float64 = 0.2    # alpha: systematic reinforcement
  vb_inventory_survival_rate::Float64 = 1.0   # 0 removes the cycles

  sector_review_probability::Float64 = 0.05
  saving_propensity::Float64 = 0.05
  suppliers_list_normal_size::Int = 100
  supplier_turnover_rate::Float64 = 0.20

  # --- constants left hard-coded in Java, surfaced here ----------------
  initial_price_max::Float64 = 200.0    # `200 - random.nextFloat(200)`, marked TODO
  imitation_attempts::Int = 10       # `for (iter = 0; iter < 10; iter++)`, marked TODO
  ricardo_test_draws::Int = 100_000  # testRespectRicardo, diagnostic only
end

"Number of suppliers dropped from the list at the end of a period (Java's `numSuppliersToReject`)."
n_suppliers_to_reject(p::Parameters) =
  floor(Int, p.suppliers_list_normal_size * p.supplier_turnover_rate)

"""
    parameter_list(p) -> Vector{String}

Transcription of `Parameters.getList`, used by `ParametersCsvExporter`. Names
stay in Java's camelCase so the existing .Rmd reports find them.
"""
parameter_list(p::Parameters) = [
  "randomSeed,$(p.random_seed)",
  "populationSize,$(p.population_size)",
  "nSector,$(p.n_sector)",
  "productivityMax,$(p.productivity_max)",
  "needMax,$(p.need_max)",
  "nNeeds,$(p.n_needs)",
  "nProductions,$(p.n_productions)",
  "vAMomentumGain,$(p.va_momentum_gain)",
  "vAMomentumBrake,$(p.va_momentum_brake)",
  "vBAgentPriceSensitivity,$(p.vb_price_sensitivity)",
  "vBAgentMomentumGain,$(p.vb_momentum_gain)",
  "vBAgentGamma,$(p.vb_gamma)",
  "vBInventorySurvivalRate,$(p.vb_inventory_survival_rate)",
  "vBSimulationDuration,$(p.vb_simulation_duration)",
  "vBSeed,$(p.vb_seed)",
  "sectorReviewProbability,$(p.sector_review_probability)",
  "savingPropensity,$(p.saving_propensity)",
  "suppliersListNormalSize,$(p.suppliers_list_normal_size)",
  "supplierTurnoverRate,$(p.supplier_turnover_rate)",
]

function export_parameters(p::Parameters, path::AbstractString)
  mkpath(dirname(path))
  open(path, "w") do io
    println(io, "parameter,value")
    for line in parameter_list(p)
      println(io, line)
    end
  end
  println("✅ Parameters saved:\n", path)
  return path
end

# =============================================================================
# Agent
# =============================================================================

"""
Transcription of Agent.java.

Every field is concretely typed. The per-agent vectors (`needs`,
`productivity`, `inventory`, `consumption_budget`, `suppliers`) are allocated
once at construction and never reallocated: they are written into, never
replaced. Java reallocates `consumptionBudget` on every call to
`consumption()`, which is one `float[nSector]` per agent per period — three
million arrays over a run.

`production_index` uses `0` as the sentinel for Java's `null` (Julia indexing
being 1-based, 0 can never be a valid sector). A `Union{Nothing,Int}` would be
an abstract field type and would poison inference throughout the model.
"""
mutable struct Agent
  # --- agent parameters, fixed at birth --------------------------------
  const needs::Vector{Float64}          # per sector, non-zero for n_needs sectors
  const productivity::Vector{Float64}   # per sector, non-zero for n_productions sectors

  # --- state -----------------------------------------------------------
  production_index::Int                 # 0 = not yet chosen (Java's null)
  const inventory::Vector{Float64}
  const consumption_budget::Vector{Float64}
  money::Float64
  price::Float64
  expected_income::Float64
  price_momentum::Float64               # accumulates the direction of the price search

  # --- supplier list ---------------------------------------------------
  # Java uses a LinkedList<Agent>, whose `contains` and `remove` are O(n) with
  # pointer chasing over 100 elements. A Vector of agent indices with an
  # explicit count does the same job with a contiguous linear scan. The list
  # persists across periods (80 kept, 20 renewed), so it belongs to the agent
  # rather than being a shared scratch buffer.
  const suppliers::Vector{Int}
  n_suppliers::Int
end

function Agent(p::Parameters)
  n = p.n_sector
  Agent(
    zeros(Float64, n),                                # needs
    zeros(Float64, n),                                # productivity
    0,                                                # production_index
    zeros(Float64, n),                                # inventory
    zeros(Float64, n),                                # consumption_budget
    0.0, 0.0, 0.0, 0.0,                               # money, price, expected_income, momentum
    Vector{Int}(undef, p.suppliers_list_normal_size), # suppliers
    0,                                                # n_suppliers
  )
end

@inline productivity(a::Agent) = @inbounds a.productivity[a.production_index]
@inline productivity(a::Agent, i::Int) = @inbounds a.productivity[i]

# =============================================================================
# Model state
# =============================================================================

"""
Transcription of VersionB.java, which implements the `World` interface.

Holds the population, the RNG, the parameters, the collected data and the
scratch buffers.

INVARIANT on the scratch buffers (`active_suppliers`, `best_suppliers`,
`reorder_buffer`). They are shared by all 10,000 agents and are overwritten by
whichever agent is currently trading. That is only safe because agents act
strictly one at a time: nothing inside one agent's `market_actions!` ever
triggers another agent's. Two consequences:

  * an agent's market loop must never call another agent's market loop, directly
    or indirectly — that would corrupt the buffers with no error whatsoever;
  * agents cannot be parallelised within a period. Parallelising whole runs is
    fine (each model owns its buffers); parallelising within a period would need
    one set of buffers per thread, not per agent.
"""
mutable struct ModelB
  const params::Parameters
  const population::Vector{Agent}
  const rng::Xoshiro
  const data::MacroData
  current_period::Int                  # 1-based; Java's currentPeriod + 1

  # --- scratch buffers, allocated once ---------------------------------
  const active_suppliers::Vector{Int}  # insertion-ordered, deduplicated (Java's LinkedHashSet)
  n_active::Int
  const best_suppliers::Vector{Int}    # one agent index per sector, 0 = none
  const reorder_buffer::Vector{Int}    # used to rebuild the supplier list
end

function ModelB(params::Parameters, population::Vector{Agent})
  L = params.suppliers_list_normal_size
  ModelB(
    params,
    population,
    Xoshiro(params.vb_seed),
    MacroData(params.vb_simulation_duration, params.n_sector),
    0,
    Vector{Int}(undef, L), 0,
    zeros(Int, params.n_sector),
    Vector{Int}(undef, L),
  )
end

@inline n_agents(m::ModelB) = length(m.population)

"Transcription of `World.pickRandomAgent`, returning an index rather than a reference."
@inline pick_random_index(m::ModelB) = rand(m.rng, 1:length(m.population))
