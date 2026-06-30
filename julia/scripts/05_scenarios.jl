#==============================================================================
 Script 05 - Cenários de carga e geração x curto-circuito na barra 7
 ------------------------------------------------------------------------------
 Explora como variações de carga e de geração afetam o curto-circuito trifásico
 franco na barra 7. Para cada cenário: ajusta carga/geração, resolve o fluxo de
 potência (PowerFlows.jl) e recalcula o curto pelo método Zbus (SCUtils).

 Cenários:
   1. Base                  - caso original
   2. Carga leve (60%)      - demanda reduzida
   3. Carga pesada (140%)   - demanda elevada
   4. Gerador b2 fora       - uma unidade síncrona fora de serviço

 Métricas: corrente de falta, impedância de Thévenin, potência de curto (SCC),
 tensão pré-falta na barra 7 e perfil de tensões durante a falta.
==============================================================================#

using PowerSystems
using DataFrames
using CSV
using Plots
using Printf

include(joinpath(@__DIR__, "..", "src", "SCUtils.jl"))
using .SCUtils

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULTS_DIR = joinpath(ROOT, "data", "results")
const FIG_DIR = joinpath(ROOT, "data", "figures")
mkpath(RESULTS_DIR)
mkpath(FIG_DIR)
gr()

const FAULT_BUS = 7

# Define cada cenário como (nome, fator_carga, barra_geração_fora|nothing)
scenarios = [
    ("Base", 1.0, nothing),
    ("Carga leve (60%)", 0.6, nothing),
    ("Carga pesada (140%)", 1.4, nothing),
    ("Gerador b2 fora", 1.0, 2),
]

println("="^70)
println(" Cenários de carga/geração - curto franco na barra ", FAULT_BUS)
println("="^70)

results = DataFrame(
    cenario = String[], carga_total_MW = Float64[],
    V7_pre_pu = Float64[], Zth_abs_pu = Float64[],
    If_pu = Float64[], If_kA = Float64[], SCC_MVA = Float64[],
    If_cargas_pu = Float64[], If_cargas_kA = Float64[],
)
vprofiles = Dict{String, Vector{Float64}}()
bus_order_ref = Int[]

for (name, load_factor, gen_off) in scenarios
    sys = build_14bus()
    scale_loads!(sys, load_factor)
    gen_off !== nothing && take_generator_offline!(sys, gen_off)
    solve_pf!(sys)

    # Carga total (MW) do cenário
    Ptot = sum(first(load_PQ(ld)) for ld in get_components(StandardLoad, sys)) *
           get_base_power(sys)

    r  = zbus_short_circuit(sys; fault_bus = FAULT_BUS, include_loads = false)
    rL = zbus_short_circuit(sys; fault_bus = FAULT_BUS, include_loads = true)

    push!(results, (
        name, Ptot,
        abs(r.Vpre[r.idx_of[FAULT_BUS]]), abs(r.Zth),
        abs(r.If), abs(r.If) * r.Ibase_kA, r.scc_mva,
        abs(rL.If), abs(rL.If) * rL.Ibase_kA,
    ))
    vprofiles[name] = abs.(r.Vpos)
    global bus_order_ref = r.bus_order

    @printf("\n  %-22s carga=%.1f MW | If=%.3f pu (%.2f kA) | Zth=%.4f | SCC=%.1f MVA\n",
            name, Ptot, abs(r.If), abs(r.If) * r.Ibase_kA, abs(r.Zth), r.scc_mva)
end

#------------------------------------------------------------------------------
# Tabela de resultados
#------------------------------------------------------------------------------
println("\n", "="^70)
println(" RESUMO DOS CENÁRIOS")
println("="^70)
show(results, allrows = true, allcols = true)
println()
CSV.write(joinpath(RESULTS_DIR, "05_scenarios_summary.csv"), results)

#------------------------------------------------------------------------------
# Gráfico 1: corrente de falta por cenário (barras)
#------------------------------------------------------------------------------
# Eixo Y ampliado (zoom) para evidenciar as pequenas diferenças entre cenários
# (variam ~4%, de 26,8 a 27,9 kA). O título avisa que o eixo NÃO começa em zero.
ymin = floor(minimum(results.If_kA) - 0.5)
ymax = ceil(maximum(results.If_kA) + 0.5)
p1 = bar(results.cenario, results.If_kA;
         ylabel = "Corrente de falta [kA]", legend = false,
         title = "Corrente de curto na barra $FAULT_BUS por cenário (eixo ampliado)",
         xrotation = 20, lw = 0, fillcolor = :steelblue, ylims = (ymin, ymax))
for (i, v) in enumerate(results.If_kA)
    annotate!(p1, i, v + 0.12, text(@sprintf("%.2f", v), 8))
end
savefig(p1, joinpath(FIG_DIR, "05_corrente_por_cenario.png"))

#------------------------------------------------------------------------------
# Gráfico 2: perfil de tensões durante a falta por cenário
#------------------------------------------------------------------------------
p2 = plot(; xlabel = "Barra", ylabel = "Tensão durante a falta [pu]",
          title = "Perfil de tensões durante curto na barra $FAULT_BUS",
          legend = :bottomright, xticks = bus_order_ref)
for (name, _, _) in scenarios
    plot!(p2, bus_order_ref, vprofiles[name]; label = name, lw = 1.8, marker = :circle, ms = 3)
end
savefig(p2, joinpath(FIG_DIR, "05_perfil_tensoes_cenarios.png"))

println("\n Figuras: 05_corrente_por_cenario.png, 05_perfil_tensoes_cenarios.png")
println(" Tabela:  05_scenarios_summary.csv")
println("="^70)
