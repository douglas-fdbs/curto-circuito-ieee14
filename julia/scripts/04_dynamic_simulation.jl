#==============================================================================
 Script 04 - Simulação dinâmica do curto-circuito trifásico na barra 7
 ------------------------------------------------------------------------------
 Usa PowerSimulationsDynamics.jl para simular a resposta transitória do sistema
 IEEE 14 barras a um curto-circuito trifásico na barra 7, modelado pela
 perturbação NetworkSwitch (admitância shunt elevada na barra 7).

 Dois casos são simulados:
   CASO A - Falta quase franca (Z=1e-3 pu), PERMANENTE, janela curta.
            Mede a corrente de falta em DOIS instantes: o pico SUBTRANSITÓRIO
            (1º ciclo após a falta — comparável ao Zbus/ANAFAS, que usam X"d) e
            a corrente AMORTECIDA do regime transitório (a corrente decai de
            X"d->X'd com o tempo). Captura também os afundamentos de tensão.
   CASO B - Falta severa (Z=5e-2 pu) ELIMINADA em 100 ms.
            Mostra a resposta transitória completa (ângulos e velocidades dos
            rotores, recuperação das tensões) - estabilidade transitória.

 Observação numérica: o solver DAE (IDA) não converge na restauração brusca da
 rede quando a falta é quase franca (salto de tensão ~18x na barra 7, que é uma
 barra de transferência). Por isso a falta franca é analisada de forma
 permanente (Caso A) e a recuperação transitória usa uma falta severa porém
 eliminável (Caso B). Ambas são curtos trifásicos na barra 7.
==============================================================================#

using PowerSystems
using PowerSimulationsDynamics
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using Sundials
using SparseArrays
using DataFrames
using CSV
using Plots
using Statistics
import Logging

const PSID = PowerSimulationsDynamics
const PSY = PowerSystems
const PNM = PowerNetworkMatrices

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULTS_DIR = joinpath(ROOT, "data", "results")
const FIG_DIR = joinpath(ROOT, "data", "figures")
mkpath(RESULTS_DIR)
mkpath(FIG_DIR)
gr()

const FAULT_BUS = 7
const T_FAULT = 1.0
const REF_GEN = "generator-1-1"   # máquina de referência (barra slack)

#------------------------------------------------------------------------------
# Função utilitária: simula uma falta trifásica na barra `fault_bus`.
#   z_fault : impedância de falta [pu]
#   t_clear : instante de eliminação [s] ou `nothing` (falta permanente)
#------------------------------------------------------------------------------
function simulate_fault(; z_fault, t_clear, tspan, dtmax = 0.01, fault_bus = FAULT_BUS)
    sys = Logging.with_logger(Logging.NullLogger()) do
        build_system(PSIDSystems, "14 Bus Base Case")
    end
    set_units_base_system!(sys, "SYSTEM_BASE")
    # Cargas como impedância constante (robustez sob baixa tensão)
    for l in get_components(StandardLoad, sys)
        transform_load_to_constant_impedance(l)
    end

    # Ybus na convenção interna do PSID (cargas Z tratadas como injeção)
    ybus = Ybus(sys; include_constant_impedance_loads = false)
    bus_order = collect(ybus.axes[1])
    idx_of = Dict(b => i for (i, b) in enumerate(bus_order))
    f = idx_of[fault_bus]

    Y_pre = SparseMatrixCSC{ComplexF32, Int}(ybus.data)
    Y_fault = copy(Y_pre)
    Yf_shunt = ComplexF32(1.0 / z_fault)
    Y_fault[f, f] += Yf_shunt

    perturbations = t_clear === nothing ?
        [NetworkSwitch(T_FAULT, Y_fault)] :
        [NetworkSwitch(T_FAULT, Y_fault), NetworkSwitch(t_clear, Y_pre)]

    sim = PSID.Simulation(ResidualModel, sys, mktempdir(), tspan, perturbations)
    status = execute!(sim, IDA(); dtmax = dtmax, saveat = dtmax)
    results = read_results(sim)

    # Séries de tensão (todas as barras)
    volt = Dict(b => get_voltage_magnitude_series(results, b) for b in bus_order)

    # Geradores dinâmicos
    gen_names = sort([get_name(g) for g in get_components(ThermalStandard, sys)
                      if get_dynamic_injector(g) !== nothing])
    delta = Dict(g => get_state_series(results, (g, :δ)) for g in gen_names)
    omega = Dict(g => get_state_series(results, (g, :ω)) for g in gen_names)

    # Corrente de falta: I_f(t) = V_f(t) * |Y_falta|  (KCL no nó de falta)
    t, vf = volt[fault_bus]
    t_end_fault = t_clear === nothing ? tspan[2] : t_clear
    if_mag = [(T_FAULT <= t[k] < t_end_fault) ? vf[k] * abs(Yf_shunt) : 0.0
              for k in eachindex(t)]
    # Pico SUBTRANSITÓRIO: média do 1º ciclo após a falta (~16 ms). Pula a amostra do
    # instante EXATO do chaveamento (V_pré*Y_falta = lixo numérico). É ESTE o valor
    # comparável ao método estático Zbus e ao ANAFAS (ambos são subtransitórios).
    subtr = findall(k -> (T_FAULT + 1e-4) <= t[k] <= (T_FAULT + 0.02), eachindex(t))
    if_subtr = isempty(subtr) ? 0.0 : mean(if_mag[subtr])
    # Corrente AMORTECIDA (regime transitório): janela tardia, longe da borda final.
    # Mostra o decaimento subtransitório->transitório (X"d -> X'd) sob falta permanente.
    settled = findall(k -> (T_FAULT + 0.30) <= t[k] <= (t_end_fault - 0.05), eachindex(t))
    if_settled = isempty(settled) ? if_subtr : mean(if_mag[settled])

    Vbase_kV = get_base_voltage(first(b for b in get_components(ACBus, sys)
                                      if get_number(b) == fault_bus))
    Ibase_kA = get_base_power(sys) / (sqrt(3) * Vbase_kV)

    # Tensões durante a falta (média no 1º ciclo, subtransitório) p/ comparação estática
    v_during = Dict(b => (isempty(subtr) ? NaN : mean(volt[b][2][subtr]))
                    for b in bus_order)

    return (; status, bus_order, volt, delta, omega, gen_names,
            if_mag, if_subtr, if_settled, Ibase_kA, t_end_fault, v_during,
            vfmin = minimum(vf), Yf_abs = abs(Yf_shunt))
end

#==============================================================================
 CASO A - Falta quase franca, permanente (comparação com Zbus estático)
==============================================================================#
println("="^70)
println(" CASO A - Falta quase franca permanente na barra ", FAULT_BUS, " (Z=1e-3 pu)")
println("="^70)
A = simulate_fault(; z_fault = 1e-3, t_clear = nothing, tspan = (0.0, 1.6), dtmax = 0.002)
println("  Status                 : ", A.status)
println("  V", FAULT_BUS, " mínima durante falta : ", round(A.vfmin, digits = 5), " pu")
println("  |I_falta| subtransitória (1º ciclo)   : ", round(A.if_subtr, digits = 4),
        " pu = ", round(A.if_subtr * A.Ibase_kA, digits = 4),
        " kA  <- comparável ao Zbus/ANAFAS")
println("  |I_falta| amortecida (regime transit.): ", round(A.if_settled, digits = 4),
        " pu = ", round(A.if_settled * A.Ibase_kA, digits = 4), " kA")

# Tabela: tensões durante a falta (dinâmico, Caso A) p/ comparação com estático
df_vA = DataFrame(bus = A.bus_order,
                  V_durante_pu = [A.v_during[b] for b in A.bus_order])
CSV.write(joinpath(RESULTS_DIR, "04A_tensoes_durante_falta.csv"), df_vA)
println("\n  Tensões durante a falta (dinâmico, Caso A):")
show(df_vA, allrows = true)
println()

#==============================================================================
 CASO B - Falta severa eliminada (resposta transitória completa)
==============================================================================#
const Z_FAULT_B = 5e-2
const T_CLEAR_B = 1.10
println("\n", "="^70)
println(" CASO B - Falta severa eliminada na barra ", FAULT_BUS,
        " (Z=5e-2 pu, elim. em ", round(Int, (T_CLEAR_B - T_FAULT) * 1000), " ms)")
println("="^70)
B = simulate_fault(; z_fault = Z_FAULT_B, t_clear = T_CLEAR_B, tspan = (0.0, 15.0))
println("  Status                 : ", B.status)
println("  V", FAULT_BUS, " mínima durante falta : ", round(B.vfmin, digits = 5), " pu")
println("  |I_falta| subtransitória : ", round(B.if_subtr, digits = 4), " pu = ",
        round(B.if_subtr * B.Ibase_kA, digits = 4), " kA")

#------------------------------------------------------------------------------
# Gráficos do Caso B (resposta transitória)
#------------------------------------------------------------------------------
buses_plot = [1, 4, 7, 8, 9]
p1 = plot(; xlabel = "tempo [s]", ylabel = "Tensão [pu]",
          title = "Caso B: Tensões - curto eliminado na barra $FAULT_BUS",
          legend = :bottomright)
for b in buses_plot
    tt, vv = B.volt[b]
    plot!(p1, tt, vv; label = "BUS $b", lw = 1.8)
end
vline!(p1, [T_FAULT, T_CLEAR_B]; ls = :dash, color = :gray, label = "falta/elim.")
savefig(p1, joinpath(FIG_DIR, "04b_tensoes.png"))

tref, dref = B.delta[REF_GEN]
p2 = plot(; xlabel = "tempo [s]", ylabel = "δ − δ_ref [rad]",
          title = "Caso B: Ângulos relativos dos rotores", legend = :topright)
for g in B.gen_names
    g == REF_GEN && continue
    tg, dg = B.delta[g]
    plot!(p2, tg, dg .- dref; label = g, lw = 1.8)
end
vline!(p2, [T_FAULT, T_CLEAR_B]; ls = :dash, color = :gray, label = "")
savefig(p2, joinpath(FIG_DIR, "04b_angulos_rotor.png"))

p3 = plot(; xlabel = "tempo [s]", ylabel = "ω [pu]",
          title = "Caso B: Velocidade dos rotores", legend = :topright)
for g in B.gen_names
    tg, wg = B.omega[g]
    plot!(p3, tg, wg; label = g, lw = 1.8)
end
vline!(p3, [T_FAULT, T_CLEAR_B]; ls = :dash, color = :gray, label = "")
savefig(p3, joinpath(FIG_DIR, "04b_velocidades.png"))

# Corrente de falta (Caso A) — remove a amostra-lixo do instante do chaveamento
# (V_pré*Y_falta) p/ o eixo autoescalar no pico subtransitório real; janela focada
# no decaimento subtransitório->transitório, evitando a borda final da simulação.
tA, _ = A.volt[FAULT_BUS]
if_plot = [x > 50 ? NaN : x for x in A.if_mag]
p4 = plot(tA, if_plot; xlabel = "tempo [s]", ylabel = "|I_falta| [pu]",
          title = "Caso A: Corrente de curto na barra $FAULT_BUS (decaimento subtransitório)",
          label = "I_falta(t)", lw = 2.0, legend = :topright,
          xlims = (T_FAULT - 0.03, T_FAULT + 0.5), ylims = (0, 1.2 * A.if_subtr))
hline!(p4, [A.if_subtr]; ls = :dash, color = :red,
       label = "subtransitório ≈ $(round(A.if_subtr, digits=2)) pu")
hline!(p4, [A.if_settled]; ls = :dot, color = :gray,
       label = "amortecida ≈ $(round(A.if_settled, digits=2)) pu")
vline!(p4, [T_FAULT]; ls = :dash, color = :black, label = "falta")
savefig(p4, joinpath(FIG_DIR, "04a_corrente_falta.png"))

#------------------------------------------------------------------------------
# Exportar séries temporais do Caso B
#------------------------------------------------------------------------------
tB = B.volt[FAULT_BUS][1]
df_v = DataFrame(time = tB)
for b in B.bus_order
    df_v[!, Symbol("V_bus$b")] = B.volt[b][2]
end
CSV.write(joinpath(RESULTS_DIR, "04B_dynamic_voltages.csv"), df_v)

df_d = DataFrame(time = B.delta[REF_GEN][1])
for g in B.gen_names
    df_d[!, Symbol("delta_$g")] = B.delta[g][2]
    df_d[!, Symbol("omega_$g")] = B.omega[g][2]
end
CSV.write(joinpath(RESULTS_DIR, "04B_dynamic_machine_states.csv"), df_d)

# Resumo
df_sum = DataFrame(
    caso = ["A (franca, permanente)", "B (severa, eliminada)"],
    z_fault_pu = [1e-3, Z_FAULT_B],
    V7_min_pu = [A.vfmin, B.vfmin],
    If_subtr_pu = [A.if_subtr, B.if_subtr],
    If_subtr_kA = [A.if_subtr * A.Ibase_kA, B.if_subtr * B.Ibase_kA],
    If_amort_pu = [A.if_settled, B.if_settled],
    If_amort_kA = [A.if_settled * A.Ibase_kA, B.if_settled * B.Ibase_kA],
    status = [string(A.status), string(B.status)],
)
CSV.write(joinpath(RESULTS_DIR, "04_summary.csv"), df_sum)
println("\n", "="^70)
println(" RESUMO DINÂMICO")
show(df_sum, allrows = true)
println("\n\n Figuras: 04a_corrente_falta, 04b_tensoes, 04b_angulos_rotor, 04b_velocidades")
println(" Séries:  04A_*, 04B_*, 04_summary.csv")
println("="^70)
