#==============================================================================
 Script 03 - Curto-circuito trifásico franco na barra 7 (método Zbus)
 ------------------------------------------------------------------------------
 Calcula, a partir da matriz de admitâncias nodal, a corrente de curto-circuito
 e as tensões em todas as barras para uma falta trifásica franca na barra 7,
 usando o método da matriz de impedâncias (Zbus) e o princípio da superposição.

 Modelagem:
   - Ybus da rede (linhas + transformadores + shunts) -> script 02
   - Acrescenta-se a reatância subtransitória X"d de cada gerador como
     admitância shunt para a terra na barra do gerador (modelo clássico de
     curto-circuito).
   - Tensões pré-falta = solução do fluxo de potência do caso base.

 Falta franca (bolted) na barra f=7:
     I_falta  = V_pf[f] / Z[f,f]
     V_pos[i] = V_pf[i] - (Z[i,f]/Z[f,f]) * V_pf[f]
==============================================================================#

using PowerSystems
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using LinearAlgebra
using DataFrames
using CSV
using Printf
import Logging

const PSY = PowerSystems
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULTS_DIR = joinpath(ROOT, "data", "results")
mkpath(RESULTS_DIR)

const FAULT_BUS = 7
const Z_FAULT   = 0.0 + 0.0im   # falta franca (impedância de falta nula)

#------------------------------------------------------------------------------
# 1. Sistema, Ybus da rede e índices
#------------------------------------------------------------------------------
println("="^70)
println(" Curto-circuito trifásico franco na barra ", FAULT_BUS, " (método Zbus)")
println("="^70)

# Suprime warnings de validação de range do caso (conhecidos e inofensivos)
sys = Logging.with_logger(Logging.NullLogger()) do
    build_system(PSIDSystems, "14 Bus Base Case")
end
set_units_base_system!(sys, "SYSTEM_BASE")
S_base = get_base_power(sys)

# Ybus PURA da rede (cargas adicionadas só na variante B), para que o modelo
# "geradores apenas" não inclua implicitamente a impedância das cargas ZIP.
ybus = Ybus(sys; include_constant_impedance_loads = false)
Y_net = Matrix(ybus.data)
bus_order = collect(ybus.axes[1])
n = size(Y_net, 1)
idx_of = Dict(b => i for (i, b) in enumerate(bus_order))   # nº barra -> índice
f = idx_of[FAULT_BUS]

buses = Dict(get_number(b) => b for b in get_components(ACBus, sys))

#------------------------------------------------------------------------------
# 2. Tensões pré-falta (solução do fluxo de potência do caso base)
#------------------------------------------------------------------------------
V_pf = ComplexF64[]
for b in bus_order
    bus = buses[b]
    push!(V_pf, get_magnitude(bus) * cis(get_angle(bus)))   # cis(x)=exp(ix)
end

#------------------------------------------------------------------------------
# 3. Reatância subtransitória dos geradores -> admitância shunt p/ a terra
#------------------------------------------------------------------------------
gen_shunt = zeros(ComplexF64, n)
println("\n--- Reatâncias subtransitórias dos geradores ---")
println(rpad("gerador", 16), rpad("barra", 7), rpad("X\"d(dev)", 12),
        rpad("Sbase", 9), rpad("X\"d(sys)", 12))
# A reatância está na máquina (injetor dinâmico), referida à base do dispositivo;
# a barra vem do gerador estático (ThermalStandard) que o hospeda.
for sg in get_components(ThermalStandard, sys)
    dyn = get_dynamic_injector(sg)
    dyn === nothing && continue
    bus_num = get_number(get_bus(sg))
    mach    = get_machine(dyn)
    Xpp     = get_Xd_pp(mach)
    R       = get_R(mach)
    Sdev    = get_base_power(dyn)
    z_sys   = (R + im * Xpp) * (S_base / Sdev)     # converte p/ base do sistema
    gen_shunt[idx_of[bus_num]] += 1 / z_sys
    @printf("%-16s%-7d%-12.5f%-9.1f%-12.5f\n",
            get_name(sg), bus_num, Xpp, Sdev, imag(z_sys))
end

#------------------------------------------------------------------------------
# 4. Cargas como impedância constante (variante mais realista) - opcional
#------------------------------------------------------------------------------
load_P(ld::StandardLoad) = get_constant_active_power(ld) +
                           get_current_active_power(ld) +
                           get_impedance_active_power(ld)
load_Q(ld::StandardLoad) = get_constant_reactive_power(ld) +
                           get_current_reactive_power(ld) +
                           get_impedance_reactive_power(ld)

load_shunt = zeros(ComplexF64, n)
for ld in get_components(StandardLoad, sys)
    bus_num = get_number(get_bus(ld))
    i = idx_of[bus_num]
    S = load_P(ld) + im * load_Q(ld)          # pu na base do sistema
    V = V_pf[i]
    load_shunt[i] += conj(S) / abs2(V)        # y = conj(S)/|V|^2
end

#------------------------------------------------------------------------------
# 5. Função de cálculo de curto via Zbus
#------------------------------------------------------------------------------
function short_circuit(Y_fault, V_pf, f, Zf)
    Z = inv(Y_fault)
    If = V_pf[f] / (Z[f, f] + Zf)
    Vpos = [V_pf[i] - (Z[i, f] / (Z[f, f] + Zf)) * V_pf[f] for i in 1:length(V_pf)]
    return (Z = Z, If = If, Vpos = Vpos, Zth = Z[f, f])
end

# Variante A: clássica (geradores apenas)
Y_A = copy(Y_net); for i in 1:n; Y_A[i, i] += gen_shunt[i]; end
res_A = short_circuit(Y_A, V_pf, f, Z_FAULT)

# Variante B: geradores + cargas como impedância constante
Y_B = copy(Y_A); for i in 1:n; Y_B[i, i] += load_shunt[i]; end
res_B = short_circuit(Y_B, V_pf, f, Z_FAULT)

#------------------------------------------------------------------------------
# 6. Conversão para unidades físicas (kA) na barra de falta
#------------------------------------------------------------------------------
Vbase_f_kV = get_base_voltage(buses[FAULT_BUS])              # kV (linha-linha)
Ibase_f_kA = S_base / (sqrt(3) * Vbase_f_kV)                 # kA  (S em MVA)

println("\n", "="^70)
println(" RESULTADO NA BARRA DE FALTA (barra ", FAULT_BUS, ")")
println("="^70)
@printf("  Tensão pré-falta              : %.4f pu (%.2f°)\n",
        abs(V_pf[f]), rad2deg(angle(V_pf[f])))
@printf("  Tensão base                   : %.2f kV\n", Vbase_f_kV)
@printf("  Corrente base                 : %.4f kA\n", Ibase_f_kA)
println()
@printf("  [A] Geradores apenas:\n")
@printf("      Z_thevenin (barra 7)      : %.5f + j%.5f pu  (|Z|=%.5f)\n",
        real(res_A.Zth), imag(res_A.Zth), abs(res_A.Zth))
@printf("      Corrente de curto |If|    : %.4f pu = %.4f kA\n",
        abs(res_A.If), abs(res_A.If) * Ibase_f_kA)
@printf("      Potência de curto (SCC)   : %.2f MVA\n",
        abs(res_A.If) * abs(V_pf[f]) * S_base)
println()
@printf("  [B] Geradores + cargas (Z const):\n")
@printf("      Z_thevenin (barra 7)      : %.5f + j%.5f pu  (|Z|=%.5f)\n",
        real(res_B.Zth), imag(res_B.Zth), abs(res_B.Zth))
@printf("      Corrente de curto |If|    : %.4f pu = %.4f kA\n",
        abs(res_B.If), abs(res_B.If) * Ibase_f_kA)
@printf("      Potência de curto (SCC)   : %.2f MVA\n",
        abs(res_B.If) * abs(V_pf[f]) * S_base)

#------------------------------------------------------------------------------
# 7. Tensões em todas as barras durante a falta
#------------------------------------------------------------------------------
df_v = DataFrame(
    bus      = bus_order,
    Vpre_pu  = abs.(V_pf),
    VA_pu    = abs.(res_A.Vpos),     # geradores apenas
    VB_pu    = abs.(res_B.Vpos),     # geradores + cargas
    VA_ang   = rad2deg.(angle.(res_A.Vpos)),
    VB_ang   = rad2deg.(angle.(res_B.Vpos)),
)
println("\n--- Tensões durante a falta (módulo, pu) ---")
show(df_v, allrows = true); println()
CSV.write(joinpath(RESULTS_DIR, "03_fault_voltages.csv"), df_v)

#------------------------------------------------------------------------------
# 8. Contribuições de corrente pelos ramos conectados à barra de falta
#------------------------------------------------------------------------------
# Corrente injetada em 7 por cada ramo vizinho: I_{viz->7} = (V_viz - V_7)*(-Y[viz,7])
# (Y[viz,7] = -y_serie; durante a falta V_7 = 0 para falta franca)
println("\n--- Contribuições de corrente para a falta (variante A) ---")
neighbors = [j for j in 1:n if j != f && !iszero(Y_net[f, j])]
df_contrib = DataFrame(from_bus = Int[], I_pu = Float64[], I_kA = Float64[])
Itot = 0.0 + 0.0im
for j in neighbors
    y_series = -Y_net[f, j]
    I_j = (res_A.Vpos[j] - res_A.Vpos[f]) * y_series
    global Itot += I_j
    push!(df_contrib, (bus_order[j], abs(I_j), abs(I_j) * Ibase_f_kA))
end
show(df_contrib, allrows = true); println()
@printf("  Soma das contribuições        : %.4f pu (|If| direto = %.4f pu)\n",
        abs(Itot), abs(res_A.If))
CSV.write(joinpath(RESULTS_DIR, "03_fault_contributions.csv"), df_contrib)

#------------------------------------------------------------------------------
# 9. Exportar Zbus (variante A) e resumo
#------------------------------------------------------------------------------
import Serialization
Serialization.serialize(joinpath(RESULTS_DIR, "03_results.jls"),
    (V_pf = V_pf, res_A = res_A, res_B = res_B,
     bus_order = bus_order, Ibase_f_kA = Ibase_f_kA, fault_bus = FAULT_BUS))

df_summary = DataFrame(
    grandeza = ["If_pu_A", "If_kA_A", "Zth_abs_A", "SCC_MVA_A",
                "If_pu_B", "If_kA_B", "Zth_abs_B", "SCC_MVA_B"],
    valor = [abs(res_A.If), abs(res_A.If)*Ibase_f_kA, abs(res_A.Zth),
             abs(res_A.If)*abs(V_pf[f])*S_base,
             abs(res_B.If), abs(res_B.If)*Ibase_f_kA, abs(res_B.Zth),
             abs(res_B.If)*abs(V_pf[f])*S_base],
)
CSV.write(joinpath(RESULTS_DIR, "03_summary.csv"), df_summary)

println("\n", "="^70)
println(" Arquivos exportados: 03_fault_voltages.csv, 03_fault_contributions.csv,")
println("                      03_summary.csv, 03_results.jls")
println("="^70)
