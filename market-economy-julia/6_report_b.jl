# =============================================================================
# 6_report_b.jl — report on version B, the decentralised model
# =============================================================================
# Transcription of analyseB.Rmd (root version, the one last touched by dd4fb88;
# the copy under rmd/ is the older one that ExperimentB was mistakenly wired to).
#
# This is the substantive report: 29 figures across six sections. The commentary
# in the .Rmd is reproduced here, in place, because it carries the analytical
# intent that the plotting code alone does not.
#
# The .Rmd opens with an author's note worth keeping in view:
#
#   « Dans ce fichier, la valeur est calculée du point de vue de la production.
#     Il faudrait refaire l'analyse avec un calcul du point de vue de la
#     consommation (valeurs réalisées). La difficulté, c'est qu'il faudrait
#     comptabiliser la main d'œuvre utilisée pour la production des marchandises
#     vendues. Or on n'a pas cette statistique. Mais elle n'est pas impossible à
#     produire. Y penser. »
#
# — i.e. every "value" below is a value *produced*, not a value *realised*. The
# `laborUsed` series the model already records is precisely the missing
# ingredient for the realised-value version; the BA report starts using it.
#
# One transcription note: the .Rmd reassigns `tLim <- 160` in the middle of the
# file (around the sector-size / price-gap scatter), so every figure after that
# point uses a longer burn-in than the 100 declared in the header. That silent
# switch is made explicit here as `t_lim_late`.

"""
    prices_table_b(r) -> DataFrame

The `prices_df` of analyseB.Rmd, plus the columns the report adds to it as it
goes (`relativePriceGap`, `deltaGap`, `deltaPrice`, `deltaPrice_lag`, the
deflated series).

  * `unitPrice = productionValue / productionVolume` — the average price at
    which the sector's output was valued.
  * `producedValue` shares the period's total production value across sectors in
    proportion to headcount, so `unitValue = producedValue / productionVolume`
    is the labour value per unit.
  * `relativePriceGap = (unitPrice − unitValue) / unitValue` is the deviation of
    price from value; it is the central object of the whole report.
"""
function prices_table_b(r::Report; t_lim_deflator::Int=r.t_lim)
  df = copy(r.df)

  df.totalProductionValue = per_period_total(df, :productionValue)
  df.totalSectorSize = per_period_total(df, :sectorSize)
  df.producedValue = df.totalProductionValue .* df.sectorSize ./ df.totalSectorSize
  df.unitPrice = df.productionValue ./ df.productionVolume
  df.unitValue = df.producedValue ./ df.productionVolume
  df.relativePriceGap = (df.unitPrice .- df.unitValue) ./ df.unitValue

  # First differences by sector, used by the phase-portrait figures.
  df.deltaGap = df.relativePriceGap .- lag_by_sector(df, :relativePriceGap)
  prev_price = lag_by_sector(df, :unitPrice)
  df.deltaPrice = (df.unitPrice .- prev_price) ./ prev_price
  df.deltaPrice_lag = lag_by_sector(df, :deltaPrice)      # k = 1 in the .Rmd

  # Constant prices: deflate by the period's total produced value, taken
  # relative to its level at the burn-in date.
  pv = replace(df.producedValue, NaN => 0.0)
  df.pib_t = per_period_total(DataFrame(t=df.t, producedValue=pv), :producedValue)
  ref_rows = findall(==(t_lim_deflator), df.t)
  pib_ref = isempty(ref_rows) ? 1.0 : df.pib_t[ref_rows[1]]
  df.unitPrice_deflated = df.unitPrice ./ df.pib_t .* pib_ref
  df.unitValue_deflated = df.unitValue ./ df.pib_t .* pib_ref

  return df
end

"""
    unsold_table(r) -> DataFrame

The `unsold_df` of the stock-flow section, plus `unsoldLevel`.

`unsold_reconstructed` rebuilds the end-of-period stock from the previous
stock and the period's physical flows:

    stock(t-1) + production(t) − consumption(t) − destruction(t)

Comparing it with the recorded `unsoldVolume` is a stock-flow consistency check
— exactly the kind of accounting identity that catches a silent modelling error
where no amount of profiling would.
"""
function unsold_table(r::Report)
  df = select(r.df, [:t, :sector, :unsoldVolume, :productionVolume,
    :consumptionVolume, :productDestruction])
  df.unsold_reconstructed = lag_by_sector(df, :unsoldVolume) .+ df.productionVolume .-
                            df.consumptionVolume .- df.productDestruction
  df.unsoldLevel = df.unsoldVolume ./ df.productionVolume
  return df
end

"""
    report_b(key; t_lim = 100, t_lim_late = 160, t0_extinction = 250) -> (Report, Dict)

Transcription of the plotting body of analyseB.Rmd.

analyseB exports none of its figures through `export_plot` — it is an on-screen
exploratory report. `export_figures = true` writes them all to `figures/`
anyway, which is the point of having them in a script rather than a knit.
"""
function report_b(key::AbstractString; t_lim::Int=100, t_lim_late::Int=160,
  t0_extinction::Int=250, export_figures::Bool=false)

  r = load_report(key; t_lim)
  df = r.df
  cols = sector_colors(r.n_sector)
  sect = sort(unique(df.sector))
  samp = r.sample_sectors
  figs = Dict{String,Figure}()

  println("Report B — data source: ", r.key)
  println("  sectors: ", r.n_sector, ", periods: ", maximum(df.t) + 1)
  println("  representative sectors: ", samp)

  # =========================================================================
  # Extinction des secteurs
  # =========================================================================
  # « Il est important de vérifier que la simulation ne conduit pas à la
  #   disparition d'un trop grand nombre de secteurs. »
  # A sector counts as extinct if its headcount is zero at every date after t0.
  late = df[df.t.>t0_extinction, :]
  extinct = [s for s in sect if all(x -> x == 0.0 || isnan(x), late[late.sector.==s, :sectorSize])]
  println("\n## Extinction des secteurs (date limite : ", t0_extinction, ")")
  println("  surviving sectors: ", r.n_sector - length(extinct))
  println("  extinct sectors:   ", length(extinct))
  println("  extinction rate:   ", round(length(extinct) / r.n_sector, digits=4))
  isempty(extinct) || println("  list: ", join(extinct, ", "))

  # =========================================================================
  # Cohérence stock-flux, en volume
  # =========================================================================
  # « Les stocks, à la fin de la période, sont-ils bien égaux (en volume) aux
  #   stocks antérieurs + les flux positifs et négatifs de la période ? »
  ud = unsold_table(r)
  fig, axes = facet_figure(samp; title="Stocks observés et stocks calculés (cohérence des stocks et des flux)",
    xlabel="Temps", ylabel="Volume de stocks")
  for s in samp
    sub = ud[ud.sector.==s, :]
    ax = axes[s]
    lines!(ax, sub.t, sub.unsold_reconstructed; color=STEELBLUE, linewidth=0.7)
    lines!(ax, sub.t, sub.unsoldVolume; color=FIREBRICK, linewidth=0.7, linestyle=:dot)
  end
  Legend(fig[fld(length(samp) - 1, 3)+2, 1:3],
    [LineElement(color=FIREBRICK, linestyle=:dot), LineElement(color=STEELBLUE)],
    ["Stocks observés", "Stocks calculés"];
    orientation=:horizontal, framevisible=false, tellwidth=false)
  figs["stock_flow_consistency"] = fig

  # Numeric version of the same check: the largest relative discrepancy.
  chk = drop_nan(ud, [:unsoldVolume, :unsold_reconstructed])
  if !isempty(chk)
    denom = max.(abs.(chk.unsoldVolume), 1.0)
    println("\n## Cohérence stock-flux")
    println("  max relative discrepancy: ",
      round(maximum(abs.(chk.unsoldVolume .- chk.unsold_reconstructed) ./ denom), sigdigits=3))
  end

  # =========================================================================
  # Dynamiques des secteurs (taille, valeur)
  # =========================================================================
  df.laborShare = 100.0 .* df.sectorSize ./ per_period_total(df, :sectorSize)
  df.productionShare = 100.0 .* df.productionValue ./ per_period_total(df, :productionValue)
  df.budgetShare = 100.0 .* df.consumptionBudget ./ per_period_total(df, :consumptionBudget)

  for (col, title, ylab, name) in (
    (:laborShare, "Taille des secteurs (nombre de producteurs) en part du total", "Taille (%)", "sector_share"),
    (:productionShare, "Part de la production en valeur", "Production (%)", "production_share"),
    (:budgetShare, "Part de la demande en valeur", "Demande (%)", "demand_share"))
    fig = gg_figure()
    ax = gg_axis(fig, (1, 1); title, xlabel="Temps", ylabel=ylab)
    plot_by_sector!(ax, df, col; colors=cols, sectors=sect)
    ylims!(ax, 0, nothing)
    figs[name] = fig
  end

  # Production share against labour share: the 45° line is the locus where a
  # sector's share of value equals its share of labour, i.e. where price = value.
  fig, axes = facet_figure(samp;
    title="Trajectoires production / travail – $(length(samp)) secteurs représentatifs",
    xlabel="Part de la production (%)", ylabel="Part du temps de travail (%)")
  for s in samp
    sub = df[(df.sector.==s).&(df.t.>t_lim), :]
    ax = axes[s]
    lines!(ax, sub.productionShare, sub.laborShare; color=(STEELBLUE, 0.2), linewidth=0.4)
    scatter!(ax, sub.productionShare, sub.laborShare; color=(STEELBLUE, 0.5), markersize=2)
    ablines!(ax, [0.0], [1.0]; color=RGBf(0.5, 0.5, 0.5), linestyle=:dash, linewidth=0.8)
  end
  figs["production_labor_trajectories"] = fig

  # =========================================================================
  # Dynamiques des prix et des valeurs
  # =========================================================================
  pdf_ = prices_table_b(r; t_lim_deflator=t_lim)

  for (col, title, ylab, name) in (
    (:unitPrice, "Prix unitaires", "Prix", "unit_prices"),
    (:unitValue, "Valeurs unitaires", "Valeur", "unit_values"),
    (:unitPrice_deflated, "Prix constants", "Prix (log)", "constant_prices"))
    fig = gg_figure()
    ax = gg_axis(fig, (1, 1); title, xlabel="Temps", ylabel=ylab, yscale=log10)
    plot_by_sector!(ax, drop_nan(pdf_, [col]), col; colors=cols, sectors=sect)
    figs[name] = fig
  end

  # Price and value side by side, per sector, after burn-in.
  fig, axes = facet_figure(samp;
    title="Prix et valeur unitaires – $(length(samp)) secteurs représentatifs, t > $t_lim",
    xlabel="Temps", ylabel="Grandeur unitaire", yscale=log10)
  for s in samp
    sub = drop_nan(pdf_[(pdf_.sector.==s).&(pdf_.t.>t_lim), :], [:unitPrice, :unitValue])
    lines!(axes[s], sub.t, sub.unitValue; color=STEELBLUE, linewidth=0.5)
    lines!(axes[s], sub.t, sub.unitPrice; color=FIREBRICK, linewidth=0.5)
  end
  Legend(fig[fld(length(samp) - 1, 3)+2, 1:3],
    [LineElement(color=STEELBLUE), LineElement(color=FIREBRICK)],
    ["Valeur unitaire", "Prix unitaire"];
    orientation=:horizontal, framevisible=false, tellwidth=false)
  figs["price_value_facets"] = fig

  # =========================================================================
  # Déséquilibre offre / demande
  # =========================================================================
  df.imbalance = 100.0 .* (df.productionValue .- df.consumptionBudget) ./
                 (df.productionValue .+ df.consumptionBudget)

  fig = gg_figure()
  ax = gg_axis(fig, (1, 1); title="Déséquilibre offre / demande par secteur",
    xlabel="Temps", ylabel="(Offre − Demande) / (Offre + demande) (%)")
  plot_by_sector!(ax, df, :imbalance; colors=cols, sectors=sect, linewidth=0.6)
  zero_hline!(ax)
  figs["imbalance_all"] = fig      # « Un écheveau... » — the .Rmd's own verdict

  fig, axes = facet_figure(samp;
    title="Déséquilibre offre / demande – $(length(samp)) secteurs tirés au hasard",
    xlabel="Temps", ylabel="(Offre − Demande) / Consommation")
  for s in samp
    sub = df[(df.sector.==s).&(df.t.>t_lim), :]
    lines!(axes[s], sub.t, sub.imbalance; color=STEELBLUE, linewidth=0.7)
    zero_hline!(axes[s])
  end
  figs["imbalance_facets"] = fig

  fig, axes = facet_figure(samp;
    title="Écart prix / valeur – $(length(samp)) secteurs tirés au hasard",
    xlabel="Temps", ylabel="(Prix − Valeur) / Valeur")
  for s in samp
    sub = pdf_[(pdf_.sector.==s).&(pdf_.t.>t_lim), :]
    lines!(axes[s], sub.t, sub.relativePriceGap; color=STEELBLUE, linewidth=0.7)
    zero_hline!(axes[s])
  end
  figs["price_gap_facets"] = fig

  # Price/value gap against relative sector size — the division-of-labour link.
  fig = gg_figure()
  ax = gg_axis(fig, (1, 1);
    title="Écart prix-valeur en fonction de la taille relative des secteurs",
    xlabel="Part du secteur dans la taille totale (log)",
    ylabel="(Prix - Valeur) / Valeur", xscale=log10)
  for (k, s) in enumerate(samp)
    sub = drop_nan(pdf_[(pdf_.sector.==s).&(pdf_.t.>t_lim), :],
      [:sectorSize, :totalSectorSize, :relativePriceGap])
    scatter!(ax, sub.sectorSize ./ sub.totalSectorSize, sub.relativePriceGap;
      color=(cols[findfirst(==(s), sect)], 0.6), markersize=3)
  end
  zero_hline!(ax)
  figs["gap_vs_relative_size"] = fig

  # =========================================================================
  # Portraits de phase
  # =========================================================================
  # From here the .Rmd silently switches to tLim <- 160.
  #
  # Every per-sector column must exist on `df` BEFORE the slices are taken:
  # `df[df.sector .== s, :]` copies, so a column added afterwards would not
  # reach the slice. (It did not, the first time this ran.)
  df.deltaSectorSize = (df.sectorSize .- lag_by_sector(df, :sectorSize)) ./
                       lag_by_sector(df, :sectorSize)
  df.unsoldRatio = df.unsoldVolumePositif ./ df.sectorSize

  gap_by = Dict(s => pdf_[pdf_.sector.==s, :] for s in samp)
  imb_by = Dict(s => df[df.sector.==s, :] for s in samp)

  fig, axes = facet_figure(samp;
    title="Trajectoires des déséquilibres offre/demande et prix/valeur, t > $t_lim",
    xlabel="Déséquilibre offre/demande (%)", ylabel="Déséquilibre prix/valeur (%)")
  for s in samp
    a = gap_by[s]
    b = imb_by[s]
    m = (a.t .> t_lim)
    lines!(axes[s], b.imbalance[m], a.relativePriceGap[m]; color=(STEELBLUE, 0.2), linewidth=0.4)
    scatter!(axes[s], b.imbalance[m], a.relativePriceGap[m]; color=(STEELBLUE, 0.5), markersize=2)
    zero_hline!(axes[s])
    zero_vline!(axes[s])
  end
  figs["imbalance_gap_trajectories"] = fig

  # Sector growth against the price/value gap: does a sector grow when its
  # price exceeds its value? This is the selection mechanism of the model.
  fig, axes = facet_figure(samp;
    title="Variation de la taille sectorielle et écart prix / valeur, t > $t_lim_late",
    xlabel="Écart relatif prix / valeur", ylabel="Taux de variation de la taille du secteur")
  for s in samp
    a = gap_by[s]
    b = imb_by[s]
    m = (a.t .> t_lim_late)
    sc = drop_nan(DataFrame(x=a.relativePriceGap[m], y=b.deltaSectorSize[m]), [:x, :y])
    scatter!(axes[s], sc.x, sc.y; color=(STEELBLUE, 0.5), markersize=3)
    zero_hline!(axes[s])
    zero_vline!(axes[s])
  end
  figs["size_change_vs_gap"] = fig

  fig, axes = facet_figure(samp;
    title="Déséquilibre offre / demande et variation de l'écart prix / valeur, t > $t_lim_late",
    xlabel="Déséquilibre offre / demande", ylabel="Variation de l'écart prix / valeur")
  for s in samp
    a = gap_by[s]
    b = imb_by[s]
    m = (a.t .> t_lim_late)
    sc = drop_nan(DataFrame(x=b.imbalance[m], y=a.deltaGap[m]), [:x, :y])
    scatter!(axes[s], sc.x, sc.y; color=(STEELBLUE, 0.5), markersize=3)
    zero_hline!(axes[s])
    zero_vline!(axes[s])
  end
  figs["imbalance_vs_delta_gap"] = fig

  fig, axes = facet_figure(samp;
    title="Déséquilibre offre / demande et variation du prix, t > $t_lim_late",
    xlabel="Déséquilibre offre / demande", ylabel="Variation du prix")
  for s in samp
    a = gap_by[s]
    b = imb_by[s]
    m = (a.t .> t_lim_late)
    sc = drop_nan(DataFrame(x=b.imbalance[m], y=a.deltaPrice_lag[m]), [:x, :y])
    scatter!(axes[s], sc.x, sc.y; color=(STEELBLUE, 0.5), markersize=3)
    zero_hline!(axes[s])
    zero_vline!(axes[s])
  end
  figs["imbalance_vs_price_change"] = fig

  # =========================================================================
  # Invendus
  # =========================================================================
  fig = gg_figure()
  ax = gg_axis(fig, (1, 1); title="Niveau des invendus, par secteur",
    xlabel="Temps", ylabel="Niveau des stocks / Production")
  plot_by_sector!(ax, drop_nan(ud, [:unsoldLevel]), :unsoldLevel;
    colors=cols, sectors=sect, linewidth=0.6)
  zero_hline!(ax)
  figs["unsold_level"] = fig

  unsold_by = Dict(s => ud[ud.sector.==s, :] for s in samp)

  fig, axes = facet_figure(samp;
    title="Niveau des stocks et variation du prix, t > $t_lim_late",
    xlabel="Niveau des stocks / Volume de la production", ylabel="Variation du prix")
  for s in samp
    a = gap_by[s]
    u = unsold_by[s]
    m = (a.t .> t_lim_late)
    sc = drop_nan(DataFrame(x=u.unsoldLevel[m], y=a.deltaPrice_lag[m]), [:x, :y])
    scatter!(axes[s], sc.x, sc.y; color=(STEELBLUE, 0.5), markersize=3)
    zero_hline!(axes[s])
    zero_vline!(axes[s])
  end
  figs["unsold_vs_price_change"] = fig

  # Vector field: where does the (stock, price change) pair move next? The
  # .Rmd uses this to read off the direction of rotation of the cycles.
  fig, axes = facet_figure(samp;
    title="Champ de vecteurs prix / stocks, t > $t_lim_late",
    xlabel="Niveau des stocks", ylabel="Variation du prix")
  scale_factor = 0.3
  rotations = Pair{Int,Float64}[]
  for s in samp
    a = gap_by[s]
    u = unsold_by[s]
    m = (a.t .> t_lim_late)
    sc = drop_nan(DataFrame(x=u.unsoldLevel[m], y=a.deltaPrice_lag[m]), [:x, :y])
    nrow(sc) < 3 && continue
    dx = [sc.x[i+1] - sc.x[i] for i in 1:(nrow(sc)-1)]
    dy = [sc.y[i+1] - sc.y[i] for i in 1:(nrow(sc)-1)]
    x0, y0 = sc.x[1:end-1], sc.y[1:end-1]
    for i in eachindex(dx)
      lines!(axes[s], [x0[i], x0[i] + dx[i] * scale_factor],
        [y0[i], y0[i] + dy[i] * scale_factor];
        color=(STEELBLUE, 0.6), linewidth=0.6)
    end
    zero_hline!(axes[s])
    zero_vline!(axes[s])

    # Mean cross product about the centroid: > 0 anticlockwise, < 0 clockwise.
    xc = sc.x .- mean(sc.x)
    yc = sc.y .- mean(sc.y)
    cross = [xc[i] * (yc[i+1] - yc[i]) - yc[i] * (xc[i+1] - xc[i]) for i in 1:(length(xc)-1)]
    push!(rotations, s => mean(cross))
  end
  figs["price_stock_vector_field"] = fig

  println("\n## Sens de rotation (moyenne du produit vectoriel)")
  println("  > 0 : rotation antihoraire, < 0 : rotation horaire")
  for (s, v) in rotations
    println("  secteur ", lpad(s, 2), " : ", round(v, sigdigits=3))
  end

  # Share of agents that failed to clear their output, against the unit price.
  fig, axes = facet_figure(samp; title="Stocks non écoulés et prix unitaires",
    xlabel="Temps", ylabel="Agents en difficulté (%)")
  for s in samp
    sub = df[df.sector.==s, :]
    pr = pdf_[pdf_.sector.==s, :]
    lines!(axes[s], sub.t, 100.0 .* sub.unsoldRatio; color=STEELBLUE, linewidth=0.6)
    # The .Rmd puts the log price on a rescaled secondary axis; Makie has no
    # secondary axis, so the price is rescaled onto the left axis instead and
    # only its shape is meaningful.
    lp = log10.(pr.unitPrice)
    ok = .!isnan.(lp) .& .!isinf.(lp)
    if any(ok)
      lo, hi = extrema(lp[ok])
      yl, yh = extrema(filter(!isnan, 100.0 .* sub.unsoldRatio))
      resc = yl .+ (lp .- lo) ./ (hi - lo) .* (yh - yl)
      lines!(axes[s], pr.t, resc; color=FIREBRICK, linewidth=0.6)
    end
  end
  Legend(fig[fld(length(samp) - 1, 3)+2, 1:3],
    [LineElement(color=STEELBLUE), LineElement(color=FIREBRICK)],
    ["Agents en difficulté (%)", "Prix unitaire (log, rééchelonné)"];
    orientation=:horizontal, framevisible=false, tellwidth=false)
  figs["unsold_count_vs_price"] = fig

  # =========================================================================
  # Prix et division du travail
  # =========================================================================
  # « Le graphique suivant montre l'existence d'une étroite interdépendance
  #   entre la division du travail (taille du secteur, en nombre d'agents) et
  #   prix des marchandises (ici, prix constants). »
  late_p = pdf_[pdf_.t.>t_lim, :]

  fig = gg_figure()
  ax = gg_axis(fig, (1, 1); xlabel="Prix unitaire normalisé", ylabel="Taille du secteur",
    xscale=log10, yscale=log10)
  for (k, s) in enumerate(sect)
    sub = drop_nan(late_p[(late_p.sector.==s).&(late_p.sectorSize.>10), :],
      [:unitPrice_deflated, :sectorSize])
    isempty(sub) && continue
    scatter!(ax, sub.unitPrice_deflated, sub.sectorSize; color=(cols[k], 0.5), markersize=2)
  end
  figs["price_vs_size"] = fig

  fig = gg_figure()
  ax = gg_axis(fig, (1, 1); xlabel="Valeur unitaire déflatée", ylabel="Taille du secteur",
    xscale=log10, yscale=log10)
  for (k, s) in enumerate(sect)
    sub = drop_nan(late_p[late_p.sector.==s, :], [:unitValue_deflated, :sectorSize])
    isempty(sub) && continue
    lines!(ax, sub.unitValue_deflated, sub.sectorSize; color=(cols[k], 0.2), linewidth=0.5)
    scatter!(ax, sub.unitValue_deflated, sub.sectorSize; color=(cols[k], 0.5), markersize=2)
  end
  figs["value_vs_size"] = fig

  fig = gg_figure()
  ax = gg_axis(fig, (1, 1); xlabel="Taille du secteur", ylabel="Écart prix - valeur")
  for s in samp
    sub = drop_nan(late_p[late_p.sector.==s, :], [:sectorSize, :relativePriceGap])
    scatter!(ax, sub.sectorSize, sub.relativePriceGap;
      color=(cols[findfirst(==(s), sect)], 0.5), markersize=2)
  end
  figs["gap_vs_size"] = fig

  # Sector averages after burn-in: the same relation, stripped of the cycles.
  fig = gg_figure()
  ax = gg_axis(fig, (1, 1); xlabel="Taille du secteur", ylabel="Écart prix - valeur")
  for (k, s) in enumerate(sect)
    sub = drop_nan(late_p[late_p.sector.==s, :], [:sectorSize, :relativePriceGap])
    isempty(sub) && continue
    scatter!(ax, [mean(sub.sectorSize)], [mean(sub.relativePriceGap)];
      color=cols[k], markersize=8)
  end
  figs["mean_gap_vs_mean_size"] = fig

  # =========================================================================
  # Prix minimum et maximum
  # =========================================================================
  # `maxPrice` / `minPrice` are the extreme individual prices recorded within
  # the sector that period, so the spread measures price dispersion among
  # producers of the same good — the market's failure to enforce one price.
  fig, axes = facet_figure(samp;
    title="Prix maximum, minimum et moyen – $(length(samp)) secteurs représentatifs",
    xlabel="Temps", ylabel="Prix")
  for s in samp
    sub = pdf_[(pdf_.sector.==s).&(pdf_.t.>t_lim), :]
    lines!(axes[s], sub.t, sub.maxPrice; color=FIREBRICK, linewidth=0.5)
    lines!(axes[s], sub.t, sub.unitPrice; color=STEELBLUE, linewidth=0.5)
    lines!(axes[s], sub.t, sub.minPrice; color=RGBf(0.2, 0.6, 0.3), linewidth=0.5)
  end
  figs["min_max_prices"] = fig

  fig, axes = facet_figure(samp;
    title="Prix maximum, minimum et moyen, en % du prix moyen",
    xlabel="Temps", ylabel="Prix (%)")
  for s in samp
    sub = pdf_[(pdf_.sector.==s).&(pdf_.t.>t_lim), :]
    lines!(axes[s], sub.t, 100.0 .* sub.maxPrice ./ sub.unitPrice; color=FIREBRICK, linewidth=0.5)
    hlines!(axes[s], [100.0]; color=STEELBLUE, linewidth=0.5)
    lines!(axes[s], sub.t, 100.0 .* sub.minPrice ./ sub.unitPrice; color=RGBf(0.2, 0.6, 0.3), linewidth=0.5)
  end
  figs["min_max_prices_relative"] = fig

  # =========================================================================
  # Rendements
  # =========================================================================
  # productionVolume / sectorSize is output per head. Plotted against
  # headcount, it says whether the sector shows increasing or decreasing
  # returns to the division of labour.
  fig, axes = facet_figure(samp; title="Rendements sectoriels, t > $t_lim",
    xlabel="Taille du secteur", ylabel="Productivité")
  for s in samp
    sub = late_p[late_p.sector.==s, :]
    prod = sub.productionVolume ./ sub.sectorSize
    sc = drop_nan(DataFrame(x=sub.sectorSize, y=prod), [:x, :y])
    scatter!(axes[s], sc.x, sc.y; color=(STEELBLUE, 0.5), markersize=3)
  end
  figs["returns_to_scale"] = fig

  if export_figures
    for (name, fig) in figs
      export_plot(fig, "vB_" * name)
    end
  end

  return r, figs
end
