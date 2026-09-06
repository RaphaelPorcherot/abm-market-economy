# =============================================================================
# 7_report_ba.jl — A/B comparison
# =============================================================================
# Merged transcription of analyseBA.Rmd and analyseBAPrices.Rmd.
#
# Merging them is not a shortcut: the two files share an identical header —
# same loading, same `prices_dfA`, same `prices_dfB`, same `resultB`, same
# price/value scatter — and only diverge at the tail. Keeping them apart would
# duplicate 200 lines to gain the five figures of the BAPrices tail.
#
# The merge also repairs a bug: analyseBA.Rmd has a bare `c` on its own line
# where the export call for the price/value figure should be, so that figure is
# drawn on screen and never written out. analyseBAPrices.Rmd has the correct
# `export_plot(p, "price2valueAB")`. Four figures are exported here, as vector
# PDFs only — analyseBAPrices also writes a PNG, which this port does not:
#
#   price2valueAB   price/value ratio against sector size, A beside B
#   priceSizeAB     price against size, A beside B
#   sizeAB          sector size in A against sector size in B
#   priceAB         unit price in A against unit price in B
#
# The question the whole comparison asks: does the decentralised model (B) land
# where the centralised tâtonnement (A) says it should? A is computed on the
# *same population*, so the two are directly comparable — that is the point of
# ExperimentBA running both on one `create_population` call.

"""
    prices_table_ba_b(r) -> DataFrame

The `prices_dfB` of the BA reports. Richer than the version B report's own
table, because it adds the *realised* value benchmark that analyseB's opening
note says is missing there:

  * `unitPrice  = productionValue / productionVolume`   — price of output produced
  * `unitPrice2 = consumptionValue / consumptionVolume` — price of output actually sold
  * `unitValue` — labour value from the production side, as in the B report
  * `laborEquivalent` shares total consumption value across sectors in
    proportion to `laborUsed`, and `unitLaborEquivalent` is that per unit sold.
    This is the labour value from the *consumption* side, i.e. the realised
    value the analyseB note wished for. `laborUsed` is recorded by the model at
    each transaction as `transactionVolume / supplier.productivity`.

Hence the two gaps:

  * `relativePriceGap  = (unitPrice  − unitValue) / unitValue`
  * `relativePriceGap2 = (unitPrice2 − unitLaborEquivalent) / unitLaborEquivalent`
"""
function prices_table_ba_b(r::Report)
    df = copy(r.df)

    df.totalProductionValue  = per_period_total(df, :productionValue)
    df.totalConsumptionValue = per_period_total(df, :consumptionValue)
    df.totalSectorSize       = per_period_total(df, :sectorSize)
    df.totalLaborUsed        = per_period_total(df, :laborUsed)

    df.unitPrice2           = df.consumptionValue ./ df.consumptionVolume
    df.unitPrice            = df.productionValue ./ df.productionVolume
    df.producedValue        = df.totalProductionValue .* df.sectorSize ./ df.totalSectorSize
    df.unitValue            = df.producedValue ./ df.productionVolume
    df.laborEquivalent      = df.totalConsumptionValue .* df.laborUsed ./ df.totalLaborUsed
    df.unitLaborEquivalent  = df.laborEquivalent ./ df.consumptionVolume

    df.relativePriceGap  = (df.unitPrice  .- df.unitValue) ./ df.unitValue
    df.relativePriceGap2 = (df.unitPrice2 .- df.unitLaborEquivalent) ./ df.unitLaborEquivalent

    return df
end

"""
    report_ba(key_a, key_b; t_lim = 200) -> (Report, Report, Dict)

Transcription of analyseBA.Rmd + analyseBAPrices.Rmd. `key_a` and `key_b` are
the two file keys written by `experiment_ba`, which share a timestamp.

Note the asymmetry, deliberate in the R: version A is read at its **final**
iteration (it converged, so that is its equilibrium), while version B is read
over **every period after the burn-in** (it never settles, so its cloud of
points is the object of interest).
"""
function report_ba(key_a::AbstractString, key_b::AbstractString;
                   t_lim::Int = 200, export_figures::Bool = true)

    ra = load_report(key_a; t_lim)
    rb = load_report(key_b; t_lim)

    dfa = prices_table(ra)              # the version A table, from 5_report_a.jl
    dfb = prices_table_ba_b(rb)

    sect = sort(unique(dfa.sector))
    cols = sector_colors(length(sect))
    figs = Dict{String,Figure}()

    println("Report BA — A: ", ra.key, "   B: ", rb.key)
    println("  burn-in for B: t > ", t_lim)

    # --- deflator ---------------------------------------------------------
    # Version B's price level drifts, so its unit prices are deflated by the
    # period's total produced value, rebased on version A's final total. Only
    # then are the two price scales comparable.
    dfa.pib_t = per_period_total(dfa, :productionValue)
    pv        = replace(dfb.producedValue, NaN => 0.0)
    dfb.pib_t = per_period_total(DataFrame(t = dfb.t, producedValue = pv), :producedValue)

    lastA   = last_period(dfa)
    pib_ref = lastA.pib_t[1]
    dfb.unitPrice_deflated = dfb.unitPrice ./ dfb.pib_t .* pib_ref
    dfb.unitValue_deflated = dfb.unitValue ./ dfb.pib_t .* pib_ref

    lateB = dfb[dfb.t .> t_lim, :]

    # --- 1. price/value ratio against sector size, A beside B -------------
    # A is one point per sector at equilibrium; B is the post-burn-in mean per
    # sector. The dotted line at 100 % is price = value.
    fig = Figure(size = (7 * 72, 5 * 72))
    Label(fig[0, 1:2], "Rapport Prix / Valeur"; fontsize = 13, font = :bold, tellwidth = false)
    axA = gg_axis(fig, (1, 1); title = "vA (équilibre général)",
                  xlabel = "Taille du secteur (nombre d'agents)", ylabel = "Rapport Prix / Valeur (%)")
    axB = gg_axis(fig, (1, 2); title = "vB (dynamiques décentralisées)",
                  xlabel = "Taille du secteur (nombre d'agents)")
    xA = Float64[]; xB = Float64[]
    for (k, s) in enumerate(sect)
        ra_ = lastA[lastA.sector .== s, :]
        if !isempty(ra_) && !isnan(ra_.gap[1])
            scatter!(axA, ra_.sectorSize, 100.0 .* (1.0 .+ ra_.gap); color = cols[k], markersize = 8)
            push!(xA, ra_.sectorSize[1])
        end
        sub = drop_nan(lateB[lateB.sector .== s, :], [:sectorSize, :relativePriceGap])
        if !isempty(sub)
            scatter!(axB, [mean(sub.sectorSize)], [100.0 * (1.0 + mean(sub.relativePriceGap))];
                     color = cols[k], markersize = 8)
            push!(xB, mean(sub.sectorSize))
        end
    end
    for ax in (axA, axB)
        hlines!(ax, [100.0]; color = RGBf(0.4, 0.4, 0.4), linestyle = :dot, linewidth = 0.8)
    end
    isempty(xA) || vlines!(axA, [median(xA)]; color = RGBf(0.4, 0.4, 0.4), linestyle = :dot)
    isempty(xB) || vlines!(axB, [median(xB)]; color = RGBf(0.4, 0.4, 0.4), linestyle = :dot)
    linkyaxes!(axA, axB)
    # PDF only. analyseBAPrices.Rmd also asks for a PNG; that branch is left off.
    export_figures && export_plot(fig, "price2valueAB")
    figs["price2valueAB"] = fig

    # --- 2. price against size, A beside B --------------------------------
    # A gets big opaque points (one per sector), B a faint cloud (every period),
    # exactly as the R sets size 2 / alpha 1 against size 1 / alpha 0.2.
    fig = Figure(size = (7 * 72, 5 * 72))
    axA = gg_axis(fig, (1, 1); title = "vA (équilibre général)",
                  xlabel = "Prix", ylabel = "Taille", xscale = log10, yscale = log10)
    axB = gg_axis(fig, (1, 2); title = "vB (dynamiques décentralisées)",
                  xlabel = "Prix", xscale = log10, yscale = log10)
    for (k, s) in enumerate(sect)
        a = drop_nan(lastA[lastA.sector .== s, :], [:price, :sectorSize])
        isempty(a) || scatter!(axA, a.price, a.sectorSize; color = cols[k], markersize = 6)
        b = drop_nan(lateB[lateB.sector .== s, :], [:unitPrice_deflated, :sectorSize])
        isempty(b) || scatter!(axB, b.unitPrice_deflated, b.sectorSize;
                               color = (cols[k], 0.2), markersize = 3)
    end
    linkaxes!(axA, axB)
    export_figures && export_plot(fig, "priceSizeAB")
    figs["priceSizeAB"] = fig

    # --- 3. sector size, A against B --------------------------------------
    # The dashed 45° line is the locus of perfect agreement between the two
    # models. Distance from it measures how far decentralisation moves the
    # division of labour away from its equilibrium allocation.
    sizeA = Dict(row.sector => row.sectorSize for row in eachrow(lastA))
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "vA (équilibre général)",
                  ylabel = "vB (dynamique décentralisée)", xscale = log10, yscale = log10)
    allx = Float64[]; ally = Float64[]
    for (k, s) in enumerate(sect)
        haskey(sizeA, s) || continue
        sub = drop_nan(lateB[lateB.sector .== s, :], [:sectorSize])
        isempty(sub) && continue
        scatter!(ax, fill(sizeA[s], nrow(sub)), sub.sectorSize;
                 color = (cols[k], 0.1), markersize = 3)
        push!(allx, sizeA[s]); append!(ally, sub.sectorSize)
    end
    identity_line!(ax, allx, ally)
    export_figures && export_plot(fig, "sizeAB")
    figs["sizeAB"] = fig

    # --- 4. unit price, A against B ---------------------------------------
    priceA = Dict(row.sector => row.price for row in eachrow(lastA))
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); xlabel = "vA (équilibre général)",
                  ylabel = "vB (dynamiques décentralisées)", xscale = log10, yscale = log10)
    allx = Float64[]; ally = Float64[]
    for (k, s) in enumerate(sect)
        haskey(priceA, s) || continue
        sub = drop_nan(lateB[lateB.sector .== s, :], [:unitPrice_deflated])
        isempty(sub) && continue
        scatter!(ax, fill(priceA[s], nrow(sub)), sub.unitPrice_deflated;
                 color = (cols[k], 0.1), markersize = 3)
        push!(allx, priceA[s]); append!(ally, sub.unitPrice_deflated)
    end
    identity_line!(ax, allx, ally)
    export_figures && export_plot(fig, "priceAB")
    figs["priceAB"] = fig

    # --- 5. version B unit prices over time (from analyseBAPrices) --------
    fig = gg_figure()
    ax  = gg_axis(fig, (1, 1); title = "Prix unitaires", xlabel = "Temps", ylabel = "Prix",
                  yscale = log10)
    plot_by_sector!(ax, drop_nan(dfb, [:unitPrice]), :unitPrice; colors = cols, sectors = sect)
    figs["vB_unit_prices"] = fig

    # --- 6 to 9. the two price measures and the two value measures ---------
    # The tail of analyseBAPrices.Rmd, on `wide_sample <- prices_dfB %>%
    # filter(sector %in% sample_sectors) %>% filter(t > tLim)`.
    #
    # This is where the realised-value benchmark earns its keep: the report
    # puts the produced and the sold side of each pair next to each other, so
    # the ratio plots read directly as "how far does what was sold diverge
    # from what was made".
    #
    # One correction to the .Rmd: its legend labels the *production*-side
    # series `unitValue` as « marchandises consommées » and the
    # *consumption*-side `unitLaborEquivalent` as « marchandises produites ».
    # The two are swapped there; they are labelled by their actual definition
    # here.
    samp = rb.sample_sectors
    ws = lateB[in.(lateB.sector, Ref(Set(samp))), :]

    function facet_pair(a::Symbol, b::Symbol, la, lb, title; logscale = false)
        fig, axes = facet_figure(samp; title, xlabel = "Temps", ylabel = "Grandeur unitaire",
                                 (logscale ? (; yscale = log10) : (;))...)
        for s in samp
            sub = drop_nan(ws[ws.sector .== s, :], [a, b])
            isempty(sub) && continue
            lines!(axes[s], sub.t, sub[!, a]; color = STEELBLUE, linewidth = 0.5)
            lines!(axes[s], sub.t, sub[!, b]; color = FIREBRICK, linewidth = 0.5)
        end
        # `nbanks = 2` puts one entry per row: these labels are long enough to
        # run off a 7-inch figure side by side.
        Legend(fig[fld(length(samp) - 1, 3) + 2, 1:3],
               [LineElement(color = STEELBLUE), LineElement(color = FIREBRICK)], [la, lb];
               orientation = :horizontal, nbanks = 2, framevisible = false,
               tellwidth = false, labelsize = 10)
        return fig
    end

    function facet_ratio(num::Symbol, den::Symbol, title, ylabel)
        fig, axes = facet_figure(samp; title, xlabel = "Temps", ylabel)
        for s in samp
            sub = drop_nan(ws[ws.sector .== s, :], [num, den])
            isempty(sub) && continue
            lines!(axes[s], sub.t, sub[!, num] ./ sub[!, den]; color = STEELBLUE, linewidth = 0.5)
        end
        return fig
    end

    n = length(samp)
    figs["price_production_vs_consumption"] = facet_pair(:unitPrice, :unitPrice2,
        "Prix à la production", "Prix à la consommation",
        "Prix et valeur unitaires – $n secteurs représentatifs, t > $t_lim"; logscale = true)

    figs["price_ratio"] = facet_ratio(:unitPrice2, :unitPrice,
        "Prix unitaires – $n secteurs représentatifs, t > $t_lim",
        "Prix à la consommation / prix à la production")

    figs["two_value_measures"] = facet_pair(:unitValue, :unitLaborEquivalent,
        "Valeur unitaire des marchandises produites",
        "Valeur unitaire des marchandises consommées",
        "2 calculs des valeurs unitaires – $n secteurs représentatifs, t > $t_lim"; logscale = true)

    figs["value_ratio"] = facet_ratio(:unitLaborEquivalent, :unitValue,
        "Deux mesures de la valeur – $n secteurs représentatifs, t > $t_lim",
        "Valeur consommée / valeur produite")

    # --- summary table -----------------------------------------------------
    println("\n  sector   sizeA     sizeB    priceA   priceB(def)   gapA%    gapB%    gapB2%")
    for s in sect
        sub = drop_nan(lateB[lateB.sector .== s, :],
                       [:sectorSize, :unitPrice_deflated, :relativePriceGap])
        a = lastA[lastA.sector .== s, :]
        (isempty(sub) || isempty(a)) && continue
        g2 = filter(!isnan, sub.relativePriceGap2)
        println("  ", lpad(s, 5), lpad(round(Int, a.sectorSize[1]), 9),
                lpad(round(Int, mean(sub.sectorSize)), 10),
                lpad(round(a.price[1], digits = 1), 10),
                lpad(round(mean(sub.unitPrice_deflated), digits = 1), 13),
                lpad(round(100 * (1 + a.gap[1]), digits = 1), 9),
                lpad(round(100 * (1 + mean(sub.relativePriceGap)), digits = 1), 9),
                lpad(isempty(g2) ? "—" : string(round(100 * (1 + mean(g2)), digits = 1)), 9))
    end

    return ra, rb, figs
end
