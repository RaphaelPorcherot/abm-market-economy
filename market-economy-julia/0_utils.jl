# =============================================================================
# 0_utils.jl — packages, macro data collection, CSV export
# =============================================================================
# Transcription of MacroVariable.java, MacroKey.java, MacroData.java and
# MacroDataCsvExporter.java.
#
# Nothing plotting-related is loaded here: the model must stay cheap to start.

using Random
using Printf

# =============================================================================
# Macro variables
# =============================================================================
# Same names and same order as the Java enum, so that the exported CSV can be
# read by the existing .Rmd reports without any lookup table.

const MACRO_VARS = [
    :consumptionBudget,
    :consumptionValue,
    :consumptionVolume,
    :productionValue,
    :productionVolume,
    :sectorSize,
    :unsoldVolume,
    :unsoldVolumePositif,
    :productDestruction,
    :price,
    :maxPrice,
    :minPrice,
    :speed,
    :laborUsed,
]

# Column index of each variable, resolved once at load time so that the hot
# loops index into a matrix with an `Int` rather than looking up a symbol.
const V_CONSUMPTION_BUDGET   = 1
const V_CONSUMPTION_VALUE    = 2
const V_CONSUMPTION_VOLUME   = 3
const V_PRODUCTION_VALUE     = 4
const V_PRODUCTION_VOLUME    = 5
const V_SECTOR_SIZE          = 6
const V_UNSOLD_VOLUME        = 7
const V_UNSOLD_VOLUME_POSITIF = 8
const V_PRODUCT_DESTRUCTION  = 9
const V_PRICE                = 10
const V_MAX_PRICE            = 11
const V_MIN_PRICE            = 12
const V_SPEED                = 13
const V_LABOR_USED           = 14

const N_MACRO_VARS = length(MACRO_VARS)

# =============================================================================
# Macro data
# =============================================================================

"""
    MacroData(n_periods, n_sector)

Holds every period's macro aggregates in a single preallocated
`n_periods × n_sector × n_variable` array.

Java allocates a fresh `MacroData` object per period, then dumps it into a
`HashMap<MacroKey, Float>` keyed by a record — one boxed Float and one record
per (period, sector, variable) triple, i.e. 300 × 20 × 14 = 84,000 heap objects.
A dense array of the same shape is 84,000 Float64 in one contiguous block.

Cells start at `NaN`, exactly like Java's `initNaN`, and NaN is what
distinguishes "never touched" from "touched, value zero" — the CSV exporter
writes `NA` for the former.
"""
struct MacroData
    values::Array{Float64,3}   # [period, sector, variable]
end

MacroData(n_periods::Int, n_sector::Int) =
    MacroData(fill(NaN, n_periods, n_sector, N_MACRO_VARS))

"""
    add!(md, t, sector, var, value)

Transcription of `MacroData.addValue`: accumulates, treating `NaN` as the
neutral element (Java's `add(base, valeur)` helper). `t` is 1-based here and
converted back to Java's 0-based period only at export time.
"""
@inline function add!(md::MacroData, t::Int, sector::Int, var::Int, value::Float64)
    @inbounds begin
        base = md.values[t, sector, var]
        md.values[t, sector, var] = isnan(base) ? value : base + value
    end
    return nothing
end

"Transcription of `MacroData.setValue`: overwrite rather than accumulate."
@inline function set!(md::MacroData, t::Int, sector::Int, var::Int, value::Float64)
    @inbounds md.values[t, sector, var] = value
    return nothing
end

"""
    add_max!(md, t, sector, value)

The `MAX_PRICE` branch of `MacroData.addValue`: a running maximum, not a sum.
"""
@inline function add_max!(md::MacroData, t::Int, sector::Int, value::Float64)
    @inbounds begin
        cur = md.values[t, sector, V_MAX_PRICE]
        if isnan(cur) || value > cur
            md.values[t, sector, V_MAX_PRICE] = value
        end
    end
    return nothing
end

"The `MIN_PRICE` branch: a running minimum."
@inline function add_min!(md::MacroData, t::Int, sector::Int, value::Float64)
    @inbounds begin
        cur = md.values[t, sector, V_MIN_PRICE]
        if isnan(cur) || value < cur
            md.values[t, sector, V_MIN_PRICE] = value
        end
    end
    return nothing
end

# =============================================================================
# CSV export
# =============================================================================

"""
    export_macro_data(md, path; n_periods)

Transcription of `MacroDataCsvExporter.export`. Same header, same sort order
(period → sector → variable) and same `NA` for missing values, so that the
existing .Rmd reports read the file unchanged.

Note that Java sorts by `variable().name()`, i.e. by the ENUM CONSTANT name
(`CONSUMPTION_BUDGET`, `LABOR_USED`, …), not by the csv name. The order below
reproduces that.
"""
function export_macro_data(md::MacroData, path::AbstractString; n_periods::Int = size(md.values, 1))
    mkpath(dirname(path))
    n_sector = size(md.values, 2)

    # Java's sort key is the enum constant name; precompute that ordering once.
    enum_names = ["CONSUMPTION_BUDGET", "CONSUMPTION_VALUE", "CONSUMPTION_VOLUME",
                  "PRODUCTION_VALUE", "PRODUCTION_VOLUME", "SECTOR_SIZE",
                  "UNSOLD_VOLUME", "UNSOLD_VOLUME_POSITIF", "PRODUCT_DESTRUCTION",
                  "PRICE", "MAX_PRICE", "MIN_PRICE", "SPEED", "LABOR_USED"]
    order = sortperm(enum_names)

    open(path, "w") do io
        println(io, "t,sector,dataType,value")
        for t in 1:n_periods, s in 1:n_sector, v in order
            x = @inbounds md.values[t, s, v]
            # Java writes 0-based periods and sectors.
            print(io, t - 1, ',', s - 1, ',', MACRO_VARS[v], ',')
            println(io, isnan(x) ? "NA" : string(x))
        end
    end
    println("✅ Data saved:\n", path)
    return path
end
