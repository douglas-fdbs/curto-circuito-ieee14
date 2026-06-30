#==============================================================================
 Script 06 - Impacto de geração solar fotovoltaica no curto-circuito da barra 7
 ------------------------------------------------------------------------------
 Conecta uma usina solar FV de tamanho considerável (RenewableDispatch + inversor
 dinâmico grid-following) na barra 4 (69 kV, ligada à barra de falta 7 pelo trafo
 4-7) e compara a resposta dinâmica a um curto trifásico na barra 7, COM e SEM a FV.
 (A barra 4, de 69 kV, sofre menos afundamento que uma barra adjacente em 13,8 kV,
 evitando que o PLL do inversor perca o sincronismo e o solver divirja.)

 A geração baseada em inversor (IBR) contribui com corrente de falta LIMITADA
 (≈ corrente nominal), ao contrário das máquinas síncronas (corrente subtransitória
 elevada), e não fornece inércia. Este script evidencia esses efeitos.

 Nota numérica: o inversor grid-following torna a eliminação brusca da falta
 intratável para o solver DAE (mesma limitação do script 04, agravada pela
 dinâmica rápida do inversor/PLL). Por isso a comparação usa uma falta severa
 PERMANENTE em janela curta (0–2 s), que captura justamente o comportamento
 "durante o curto" — corrente de falta, suporte de tensão e limitação de corrente
 do inversor — de forma estável e justa para ambos os casos.

 Modelo do inversor (grid-following): AverageConverter + (ActivePowerPI +
 ReactivePowerPI) + CurrentModeControl + FixedDCSource + KauraPLL + LCLFilter.
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

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULTS_DIR = joinpath(ROOT, "data", "results")
const FIG_DIR = joinpath(ROOT, "data", "figures")
mkpath(RESULTS_DIR)
mkpath(FIG_DIR)
gr()

# Parâmetros
const FAULT_BUS = 7
const PV_BUS = 4          # barra 69 kV conectada à barra de falta (trafo 4-7)
const PV_NAME = "PV_solar"
const PV_P = 0.6           # potência ativa [pu, base 100 MVA] = 60 MW
const PV_S = 100.0         # base de potência da usina [MVA]
const T_FAULT = 1.0
const Z_FAULT = 5e-2       # falta severa (permanente, ver nota no cabeçalho)
const TSPAN = (0.0, 2.0)
const REF_GEN = "generator-1-1"

#------------------------------------------------------------------------------
# Inversor grid-following (modelo médio) — parâmetros do template do PSD.jl
#------------------------------------------------------------------------------
function grid_following_inverter(static_device)
    return DynamicInverter(;
        name = get_name(static_device),
        ω_ref = 1.0,
        converter = AverageConverter(; rated_voltage = 138.0, rated_current = 100.0),
        outer_control = OuterControl(
            ActivePowerPI(; Kp_p = 2.0, Ki_p = 30.0, ωz = 0.132 * 2π * 50),
            ReactivePowerPI(; Kp_q = 2.0, Ki_q = 30.0, ωf = 0.132 * 2π * 50),
        ),
        inner_control = CurrentModeControl(; kpc = 0.37, kic = 0.7, kffv = 1.0),
        dc_source = FixedDCSource(; voltage = 600.0),
        freq_estimator = KauraPLL(; ω_lp = 500.0, kp_pll = 0.084, ki_pll = 4.69),
        filter = LCLFilter(; lf = 0.009, rf = 0.016, cf = 2.5, lg = 0.002, rg = 0.003),
    )
end

#------------------------------------------------------------------------------
# Constrói o sistema, opcionalmente com a usina FV
#------------------------------------------------------------------------------
function build_system_pv(; with_pv::Bool)
    sys = Logging.with_logger(Logging.NullLogger()) do
        build_system(PSIDSystems, "14 Bus Base Case")
    end
    set_units_base_system!(sys, "SYSTEM_BASE")

    if with_pv
        bus = first(b for b in get_components(ACBus, sys) if get_number(b) == PV_BUS)
        pv = RenewableDispatch(;
            name = PV_NAME,
            available = true,
            bus = bus,
            active_power = PV_P,
            reactive_power = 0.0,
            rating = 1.0,
            prime_mover_type = PrimeMovers.PVe,
            reactive_power_limits = (min = -0.4, max = 0.4),
            power_factor = 1.0,
            operation_cost = RenewableGenerationCost(nothing),
            base_power = PV_S,
        )
        add_component!(sys, pv)
        add_component!(sys, grid_following_inverter(pv), pv)
    end

    for l in get_components(StandardLoad, sys)
        transform_load_to_constant_impedance(l)
    end
    return sys
end

#------------------------------------------------------------------------------
# Simula o curto trifásico PERMANENTE e devolve as séries de interesse
#------------------------------------------------------------------------------
function run_fault(sys)
    ybus = Ybus(sys; include_constant_impedance_loads = false)
    bus_order = collect(ybus.axes[1])
    idx_of = Dict(b => i for (i, b) in enumerate(bus_order))
    f = idx_of[FAULT_BUS]

    Y_fault = SparseMatrixCSC{ComplexF32, Int}(ybus.data)
    Yf = ComplexF32(1.0 / Z_FAULT)
    Y_fault[f, f] += Yf

    sim = PSID.Simulation(ResidualModel, sys, mktempdir(), TSPAN,
        NetworkSwitch(T_FAULT, Y_fault))
    status = execute!(sim, IDA(); dtmax = 0.005, saveat = 0.005)
    res = read_results(sim)

    volt = Dict(b => get_voltage_magnitude_series(res, b) for b in bus_order)
    gen_names = sort([get_name(g) for g in get_components(ThermalStandard, sys)
                      if get_dynamic_injector(g) !== nothing])
    omega = Dict(g => get_state_series(res, (g, :ω)) for g in gen_names)

    t, vf = volt[FAULT_BUS]
    iflt = [(t[k] >= T_FAULT) ? vf[k] * abs(Yf) : 0.0 for k in eachindex(t)]

    Vbase = get_base_voltage(first(b for b in get_components(ACBus, sys)
                                   if get_number(b) == FAULT_BUS))
    Ibase = get_base_power(sys) / (sqrt(3) * Vbase)

    return (; status, volt, omega, gen_names, t, iflt, Ibase, res)
end

# Janela breve logo após a falta (pós-subtransitório, antes da degradação do
# sistema sob falta permanente) — corrente representativa e comparável aos
# scripts 03/04.
settled_idx(t) = findall(k -> (T_FAULT + 0.05) <= t[k] <= (T_FAULT + 0.30), eachindex(t))

#==============================================================================
 Executa os dois casos
==============================================================================#
println("="^70)
println(" Impacto de geração solar FV no curto da barra ", FAULT_BUS)
println("="^70)

println("\n--- Caso SEM FV ---")
base = run_fault(build_system_pv(; with_pv = false))
println("  Status: ", base.status)

println("\n--- Caso COM FV (", round(Int, PV_P * 100), " MW na barra ", PV_BUS, ") ---")
sys_pv = build_system_pv(; with_pv = true)
pv = run_fault(sys_pv)
println("  Status: ", pv.status)

# Potência e corrente da FV durante o transitório
pv_P = get_activepower_series(pv.res, PV_NAME)
pv_Q = get_reactivepower_series(pv.res, PV_NAME)
pv_Ir = get_real_current_series(pv.res, PV_NAME)
pv_Ii = get_imaginary_current_series(pv.res, PV_NAME)
pv_Imag = sqrt.(pv_Ir[2] .^ 2 .+ pv_Ii[2] .^ 2)

# Corrente de falta estabilizada (durante a falta)
ib = settled_idx(base.t)
ip = settled_idx(pv.t)
if_base = mean(base.iflt[ib])
if_pv = mean(pv.iflt[ip])

println("\n", "="^70)
println(" RESULTADOS")
println("="^70)
println("  Corrente de falta na barra 7 (estab. durante a falta):")
println("    SEM FV : ", round(if_base, digits = 4), " pu = ",
        round(if_base * base.Ibase, digits = 3), " kA")
println("    COM FV : ", round(if_pv, digits = 4), " pu = ",
        round(if_pv * pv.Ibase, digits = 3), " kA")
println("    Δ      : ", round((if_pv - if_base) / if_base * 100, digits = 2), " %")
# Corrente própria da FV durante a falta (limitação típica de IBR)
ipv_fault = mean(pv_Imag[settled_idx(pv_Ir[1])])
println("  Corrente da FV durante a falta : ", round(ipv_fault, digits = 3),
        " pu (base ", round(Int, PV_S), " MVA) — limitada, típico de IBR")
println("  (uma máquina síncrona de mesmo porte daria várias vezes a nominal)")

#------------------------------------------------------------------------------
# Gráficos comparativos
#------------------------------------------------------------------------------
# (1) Tensão na barra de falta
p1 = plot(; xlabel = "tempo [s]", ylabel = "V_bus7 [pu]",
          title = "Tensão na barra de falta (7): efeito da FV", legend = :right,
          xlims = (0.8, TSPAN[2]))
plot!(p1, base.volt[FAULT_BUS]...; label = "sem FV", lw = 2)
plot!(p1, pv.volt[FAULT_BUS]...; label = "com FV", lw = 2, ls = :dash)
vline!(p1, [T_FAULT]; ls = :dot, color = :gray, label = "falta")
savefig(p1, joinpath(FIG_DIR, "06_tensao_bus7.png"))

# (2) Tensão na barra da FV
p2 = plot(; xlabel = "tempo [s]", ylabel = "V_bus$PV_BUS [pu]",
          title = "Tensão na barra da FV (barra $PV_BUS)", legend = :right,
          xlims = (0.8, TSPAN[2]))
plot!(p2, base.volt[PV_BUS]...; label = "sem FV", lw = 2)
plot!(p2, pv.volt[PV_BUS]...; label = "com FV", lw = 2, ls = :dash)
vline!(p2, [T_FAULT]; ls = :dot, color = :gray, label = "falta")
savefig(p2, joinpath(FIG_DIR, "06_tensao_pv.png"))

# (3) Velocidade da máquina de referência
p3 = plot(; xlabel = "tempo [s]", ylabel = "ω [pu]",
          title = "Velocidade do gerador $REF_GEN durante a falta", legend = :topleft,
          xlims = (0.8, TSPAN[2]))
plot!(p3, base.omega[REF_GEN]...; label = "sem FV", lw = 2)
plot!(p3, pv.omega[REF_GEN]...; label = "com FV", lw = 2, ls = :dash)
vline!(p3, [T_FAULT]; ls = :dot, color = :gray, label = "falta")
savefig(p3, joinpath(FIG_DIR, "06_velocidade_ref.png"))

# (4) Resposta da usina FV (P, Q, |I|)
p4 = plot(; xlabel = "tempo [s]", ylabel = "FV [pu, base $(round(Int,PV_S)) MVA]",
          title = "Resposta da usina FV durante o curto", legend = :right,
          xlims = (0.8, TSPAN[2]))
plot!(p4, pv_P...; label = "P", lw = 2)
plot!(p4, pv_Q...; label = "Q", lw = 2)
plot!(p4, pv_Ir[1], pv_Imag; label = "|I|", lw = 2, ls = :dash)
vline!(p4, [T_FAULT]; ls = :dot, color = :gray, label = "falta")
savefig(p4, joinpath(FIG_DIR, "06_resposta_fv.png"))

#------------------------------------------------------------------------------
# Exportar séries e resumo (alinhando pelo menor comprimento, por segurança)
#------------------------------------------------------------------------------
m = min(length(base.t), length(pv.t))
df = DataFrame(time = base.t[1:m],
    V7_sem_fv = base.volt[FAULT_BUS][2][1:m], V7_com_fv = pv.volt[FAULT_BUS][2][1:m],
    V9_sem_fv = base.volt[PV_BUS][2][1:m], V9_com_fv = pv.volt[PV_BUS][2][1:m],
    w_ref_sem_fv = base.omega[REF_GEN][2][1:m], w_ref_com_fv = pv.omega[REF_GEN][2][1:m])
CSV.write(joinpath(RESULTS_DIR, "06_pv_comparison.csv"), df)

df_fv = DataFrame(time = pv_P[1], P_pu = pv_P[2], Q_pu = pv_Q[2], I_mag_pu = pv_Imag)
CSV.write(joinpath(RESULTS_DIR, "06_pv_response.csv"), df_fv)

df_sum = DataFrame(
    caso = ["sem FV", "com FV"],
    If_pu = [if_base, if_pv],
    If_kA = [if_base * base.Ibase, if_pv * pv.Ibase],
)
CSV.write(joinpath(RESULTS_DIR, "06_summary.csv"), df_sum)

println("\n Figuras: 06_tensao_bus7, 06_tensao_pv, 06_velocidade_ref, 06_resposta_fv")
println(" Séries:  06_pv_comparison.csv, 06_pv_response.csv, 06_summary.csv")
println("="^70)
