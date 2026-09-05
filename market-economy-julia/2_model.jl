# =============================================================================
# 2_model.jl — version B, the agent-based model
# =============================================================================
# Transcription of the behavioural methods of Agent.java and of the period loop
# of VersionB.java.
#
# Java's period, for each agent in a freshly shuffled order:
#
#   preMarketActions()   selectProduction, production, calculateConsumptionBudget
#   marketActions()      searchNewSuppliers, performMarketTransactions, updateSuppliersList
#   postMarketActions()  updateProductionPrice
#
# The three phases run as three successive passes over the whole population,
# not interleaved per agent — which matters here, unlike in the profits model,
# because agents trade with each other during the market phase.

# =============================================================================
# Pre-market
# =============================================================================

"""
    select_production!(agent, model)

Transcription of `Agent.selectProduction`.

Three distinct things happen in this one method, which is worth noting because
Java's own comment flags it as odd:

  1. first period only — pick a random sector the agent can actually produce in,
     draw an initial price uniformly in (0, initial_price_max];
  2. every later period — erode the inventory by `inventory_survival_rate`
     (perishable goods). Java's comment calls this "un cheveu sur la soupe":
     stock erosion inside a method meant to choose future production;
  3. with probability `sector_review_probability` — imitate: sample up to
     `imitation_attempts` random agents and switch to the first sector found
     that would yield a higher income at that agent's price. Switching destroys
     the current inventory.
"""
function select_production!(a::Agent, m::ModelB)
  p = m.params
  t = m.current_period
  rng = m.rng
  md = m.data

  if a.production_index == 0
    # First period: a sector the agent can actually produce in.
    while true
      idx = rand(rng, 1:p.n_sector)
      if @inbounds a.productivity[idx] > 0.0
        a.production_index = idx
        a.price = p.initial_price_max * (1.0 - rand(rng))   # in (0, max]
        a.expected_income = a.price * productivity(a)
        break
      end
    end
    return nothing
  end

  pi = a.production_index

  if p.vb_inventory_survival_rate < 1.0
    # Partially or wholly perishable good: part of the past stock is destroyed.
    @inbounds begin
      before = a.inventory[pi]
      a.inventory[pi] = p.vb_inventory_survival_rate * before
      add!(md, t, pi, V_PRODUCT_DESTRUCTION, before - a.inventory[pi])
    end
  end

  rand(rng) < p.sector_review_probability || return nothing

  # Sector review proper.
  a.expected_income = a.price * productivity(a)

  for _ in 1:p.imitation_attempts
    other = @inbounds m.population[pick_random_index(m)]
    new_index = other.production_index
    new_index == pi && continue

    new_income = other.price * productivity(a, new_index)
    new_income > a.expected_income || continue

    # Switch sector: the current inventory is written off.
    @inbounds begin
      add!(md, t, pi, V_PRODUCT_DESTRUCTION, a.inventory[pi])
      a.inventory[pi] = 0.0
    end
    a.production_index = new_index
    a.expected_income = new_income
    a.price = other.price
    a.price_momentum = 0.0
    break
  end
  return nothing
end

"Transcription of `Agent.production`: one period of labour adds `productivity` units of the good."
function production!(a::Agent, m::ModelB)
  t = m.current_period
  md = m.data
  pi = a.production_index

  volume = productivity(a)
  @inbounds a.inventory[pi] += volume

  add!(md, t, pi, V_PRODUCTION_VOLUME, volume)
  add!(md, t, pi, V_PRODUCTION_VALUE, volume * a.price)
  add!(md, t, pi, V_SECTOR_SIZE, 1.0)
  return nothing
end

"""
    consumption!(dest, agent, income)

Transcription of `Agent.consumption(float income)`: the income is split across
sectors in proportion to the agent's needs. Java allocates and returns a fresh
`float[]`; here the caller supplies the destination, which is the agent's own
preallocated `consumption_budget`.
"""
function consumption!(dest::Vector{Float64}, a::Agent, income::Float64)
  total_needs = 0.0
  @inbounds for w in a.needs
    total_needs += w
  end
  if total_needs == 0.0
    fill!(dest, 0.0)          # no declared need, no spending
    return nothing
  end
  @inbounds for i in eachindex(dest)
    dest[i] = income * (a.needs[i] / total_needs)
  end
  return nothing
end

"""
    calculate_consumption_budget!(agent, model)

Transcription of `Agent.calculateConsumptionBudget`.

Note that the budget is `money + expectedIncome - saving`, so it includes income
the agent has not earned yet: money can and does go negative during the market
phase. That is a modelling choice, not an accident.
"""
function calculate_consumption_budget!(a::Agent, m::ModelB)
  saving = a.expected_income * m.params.saving_propensity
  total = max(0.0, a.money + a.expected_income - saving)

  consumption!(a.consumption_budget, a, total)

  t = m.current_period
  @inbounds for i in eachindex(a.consumption_budget)
    add!(m.data, t, i, V_CONSUMPTION_BUDGET, a.consumption_budget[i])
  end
  return nothing
end

"Transcription of `Agent.preMarketActions`."
function pre_market_actions!(a::Agent, m::ModelB)
  select_production!(a, m)
  production!(a, m)
  calculate_consumption_budget!(a, m)
  return nothing
end

# =============================================================================
# Market
# =============================================================================

"Transcription of `Agent.allBudgetsCompleted`."
@inline function all_budgets_completed(a::Agent)
  @inbounds for b in a.consumption_budget
    b > 0.0 && return false
  end
  return true
end

"""
    all_suppliers_exhausted(agent, model)

Transcription of `Agent.allSupplierExhausted`: true when no remaining supplier
holds stock in a sector for which this agent still has budget.
"""
@inline function all_suppliers_exhausted(a::Agent, m::ModelB)
  @inbounds for k in 1:a.n_suppliers
    s = m.population[a.suppliers[k]]
    i = s.production_index
    if s.inventory[i] > 0.0 && a.consumption_budget[i] > 0.0
      return false
    end
  end
  return true
end

"""
    search_new_suppliers!(agent, model)

Transcription of `Agent.searchNewSuppliers`: refill the list up to
`suppliers_list_normal_size` with random agents, excluding self and duplicates.

Java guards this with an attempt counter (`missing * 20`) and throws if it runs
out; the same guard is kept, since exhausting it means the population is too
small for the requested list size and silently looping forever would be worse.
"""
function search_new_suppliers!(a::Agent, m::ModelB, self_index::Int)
  L = m.params.suppliers_list_normal_size
  n = length(m.population)

  L > n - 1 && throw(ArgumentError("supplier list size ($L) exceeds available population ($n)"))

  attempts = 0
  max_attempts = max(1, (L - a.n_suppliers)) * 20

  while a.n_suppliers < L
    attempts += 1
    attempts > max_attempts &&
      throw(ErrorException("too many duplicate draws while filling the supplier list"))

    candidate = pick_random_index(m)
    candidate == self_index && continue

    duplicate = false
    @inbounds for k in 1:a.n_suppliers
      if a.suppliers[k] == candidate
        duplicate = true
        break
      end
    end
    duplicate && continue

    a.n_suppliers += 1
    @inbounds a.suppliers[a.n_suppliers] = candidate
  end
  return nothing
end

"""
    select_best_suppliers!(agent, model)

Transcription of `Agent.selectBestSuppliers`: for each sector, the cheapest
supplier in the list that holds stock in that sector and for which the agent
still has budget. Writes into `model.best_suppliers`, `0` meaning none.
"""
@inline function select_best_suppliers!(a::Agent, m::ModelB)
  best = m.best_suppliers
  fill!(best, 0)
  @inbounds for k in 1:a.n_suppliers
    si = a.suppliers[k]
    s = m.population[si]
    i = s.production_index
    if s.inventory[i] > 0.0 && a.consumption_budget[i] > 0.0
      if best[i] == 0 || s.price < m.population[best[i]].price
        best[i] = si
      end
    end
  end
  return nothing
end

"Remove supplier at position `k` from the agent's list, by shifting left."
@inline function remove_supplier_at!(a::Agent, k::Int)
  @inbounds for j in k:(a.n_suppliers-1)
    a.suppliers[j] = a.suppliers[j+1]
  end
  a.n_suppliers -= 1
  return nothing
end

"Remove supplier by agent index; no-op if absent (Java's `LinkedList.remove(Object)`)."
@inline function remove_supplier!(a::Agent, index::Int)
  @inbounds for k in 1:a.n_suppliers
    if a.suppliers[k] == index
      remove_supplier_at!(a, k)
      return nothing
    end
  end
  return nothing
end

"Append to the active-supplier buffer if absent (Java's `LinkedHashSet.add`)."
@inline function push_active!(m::ModelB, index::Int)
  @inbounds for k in 1:m.n_active
    m.active_suppliers[k] == index && return nothing
  end
  m.n_active += 1
  @inbounds m.active_suppliers[m.n_active] = index
  return nothing
end

"""
    perform_market_transactions!(agent, model)

Transcription of `Agent.performMarketTransactions`.

The loop terminates because every pass that does not break either exhausts a
budget or removes at least one supplier from the list: `all_suppliers_exhausted`
being false guarantees `select_best_suppliers!` finds at least one match, and
each match removes its supplier.
"""
function perform_market_transactions!(a::Agent, m::ModelB)
  t = m.current_period
  md = m.data
  m.n_active = 0

  while true
    all_budgets_completed(a) && break
    all_suppliers_exhausted(a, m) && break

    select_best_suppliers!(a, m)

    @inbounds for i in 1:m.params.n_sector
      si = m.best_suppliers[i]
      (a.consumption_budget[i] > 0.0 && si != 0) || continue

      s = m.population[si]

      offer_value = s.inventory[i] * s.price
      transaction_value = min(offer_value, a.consumption_budget[i])
      transaction_vol = min(s.inventory[i], transaction_value / s.price)

      a.money -= transaction_value
      s.money += transaction_value

      a.consumption_budget[i] -= transaction_value
      s.inventory[i] -= transaction_vol

      push_active!(m, si)
      remove_supplier!(a, si)

      add!(md, t, i, V_CONSUMPTION_VALUE, transaction_value)
      add!(md, t, i, V_CONSUMPTION_VOLUME, transaction_vol)
      add!(md, t, i, V_LABOR_USED, transaction_vol / s.productivity[i])
    end
  end
  return nothing
end

"""
    update_suppliers_list!(agent, model)

Transcription of `Agent.updateSuppliersList`: the suppliers actually traded
with move to the front of the list, the untouched ones follow, and the last
`n_suppliers_to_reject` are dropped so the next period draws fresh ones.

(The `FIXME` left in the Java source — "cette méthode ne fait rien de
reordered" — is stale: `suppliers.clear(); suppliers.addAll(reordered)` does
apply the reordering. The git log shows the bug was fixed and the comment left
behind.)
"""
function update_suppliers_list!(a::Agent, m::ModelB)
  L = m.params.suppliers_list_normal_size
  buf = m.reorder_buffer

  total = m.n_active + a.n_suppliers
  total == L || throw(ErrorException("reordered list size ($total) is not equal to L ($L)"))

  @inbounds for k in 1:m.n_active
    buf[k] = m.active_suppliers[k]
  end
  @inbounds for k in 1:a.n_suppliers
    buf[m.n_active+k] = a.suppliers[k]
  end

  keep = L - n_suppliers_to_reject(m.params)
  @inbounds for k in 1:keep
    a.suppliers[k] = buf[k]
  end
  a.n_suppliers = keep
  return nothing
end

"Transcription of `Agent.marketActions`."
function market_actions!(a::Agent, m::ModelB, self_index::Int)
  search_new_suppliers!(a, m, self_index)
  perform_market_transactions!(a, m)
  update_suppliers_list!(a, m)
  return nothing
end

# =============================================================================
# Post-market
# =============================================================================

"""
    update_production_price!(agent, model)

Transcription of `Agent.updateProductionPrice`.

The price search is a momentum rule: unsold stock pushes the price down,
a sell-out pushes it up. Amplitude accelerates by `momentum_gain` while the
direction holds and is braked by `gamma` on a reversal, then

    price *= exp(price_sensitivity * price_momentum)
"""
function update_production_price!(a::Agent, m::ModelB)
  p = m.params
  t = m.current_period
  md = m.data
  pi = a.production_index

  direction = 0.0
  @inbounds if a.inventory[pi] > 0.0
    direction = -1.0
    add!(md, t, pi, V_UNSOLD_VOLUME, a.inventory[pi])
    add!(md, t, pi, V_UNSOLD_VOLUME_POSITIF, 1.0)
  else
    direction = 1.0
    add!(md, t, pi, V_UNSOLD_VOLUME_POSITIF, 0.0)
    add!(md, t, pi, V_UNSOLD_VOLUME, 0.0)
  end

  amplitude = abs(a.price_momentum)
  reversal = a.price_momentum != 0.0 && sign(a.price_momentum) != direction

  amplitude = reversal ? amplitude * p.vb_gamma : amplitude + p.vb_momentum_gain
  amplitude = max(0.0, amplitude)          # guard against a large negative shock

  a.price_momentum = direction * amplitude
  a.price *= exp(p.vb_price_sensitivity * a.price_momentum)

  add_max!(md, t, pi, a.price)
  add_min!(md, t, pi, a.price)
  return nothing
end

"Transcription of `Agent.postMarketActions`."
post_market_actions!(a::Agent, m::ModelB) = update_production_price!(a, m)

# =============================================================================
# Ricardo diagnostic
# =============================================================================

"""
    respects_ricardo(A, B) -> Union{Bool,Nothing}

Transcription of `Model.respectsRicardo`. `nothing` when both agents produce in
the same sector, which is Java's `null`.
"""
@inline function respects_ricardo(A::Agent, B::Agent)
  ia = A.production_index
  ib = B.production_index
  ia == ib && return nothing
  rA = productivity(A, ia) / productivity(A, ib)
  rB = productivity(B, ia) / productivity(B, ib)
  return rA >= rB
end

"""
    test_respect_ricardo(model) -> ratio

Transcription of `VersionB.testRespectRicardo`: samples random agent pairs and
returns the share respecting comparative advantage.

This is a diagnostic, printed but never recorded in the data. It costs
`ricardo_test_draws` random pairs per period (100,000 by default), so it is
switchable here — Java runs it unconditionally.
"""
function test_respect_ricardo(m::ModelB)
  n = length(m.population)
  r_null = r_pos = r_neg = 0
  for _ in 1:(m.params.ricardo_test_draws-1)
    a = rand(m.rng, 1:n)
    b = rand(m.rng, 1:n)
    a == b && continue
    r = @inbounds respects_ricardo(m.population[a], m.population[b])
    if r === nothing
      r_null += 1
    elseif r
      r_pos += 1
    else
      r_neg += 1
    end
  end
  return r_pos / (r_null + r_pos + r_neg)
end

# =============================================================================
# The period loop
# =============================================================================

"""
    run_version_b!(model; verbose = true, ricardo = true) -> MacroData

Transcription of `VersionB.run`. Three passes over the shuffled population per
period, then the Ricardo diagnostic.

`order` is a permutation of agent indices rather than a shuffle of the
population vector itself: agents refer to each other by index, so permuting the
vector would silently invalidate every supplier list.
"""
function run_version_b!(m::ModelB; verbose::Bool=true, ricardo::Bool=true)
  n = length(m.population)
  order = collect(1:n)
  t0 = time()

  for period in 1:m.params.vb_simulation_duration
    m.current_period = period
    shuffle!(m.rng, order)

    @inbounds for k in 1:n
      pre_market_actions!(m.population[order[k]], m)
    end
    @inbounds for k in 1:n
      i = order[k]
      market_actions!(m.population[i], m, i)
    end
    @inbounds for k in 1:n
      post_market_actions!(m.population[order[k]], m)
    end

    if ricardo
      ratio = test_respect_ricardo(m)
      verbose && @printf("period %4d  ricardo=%.4f  elapsed=%.1fs\n", period - 1, ratio, time() - t0)
    elseif verbose && period % 10 == 0
      @printf("period %4d  elapsed=%.1fs\n", period - 1, time() - t0)
    end
  end

  return m.data
end
