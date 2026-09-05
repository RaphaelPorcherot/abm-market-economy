# =============================================================================
# 3_version_a.jl — version A, the tâtonnement benchmark
# =============================================================================
# Transcription of VersionA.java.
#
# Despite living beside the agent-based model, version A is not an ABM: agents
# never meet. Each iteration every agent picks, with perfect information, the
# sector maximising `productivity[i] * price[i]`; its income is that maximum and
# its demand is that income split across its needs. The aggregate excess demand
# then drives a centralised price update. It is a Walrasian tâtonnement used as
# a reference point for version B.

"""
    ModelA(params)

State of the tâtonnement: current prices, and the speed/direction of each
sector's price search.

`i_history` is a circular buffer of the last `va_history_size` imbalance
readings, used by the stopping rule.
"""
mutable struct ModelA
  const params::Parameters
  const prices::Vector{Float64}
  const speed::Vector{Float64}
  const direction::Vector{Float64}

  # --- scratch buffers, one per sector, reused every iteration ---------
  const sector_size::Vector{Float64}
  const production_value::Vector{Float64}
  const production_volume::Vector{Float64}
  const consumption_value::Vector{Float64}
  const agent_demand::Vector{Float64}

  # --- stagnation criterion -------------------------------------------
  const i_history::Vector{Float64}
  i_index::Int
  i_filled::Int
end

function ModelA(p::Parameters)
  n = p.n_sector
  ModelA(
    p,
    fill(p.va_initial_price, n),
    zeros(n), zeros(n),
    zeros(n), zeros(n), zeros(n), zeros(n), zeros(n),
    zeros(p.va_history_size), 1, 0,
  )
end

"""
    imbalance(demand, supply)

Transcription of `VersionA.imbalance`: sum of absolute gaps over sum of levels,
i.e. a normalised aggregate disequilibrium in [0, 1].
"""
function imbalance(demand::Vector{Float64}, supply::Vector{Float64})
  D = 0.0
  S = 0.0
  @inbounds for i in eachindex(demand)
    D += abs(demand[i] - supply[i])
    S += demand[i] + supply[i]
  end
  return S == 0.0 ? 0.0 : D / S
end

"""
    stagnation!(model, I) -> Bool

Transcription of `VersionA.stagnation`: true once the last `va_history_size`
imbalance readings span less than `va_tolerance`. Returns false until the
buffer has filled.
"""
function stagnation!(m::ModelA, I::Float64)
  h = m.i_history
  @inbounds h[m.i_index] = I
  m.i_index = mod1(m.i_index + 1, length(h))

  if m.i_filled < length(h)
    m.i_filled += 1
    return false
  end

  lo, hi = Inf, -Inf
  @inbounds for v in h
    lo = min(lo, v)
    hi = max(hi, v)
  end
  return (hi - lo) < m.params.va_tolerance
end

"""
    update_price!(model, i, excess_demand)

Transcription of `VersionA.updatePrice`: a sign-following momentum rule. The
speed accelerates by `va_momentum_gain` while the sign of excess demand holds
and is cut by `va_momentum_brake` when it flips.

Note that Java seeds `speed[i]` at 0.1 the first time it is zero, and that the
multiplicative factor is floored at 1e-9 so a price can never go non-positive.
"""
function update_price!(m::ModelA, i::Int, excess_demand::Float64)
  p = m.params
  new_dir = excess_demand > 0.0 ? 1.0 : (excess_demand < 0.0 ? -1.0 : 0.0)

  @inbounds begin
    m.speed[i] == 0.0 && (m.speed[i] = 0.1)

    if new_dir == m.direction[i]
      m.speed[i] *= p.va_momentum_gain
    elseif new_dir != 0.0
      m.speed[i] *= p.va_momentum_brake
    end

    m.direction[i] = new_dir

    factor = 1.0 + m.direction[i] * m.speed[i]
    factor <= 0.0 && (factor = 1e-9)
    m.prices[i] *= factor
  end
  return nothing
end

"""
    run_version_a!(model, population; verbose = true) -> MacroData

Transcription of `VersionA.run`.

Stops on stagnation of the imbalance index, or after `va_max_iterations`.
Because the number of iterations is not known in advance, the macro data array
is sized at the maximum and trimmed to the iterations actually run — which is
the returned value's first dimension.
"""
function run_version_a!(m::ModelA, population::Vector{Agent}; verbose::Bool=true)
  p = m.params
  n = p.n_sector
  md = MacroData(p.va_max_iterations + 1, n)
  iterations_run = 0

  for iter in 1:(p.va_max_iterations+1)
    if iter > p.va_max_iterations
      verbose && println("Max iter reached")
      break
    end
    iterations_run = iter

    fill!(m.sector_size, 0.0)
    fill!(m.production_value, 0.0)
    fill!(m.production_volume, 0.0)
    fill!(m.consumption_value, 0.0)

    for a in population
      # Perfect information: the agent picks the most profitable sector.
      income = -Inf
      best = 0
      @inbounds for i in 1:n
        new_income = a.productivity[i] * m.prices[i]
        if best == 0 || new_income > income
          income = new_income
          best = i
        end
      end

      @inbounds begin
        m.sector_size[best] += 1.0
        m.production_value[best] += income
        m.production_volume[best] += a.productivity[best]
      end

      consumption!(m.agent_demand, a, income)
      @inbounds for i in 1:n
        m.consumption_value[i] += m.agent_demand[i]
      end
    end

    I = imbalance(m.consumption_value, m.production_value)

    @inbounds for i in 1:n
      set!(md, iter, i, V_CONSUMPTION_BUDGET, m.consumption_value[i])
      set!(md, iter, i, V_PRODUCTION_VALUE, m.production_value[i])
      set!(md, iter, i, V_PRODUCTION_VOLUME, m.production_volume[i])
      set!(md, iter, i, V_SECTOR_SIZE, m.sector_size[i])
      set!(md, iter, i, V_PRICE, m.prices[i])
      set!(md, iter, i, V_SPEED, m.speed[i] * m.direction[i])
    end

    verbose && @printf("%04d  I=%.6f\n", iter - 1, I)

    if stagnation!(m, I)
      if verbose
        println("Local convergence detected at iter ", iter - 1)
        println("Final imbalance: ", I)
      end
      break
    end

    @inbounds for i in 1:n
      update_price!(m, i, m.consumption_value[i] - m.production_value[i])
    end
  end

  return MacroData(md.values[1:iterations_run, :, :]), iterations_run
end
