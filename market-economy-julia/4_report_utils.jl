# =============================================================================
# 4_report_utils.jl — shared plumbing for the three reports
# =============================================================================
# The R side is four .Rmd files that all repeat the same header: load the long
# CSV, pivot it wide, pick a burn-in, draw a sample of representative sectors,
# and define `export_plot`. That header is factored out here.
#
# Which .Rmd is the reference, established from the git history:
#
#   analyseA.Rmd   (root)  — last touched by dd4fb88, the most recent
#   analyseB.Rmd   (root)  — last touched by dd4fb88, the most recent
#   rmd/analyse*.Rmd       — untouched since the first commit, superseded
#   analyse.Rmd            — the pre-split ancestor of analyseB
#   analyseBA.Rmd          — A/B comparison
#   analyseBAPrices.Rmd    — sibling of analyseBA, same header, diverging tail
#
# Note that the Java wiring was inconsistent: ExperimentB knitted
# rmd/analyseB.Rmd, i.e. the OLDER copy, while ExperimentBA knitted the newer
# root one. The port follows the root versions throughout.

using CairoMakie
using CSV
using DataFrames
using Colors
using Statistics
using Random

# =============================================================================
# Loading
# =============================================================================

"""
    Report

One simulation's output, ready to plot.

`df` is the wide table: one row per (t, sector), one column per `dataType` —
the equivalent of the R

    df %>% filter(!is.na(value)) %>% pivot_wider(names_from = dataType, values_from = value)

Missing cells become `NaN` rather than `missing`: Makie skips NaN in a line the
way ggplot drops NA points, and a `Float64` column keeps the arithmetic
type-stable.
"""
struct Report
    key::String
    df::DataFrame
    params::DataFrame
    n_sector::Int
    sample_sectors::Vector{Int}
    t_lim::Int
end

outputdir() = joinpath(@__DIR__, "output")
figuresdir() = joinpath(@__DIR__, "figures")

"""
    load_report(key; t_lim = 100, n_sample = 9, sample_seed = 0) -> Report

Reads `output/<key>.output.csv` and `output/<key>.parameters.csv`.

One deliberate divergence from the R: the .Rmd files do `set.seed(NULL)` before
sampling the representative sectors, so the nine sectors shown change on every
knit and no two renders of the same data are comparable. Here the draw is
seeded, and `sample_seed = nothing` restores the R behaviour.
"""
function load_report(key::AbstractString; t_lim::Int = 100, n_sample::Int = 9,
                     sample_seed::Union{Int,Nothing} = 0)

    data_file  = joinpath(outputdir(), key * ".output.csv")
    param_file = joinpath(outputdir(), key * ".parameters.csv")

    long   = CSV.read(data_file, DataFrame; missingstring = "NA")
    params = CSV.read(param_file, DataFrame)

    dropmissing!(long, :value)
    wide = unstack(long, [:t, :sector], :dataType, :value)
    sort!(wide, [:t, :sector])

    # missing → NaN, so every measure column is a plain Float64
    for c in names(wide)
        c in ("t", "sector") && continue
        wide[!, c] = coalesce.(wide[!, c], NaN)
    end

    sectors  = sort(unique(wide.sector))
    n_sector = length(sectors)

    rng = sample_seed === nothing ? Random.default_rng() : Xoshiro(sample_seed)
    sample_sectors = sort(randperm(rng, n_sector)[1:min(n_sample, n_sector)] .- 1)

    return Report(key, wide, params, n_sector, sample_sectors, t_lim)
end

"Rows of `r.df` restricted to the nine representative sectors."
sample_rows(r::Report) = r.df[in.(r.df.sector, Ref(Set(r.sample_sectors))), :]

"Rows after the burn-in, i.e. the R `filter(t > tLim)`."
after_burnin(r::Report, df::DataFrame = r.df) = df[df.t .> r.t_lim, :]

# =============================================================================
# Visual identity
# =============================================================================

"""
    sector_colors(n)

ggplot2's default discrete palette (`scales::hue_pal()`): `n` hues evenly spaced
over [15°, 375°) at chroma 100 and luminance 65 in Luv space.
"""
sector_colors(n::Int) = [LCHuv(65.0, 100.0, 15.0 + 360.0 * (i - 1) / n) for i in 1:n]

"""
    gg_axis(fig, pos; kwargs...)

`theme_minimal()`: no panel border, no ticks, light grey grid on both axes.
Every report suppresses the legend (`theme(legend.position = "none")`), which
here simply means never labelling a plot.
"""
function gg_axis(fig, pos = fig[1, 1]; title = "", xlabel = "", ylabel = "", kwargs...)
    Axis(fig[pos...];
        title, xlabel, ylabel,
        titlesize = 13.0, titlefont = :bold, titlealign = :center,
        xgridcolor = RGBf(0.92, 0.92, 0.92), ygridcolor = RGBf(0.92, 0.92, 0.92),
        xgridwidth = 0.8, ygridwidth = 0.8,
        xminorgridvisible = false, yminorgridvisible = false,
        leftspinevisible = false, rightspinevisible = false,
        topspinevisible = false, bottomspinevisible = false,
        xticksvisible = false, yticksvisible = false,
        kwargs...)
end

"A figure sized like the R `export_plot` default: 7 × 5 inches at 72 points per inch."
gg_figure(; width_in = 7, height_in = 5) = Figure(size = (width_in * 72, height_in * 72))

"""
    export_plot(fig, name; png = false)

Transcription of the `export_plot` helper repeated in every .Rmd: a vector PDF
at 7 × 5 inches into `figures/`. The PNG branch is commented out in analyseA
and analyseBA and active in analyseBAPrices; it is a keyword here.
"""
function export_plot(fig, name::AbstractString; png::Bool = false, dpi::Int = 300)
    dir = figuresdir(); mkpath(dir)
    pdf_path = joinpath(dir, name * ".pdf")
    save(pdf_path, fig)
    msg = pdf_path
    if png
        png_path = joinpath(dir, name * ".png")
        save(png_path, fig; px_per_unit = dpi / 72)
        msg *= " and " * png_path
    end
    println("Exported: ", msg)
    return fig
end

# =============================================================================
# Small helpers standing in for dplyr verbs
# =============================================================================

"""
    per_period_total(df, col) -> Vector{Float64}

The R idiom `group_by(t) %>% mutate(total = sum(col, na.rm = TRUE))`: the
period total, broadcast back onto every row of that period.
"""
function per_period_total(df::DataFrame, col::Symbol)
    totals = Dict{Int,Float64}()
    @inbounds for i in 1:nrow(df)
        v = df[i, col]
        isnan(v) && continue
        totals[df.t[i]] = get(totals, df.t[i], 0.0) + v
    end
    return [get(totals, t, 0.0) for t in df.t]
end

"Rows of the last period, one per sector — the R `group_by(sector) %>% filter(t == max(t))`."
last_period(df::DataFrame) = df[df.t .== maximum(df.t), :]

"""
    plot_by_sector!(ax, df, ycol; colors, sectors)

One line per sector, coloured by sector — the `ggplot(aes(t, color = factor(sector))) + geom_line`
that every report repeats. NaNs break the line, as NAs break a ggplot line.
"""
function plot_by_sector!(ax, df::DataFrame, ycol::Symbol;
                         colors = sector_colors(length(unique(df.sector))),
                         sectors = sort(unique(df.sector)), linewidth = 0.5)
    for (k, s) in enumerate(sectors)
        sub = df[df.sector .== s, :]
        isempty(sub) && continue
        lines!(ax, sub.t, sub[!, ycol]; color = colors[mod1(k, length(colors))], linewidth)
    end
    return ax
end

"""
    facet_grid(fig, sectors; ncol = 3) -> Dict(sector => (row, col))

Stands in for `facet_wrap(~ sector)`: a 3 × 3 grid for the nine representative
sectors. Makie has no facetting, so the positions are computed explicitly.
"""
function facet_positions(sectors; ncol::Int = 3)
    Dict(s => (fld(i - 1, ncol) + 1, mod1(i, ncol)) for (i, s) in enumerate(sectors))
end

"""
    lag_by_sector(df, col; k = 1) -> Vector{Float64}

The R `arrange(sector, t) %>% group_by(sector) %>% mutate(lag(col, k))`.
Assumes `df` is already sorted by (t, sector), which `load_report` guarantees.
The first `k` observations of each sector are `NaN`, as they are `NA` in R.
"""
function lag_by_sector(df::DataFrame, col::Symbol; k::Int = 1)
    out = fill(NaN, nrow(df))
    for s in unique(df.sector)
        idx = findall(==(s), df.sector)
        v = df[idx, col]
        @inbounds for i in (k + 1):length(idx)
            out[idx[i]] = v[i - k]
        end
    end
    return out
end

"The symmetric `lead(col, k)`: the last `k` observations of each sector are NaN."
function lead_by_sector(df::DataFrame, col::Symbol; k::Int = 1)
    out = fill(NaN, nrow(df))
    for s in unique(df.sector)
        idx = findall(==(s), df.sector)
        v = df[idx, col]
        @inbounds for i in 1:(length(idx) - k)
            out[idx[i]] = v[i + k]
        end
    end
    return out
end

"""
    facet_figure(sectors; ncol = 3, ...) -> (fig, axes)

Stands in for `facet_wrap(~ sector)`. Makie has no facetting, so the grid is
built explicitly: one `Axis` per sector, three per row, each titled with its
sector number. `axes` maps sector → Axis.

`shared_limits = true` is `scales = "fixed"`, `false` is `scales = "free"`.
"""
function facet_figure(sectors; ncol::Int = 3, title = "", xlabel = "", ylabel = "",
                      width_in = 7, height_in = 8, kwargs...)
    fig = Figure(size = (width_in * 72, height_in * 72))
    isempty(title) || Label(fig[0, 1:ncol], title; fontsize = 13, font = :bold, tellwidth = false)
    axes = Dict{Int,Any}()
    for (i, s) in enumerate(sectors)
        row, col = fld(i - 1, ncol) + 1, mod1(i, ncol)
        ax = Axis(fig[row, col];
            title = "secteur $s", titlesize = 10.0,
            xlabel = row == fld(length(sectors) - 1, ncol) + 1 ? xlabel : "",
            ylabel = col == 1 ? ylabel : "",
            xlabelsize = 10.0, ylabelsize = 10.0,
            xticklabelsize = 8.0, yticklabelsize = 8.0,
            xgridcolor = RGBf(0.92, 0.92, 0.92), ygridcolor = RGBf(0.92, 0.92, 0.92),
            xminorgridvisible = false, yminorgridvisible = false,
            leftspinevisible = false, rightspinevisible = false,
            topspinevisible = false, bottomspinevisible = false,
            xticksvisible = false, yticksvisible = false,
            kwargs...)
        axes[s] = ax
    end
    return fig, axes
end

"Drop the rows where any of `cols` is NaN — the R behaviour when ggplot silently drops NA points."
function drop_nan(df::DataFrame, cols::Vector{Symbol})
    keep = trues(nrow(df))
    for c in cols, i in 1:nrow(df)
        isnan(df[i, c]) && (keep[i] = false)
    end
    return df[keep, :]
end

"Dashed grey reference line at zero, the recurring `geom_hline(yintercept = 0, linetype = \"dashed\")`."
zero_hline!(ax) = hlines!(ax, [0.0]; color = RGBf(0.6, 0.6, 0.6), linestyle = :dash, linewidth = 0.8)
zero_vline!(ax) = vlines!(ax, [0.0]; color = RGBf(0.6, 0.6, 0.6), linestyle = :dash, linewidth = 0.8)

const STEELBLUE = colorant"steelblue"
const FIREBRICK = colorant"firebrick"

"""
    identity_line!(ax, values...)

The `geom_abline(slope = 1, intercept = 0)` that marks perfect agreement
between two quantities. Makie's `ablines!` refuses a log-scaled axis, so the
line is drawn as a segment across the observed range — which on a log axis is
still the straight diagonal, since log(y) = log(x).
"""
function identity_line!(ax, values...)
    all = Float64[]
    for v in values
        append!(all, filter(x -> isfinite(x) && x > 0, v))
    end
    isempty(all) && return ax
    lo, hi = extrema(all)
    lines!(ax, [lo, hi], [lo, hi]; color = :black, linestyle = :dash, linewidth = 0.8)
    return ax
end
