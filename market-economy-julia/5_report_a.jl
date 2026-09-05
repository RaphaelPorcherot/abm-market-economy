# =============================================================================
# 5_report_a.jl — report on version A, the tâtonnement
# =============================================================================
# Transcription of analyseA.Rmd (root version, the one last touched by dd4fb88).
#
# The report walks the tâtonnement's convergence: prices, adjustment speeds,
# sector sizes, sectoral and global disequilibria, then two cross-sections at
# the final iteration relating price, size and the price/value gap.
#
# Note that the x axis is labelled "Itérations" and not "Temps": version A has
# no time, only the successive rounds of a centralised price search.

"""
    prices_table(r) -> DataFrame

Transcription of the `prices_df` chunk of analyseA.Rmd.

The economic content is worth spelling out, because the same construction
reappears in the B and BA reports:

  * `producedValue` distributes the period's total production value across
    sectors *in proportion to their headcount* — that is, it is what each
    sector would be worth if one unit of labour produced the same value
    everywhere. This is the labour-value benchmark.
  * `unitValue` is that per unit of output.
  * `gap = (price - unitValue) / unitValue` is therefore the relative deviation
    of the market price from the labour value. `gap = 0` means price equals
    value; the reports plot `(1 + gap) * 100`, i.e. the price/value ratio in
    percent.
"""
function prices_table(r::Report)
    df = copy(r.df)
    df.totalProductionValue = per_period_total(df, :productionValue)
    df.totalSectorSize      = per_period_total(df, :sectorSize)
    df.producedValue        = df.totalProductionValue .* df.sectorSize ./ df.totalSectorSize
    df.unitValue            = df.producedValue ./ df.productionVolume
    df.gap                  = (df.price .- df.unitValue) ./ df.unitValue
    return df
end

"""
    report_a(key; export_figures = true) -> Report

Transcription of the plotting body of analyseA.Rmd. Produces the five exported
figures (`vA_tatonnement_*`) plus the four exploratory ones that the .Rmd draws
without exporting.
"""
function report_a(key::AbstractString; t_lim::Int = 100, export_figures::Bool = true)

    r  = load_report(key; t_lim)                  # tLim <- 100 in analyseA.Rmd
    df = r.df
    cols = sector_colors(r.n_sector)
    sectors = sort(unique(df.sector))

    println("Report A — data source: ", r.key)
    println("  sectors: ", r.n_sector, ", iterations: ", maximum(df.t) + 1)
    println("  representative sectors: ", r.sample_sectors)

    figs = Dict{String,Figure}()

    # --- 1. sectoral unit prices, log scale ------------------------------
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "Itérations", ylabel = "Prix unitaires sectoriels",
                  yscale = log10)
    plot_by_sector!(ax, df, :price; colors = cols, sectors)
    export_figures && export_plot(fig, "vA_tatonnement_prices")
    figs["prices"] = fig

    # --- 2. price adjustment factors -------------------------------------
    # `speed` is signed in the export: VersionA writes speed[i] * direction[i].
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "Itérations", ylabel = "Facteurs d'ajustement des prix")
    plot_by_sector!(ax, df, :speed; colors = cols, sectors)
    export_figures && export_plot(fig, "vA_tatonnement_speed")
    figs["speed"] = fig

    # --- 3. sector headcounts, log scale ---------------------------------
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "Itérations", ylabel = "Effectifs sectoriels",
                  yscale = log10)
    plot_by_sector!(ax, df, :sectorSize; colors = cols, sectors)
    export_figures && export_plot(fig, "vA_tatonnement_sectors")
    figs["sectors"] = fig

    # --- 4. sectoral productivities (representative sectors only) --------
    # Not exported by the .Rmd; kept because it is the only place the report
    # looks at productivity per head.
    sub = sample_rows(r)
    sub.productivity = sub.productionVolume ./ sub.sectorSize
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); title = "Productivités sectorielles",
                  xlabel = "Temps", ylabel = "productionVolume / sectorSize")
    plot_by_sector!(ax, sub, :productivity; colors = cols, sectors = r.sample_sectors)
    figs["productivity"] = fig

    # --- 5. sectoral disequilibria ---------------------------------------
    # 100 * |demand - supply| / (demand + supply), per sector and per iteration.
    df.imbalance_pct = 100.0 .* abs.(df.consumptionBudget .- df.productionValue) ./
                       (df.consumptionBudget .+ df.productionValue)
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "Itérations", ylabel = "Déséquilibres sectoriels (%)")
    plot_by_sector!(ax, df, :imbalance_pct; colors = cols, sectors)
    export_figures && export_plot(fig, "vA_tatonnement_desequilibria")
    figs["desequilibria"] = fig

    # The .Rmd prints the worst sectoral imbalance at iteration 50.
    at50 = df[df.t .== 50, :]
    if !isempty(at50)
        println("  max sectoral imbalance at t = 50: ",
                round(maximum(filter(!isnan, at50.imbalance_pct)), digits = 3), " %")
    end

    # --- 6. global disequilibrium index ----------------------------------
    # Same quantity aggregated: sum of absolute gaps over the sum of levels.
    ts = sort(unique(df.t))
    index = Float64[]
    for t in ts
        sub = df[df.t .== t, :]
        num = sum(abs.(sub.consumptionBudget .- sub.productionValue))
        den = sum(sub.consumptionBudget .+ sub.productionValue)
        push!(index, 100.0 * num / den)
    end
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "Itérations", ylabel = "Indice de déséquilibre global (%)")
    lines!(ax, ts, index; color = :red)
    export_figures && export_plot(fig, "vA_tatonnement_global_desequilibrium")
    figs["global_desequilibrium"] = fig

    i50 = findfirst(==(50), ts)
    i50 === nothing || println("  global imbalance index at t = 50: ",
                               round(index[i50], digits = 3), " %")

    # --- 7. price against sector size at the final iteration -------------
    # The .Rmd clamps the view to x in [30, 400] and y in [150, 1000]; kept, but
    # this is a hand-tuned window and will hide points on other parameter sets.
    lastp = last_period(df)
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "Prix", ylabel = "Taille du secteur",
                  xscale = log10, yscale = log10,
                  limits = ((30, 400), (150, 1000)))
    for (k, s) in enumerate(sectors)
        row = lastp[lastp.sector .== s, :]
        isempty(row) && continue
        scatter!(ax, row.price, row.sectorSize; color = cols[k], markersize = 8)
    end
    figs["price_size"] = fig

    # --- 8 & 9. price/value gap at the final iteration --------------------
    pdf_ = prices_table(r)
    lastp = last_period(pdf_)

    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "productionValue", ylabel = "gap")
    for (k, s) in enumerate(sectors)
        row = lastp[lastp.sector .== s, :]
        isempty(row) && continue
        scatter!(ax, row.productionValue, row.gap; color = cols[k], markersize = 8)
    end
    figs["gap_value"] = fig

    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "Taille du secteur",
                  ylabel = "Rapport Prix / Valeur (%)")
    for (k, s) in enumerate(sectors)
        row = lastp[lastp.sector .== s, :]
        isempty(row) && continue
        scatter!(ax, row.sectorSize, 100.0 .* (1.0 .+ row.gap); color = cols[k], markersize = 8)
    end
    ylims!(ax, 0, nothing)
    figs["gap_size"] = fig

    return r, figs
end
