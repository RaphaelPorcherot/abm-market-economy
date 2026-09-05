# =============================================================================
# _main.jl — entry point
# =============================================================================
# Transcription of PopulationFactory.java, Experiment.java, ExperimentA.java,
# ExperimentB.java, ExperimentBA.java and MainA/MainB/MainBA.
#
#   julia --project=. _main.jl
#
# Files 0 to 3 only *define* things; this file is the one that runs them.
#
# What is deliberately NOT ported yet: `Experiment.renderReport` and
# `openHtmlReport`, which shell out to Rscript to knit an .Rmd and open a
# browser. The .Rmd reports are a separate job. This version stops at the CSV
# export, in the same long format Java produces, so the existing reports can
# consume it unchanged.

include("0_utils.jl")      # macro variables, MacroData, CSV export
include("1_agents.jl")     # Parameters, Agent, ModelB
include("2_model.jl")      # version B, the agent-based model
include("3_version_a.jl")  # version A, the tâtonnement benchmark

# The reports are the Julia port of the four .Rmd analyses. They pull in
# CairoMakie, which costs ~20 s of load time, so comment these four lines out
# when you only want to run a simulation.
include("4_report_utils.jl")  # shared: loading, wide format, theme, export
include("5_report_a.jl")      # analyseA.Rmd
include("6_report_b.jl")      # analyseB.Rmd
include("7_report_ba.jl")     # analyseBA.Rmd + analyseBAPrices.Rmd

using Dates

# =============================================================================
# Population
# =============================================================================

"""
    pick_two_disjoint_sets!(productions, needs, n_sector, rng, scratch)

Transcription of `PopulationFactory.pickTwoDisjointSets`: shuffle the sectors
and take the first `n_productions` for production, the next `n_needs` for
consumption. The two sets are disjoint by construction — an agent never
consumes what it can produce, which is what makes exchange necessary.
"""
function pick_two_disjoint_sets!(productions::Vector{Int}, needs::Vector{Int},
  scratch::Vector{Int}, rng)
  shuffle!(rng, scratch)
  n = length(productions)
  @inbounds for i in 1:n
    productions[i] = scratch[i]
  end
  @inbounds for i in 1:length(needs)
    needs[i] = scratch[n+i]
  end
  return nothing
end

"""
    create_population(params) -> Vector{Agent}

Transcription of `PopulationFactory.create`.

Two sector-level ceilings are drawn first — `productivityMax[i]` and
`needMax[i]` — and each agent's own productivity and need in a sector is then a
uniform draw below that ceiling. So sectors differ systematically in how
productive and how wanted they are, and agents differ within each sector.

Java writes `(1 - rng.nextFloat())` to get a draw in (0, 1] rather than [0, 1),
i.e. to exclude zero; `1 - rand(rng)` does the same here.
"""
function create_population(p::Parameters)
  rng = Xoshiro(p.random_seed)
  n = p.n_sector

  productivity_max = [(1.0 - rand(rng)) * p.productivity_max for _ in 1:n]
  need_max = [1.0 + (1.0 - rand(rng)) * p.need_max for _ in 1:n]

  p.n_productions + p.n_needs <= n ||
    throw(ArgumentError("n_productions + n_needs > n_sector"))

  population = Vector{Agent}(undef, p.population_size)
  productions = Vector{Int}(undef, p.n_productions)
  needs = Vector{Int}(undef, p.n_needs)
  scratch = collect(1:n)

  for k in 1:p.population_size
    pick_two_disjoint_sets!(productions, needs, scratch, rng)
    a = Agent(p)
    @inbounds for j in productions
      a.productivity[j] = (1.0 - rand(rng)) * productivity_max[j]
    end
    @inbounds for j in needs
      a.needs[j] = (1.0 - rand(rng)) * need_max[j]
    end
    population[k] = a
  end
  return population
end

# =============================================================================
# Experiments
# =============================================================================

outdir() = joinpath(@__DIR__, "output")

"Java's `DateTimeFormatter.ofPattern(\"YYMMddHHmmss\")` file key."
file_key(suffix::AbstractString) = Dates.format(now(), "yymmddHHMMSS") * suffix

"""
    experiment_a(params = Parameters()) -> (MacroData, key)

Transcription of `ExperimentA.run` (entry point `MainA`).
"""
function experiment_a(params::Parameters=Parameters(); verbose::Bool=true)
  key = file_key("modelA")
  println("ExperimentA-", key)

  population = create_population(params)
  model = ModelA(params)
  t = @elapsed ((data, n_iter) = run_version_a!(model, population; verbose))
  println("VersionA: $n_iter iterations in $(round(t, digits=2)) s")

  export_macro_data(data, joinpath(outdir(), key * ".output.csv"); n_periods=n_iter)
  export_parameters(params, joinpath(outdir(), key * ".parameters.csv"))
  return data, key
end

"""
    experiment_b(params = Parameters()) -> (MacroData, key)

Transcription of `ExperimentB.run` (entry point `MainB`).
"""
function experiment_b(params::Parameters=Parameters(); verbose::Bool=true, ricardo::Bool=true)
  key = file_key("modelB")
  println("ExperimentB-", key)

  population = create_population(params)
  model = ModelB(params, population)
  t = @elapsed run_version_b!(model; verbose, ricardo)
  println("VersionB: $(params.vb_simulation_duration) periods in $(round(t, digits=2)) s")

  export_macro_data(model.data, joinpath(outdir(), key * ".output.csv"))
  export_parameters(params, joinpath(outdir(), key * ".parameters.csv"))
  return model.data, key
end

"""
    experiment_ba(params = Parameters())

Transcription of `ExperimentBA.run` (entry point `MainBA`): both models on the
**same** population, so that the tâtonnement benchmark and the decentralised
outcome are directly comparable.

Note that Java runs A first and B second on that shared population, and that A
mutates nothing on the agents — it only reads `productivity` — so the order is
harmless. B does mutate them, which is why the reverse order would not be
equivalent.
"""
function experiment_ba(params::Parameters=Parameters(); verbose::Bool=true, ricardo::Bool=true)
  start = Dates.format(now(), "yymmddHHMMSS")
  population = create_population(params)

  println("ExperimentBA-", start)

  model_a = ModelA(params)
  data_a, n_iter = run_version_a!(model_a, population; verbose)
  key_a = start * "modelA"
  export_macro_data(data_a, joinpath(outdir(), key_a * ".output.csv"); n_periods=n_iter)
  export_parameters(params, joinpath(outdir(), key_a * ".parameters.csv"))

  model_b = ModelB(params, population)
  run_version_b!(model_b; verbose, ricardo)
  key_b = start * "modelB"
  export_macro_data(model_b.data, joinpath(outdir(), key_b * ".output.csv"))
  export_parameters(params, joinpath(outdir(), key_b * ".parameters.csv"))

  return (a=data_a, b=model_b.data, key_a=key_a, key_b=key_b)
end

# =============================================================================
# Running
# =============================================================================
# Pick one. Java has three separate main classes (MainA, MainB, MainBA); here
# they are three function calls.

# results = experiment_a()
# results = experiment_b()
# results = experiment_ba()

# --- Reports ----------------------------------------------------------------
# Each takes the file key(s) written by the experiment above and returns the
# figures in a Dict, so they can be inspected one by one in the REPL.
#
# r, figs = report_a("260904124926modelA")
# r, figs = report_b("260904124932modelB")
# figs["imbalance_vs_price_change"]
# ra, rb, figs = report_ba("260904124329modelA", "260904124329modelB", export_figures = true)

# figs["price2valueAB"]
# Then `figs["unit_prices"]` to look at one, or pass `export_figures = true` to
# write every figure to figures/ as a PDF.
