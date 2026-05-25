#==============================================================================
 Script 01 - Carregamento e exploração do sistema IEEE 14 barras
 ------------------------------------------------------------------------------
 Carrega o sistema IEEE 14 barras (com dados dinâmicos) via
 PowerSystemCaseBuilder.jl e inventaria todos os seus componentes:
 barras, linhas, transformadores, geradores (estáticos e dinâmicos) e cargas.

 Os dados são exibidos no terminal e exportados para CSV em data/results/,
 para uso posterior nos demais scripts e no relatório.
==============================================================================#

using PowerSystems
using PowerSystemCaseBuilder
using DataFrames
using CSV

const PSY = PowerSystems

# Diretório de saída (relativo à raiz do projeto)
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULTS_DIR = joinpath(ROOT, "data", "results")
mkpath(RESULTS_DIR)

#------------------------------------------------------------------------------
# 1. Carregar o sistema
#------------------------------------------------------------------------------
println("="^70)
println(" Carregando sistema IEEE 14 barras (PSIDSystems / \"14 Bus Base Case\")")
println("="^70)

sys = build_system(PSIDSystems, "14 Bus Base Case")
set_units_base_system!(sys, "SYSTEM_BASE")

println(sys)

#------------------------------------------------------------------------------
# 2. Inventário de barras
#------------------------------------------------------------------------------
buses = sort(collect(get_components(ACBus, sys)); by = get_number)

df_bus = DataFrame(
    number       = Int[],
    name         = String[],
    bustype      = String[],
    base_voltage = Float64[],   # kV
    vm_pu        = Float64[],   # magnitude de tensão [pu]
    va_rad       = Float64[],   # ângulo [rad]
)
for b in buses
    push!(df_bus, (
        get_number(b),
        get_name(b),
        string(get_bustype(b)),
        get_base_voltage(b),
        get_magnitude(b),
        get_angle(b),
    ))
end
println("\n--- Barras (", nrow(df_bus), ") ---")
show(df_bus, allrows = true); println()
CSV.write(joinpath(RESULTS_DIR, "01_buses.csv"), df_bus)

#------------------------------------------------------------------------------
# 3. Inventário de linhas
#------------------------------------------------------------------------------
lines = collect(get_components(Line, sys))
df_line = DataFrame(
    name = String[], from_bus = Int[], to_bus = Int[],
    r_pu = Float64[], x_pu = Float64[], b_pu = Float64[], rating = Float64[],
)
for l in lines
    arc = get_arc(l)
    push!(df_line, (
        get_name(l),
        get_number(get_from(arc)),
        get_number(get_to(arc)),
        get_r(l), get_x(l), get_b(l).from + get_b(l).to,
        get_rating(l),
    ))
end
println("\n--- Linhas (", nrow(df_line), ") ---")
show(df_line, allrows = true); println()
CSV.write(joinpath(RESULTS_DIR, "01_lines.csv"), df_line)

#------------------------------------------------------------------------------
# 4. Inventário de transformadores (2 enrolamentos e tap)
#------------------------------------------------------------------------------
df_tr = DataFrame(
    name = String[], type = String[], from_bus = Int[], to_bus = Int[],
    r_pu = Float64[], x_pu = Float64[],
)
for T in (Transformer2W, TapTransformer)
    for t in get_components(T, sys)
        arc = get_arc(t)
        push!(df_tr, (
            get_name(t), string(T),
            get_number(get_from(arc)), get_number(get_to(arc)),
            get_r(t), get_x(t),
        ))
    end
end
println("\n--- Transformadores (", nrow(df_tr), ") ---")
show(df_tr, allrows = true); println()
CSV.write(joinpath(RESULTS_DIR, "01_transformers.csv"), df_tr)

#------------------------------------------------------------------------------
# 5. Geradores estáticos (ThermalStandard, RenewableDispatch, Source)
#------------------------------------------------------------------------------
df_gen = DataFrame(
    name = String[], type = String[], bus = Int[],
    P_pu = Float64[], Q_pu = Float64[], rating = Float64[], base_power = Float64[],
)
for G in (ThermalStandard, RenewableDispatch, Source)
    for g in get_components(G, sys)
        push!(df_gen, (
            get_name(g), string(G), get_number(get_bus(g)),
            get_active_power(g), get_reactive_power(g),
            get_rating(g), get_base_power(g),
        ))
    end
end
println("\n--- Geradores estáticos (", nrow(df_gen), ") ---")
show(df_gen, allrows = true); println()
CSV.write(joinpath(RESULTS_DIR, "01_generators.csv"), df_gen)

#------------------------------------------------------------------------------
# 6. Injetores dinâmicos (máquinas síncronas, inversores)
#------------------------------------------------------------------------------
println("\n--- Injetores dinâmicos ---")
dyn = collect(get_components(DynamicInjection, sys))
for d in dyn
    println("  ", get_name(d), "  ::  ", typeof(d))
end
df_dyn = DataFrame(
    name = [get_name(d) for d in dyn],
    type = [string(typeof(d)) for d in dyn],
)
CSV.write(joinpath(RESULTS_DIR, "01_dynamic_injectors.csv"), df_dyn)

#------------------------------------------------------------------------------
# 7. Cargas
#------------------------------------------------------------------------------
# StandardLoad usa modelo ZIP (potência constante + corrente + impedância);
# PowerLoad/ExponentialLoad usam potência constante única.
load_P(ld::StandardLoad) = get_constant_active_power(ld) +
                           get_current_active_power(ld) +
                           get_impedance_active_power(ld)
load_Q(ld::StandardLoad) = get_constant_reactive_power(ld) +
                           get_current_reactive_power(ld) +
                           get_impedance_reactive_power(ld)
load_P(ld) = get_active_power(ld)
load_Q(ld) = get_reactive_power(ld)

df_load = DataFrame(
    name = String[], type = String[], bus = Int[],
    P_pu = Float64[], Q_pu = Float64[],
)
for L in (PowerLoad, StandardLoad, ExponentialLoad)
    for ld in get_components(L, sys)
        push!(df_load, (
            get_name(ld), string(L), get_number(get_bus(ld)),
            load_P(ld), load_Q(ld),
        ))
    end
end
println("\n--- Cargas (", nrow(df_load), ") ---")
show(df_load, allrows = true); println()
CSV.write(joinpath(RESULTS_DIR, "01_loads.csv"), df_load)

#------------------------------------------------------------------------------
# 8. Resumo
#------------------------------------------------------------------------------
println("\n", "="^70)
println(" RESUMO")
println("="^70)
println("  Base de potência do sistema : ", get_base_power(sys), " MVA")
println("  Frequência base             : ", get_frequency(sys), " Hz")
println("  Barras                      : ", nrow(df_bus))
println("  Linhas                      : ", nrow(df_line))
println("  Transformadores             : ", nrow(df_tr))
println("  Geradores estáticos         : ", nrow(df_gen))
println("  Injetores dinâmicos         : ", length(dyn))
println("  Cargas                      : ", nrow(df_load))
println("\n  CSVs exportados em: ", RESULTS_DIR)
println("="^70)
