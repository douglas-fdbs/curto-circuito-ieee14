#==============================================================================
 SCUtils - utilitários compartilhados para o estudo de curto-circuito
 ------------------------------------------------------------------------------
 Reúne as rotinas reutilizadas pelos scripts de cenários (05) e geração solar
 (06): carregamento do sistema, fluxo de potência, escalonamento de carga e o
 cálculo estático de curto-circuito trifásico pelo método Zbus.

 O método Zbus aqui implementado é idêntico ao do script 03 (validado): a
 soma das contribuições dos ramos confere com a corrente de falta direta.
==============================================================================#
module SCUtils

using PowerSystems
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using PowerFlows
using LinearAlgebra
import Logging

const PSY = PowerSystems

export build_14bus, solve_pf!, load_PQ, scale_loads!, take_generator_offline!,
       zbus_short_circuit, base_current_kA

"Carrega o IEEE 14 barras (com dados dinâmicos), suprimindo warnings do caso."
function build_14bus()
    sys = Logging.with_logger(Logging.NullLogger()) do
        build_system(PSIDSystems, "14 Bus Base Case")
    end
    set_units_base_system!(sys, "SYSTEM_BASE")
    return sys
end

"Resolve o fluxo de potência AC e armazena a solução (tensões) no sistema."
function solve_pf!(sys)
    conv = Logging.with_logger(Logging.NullLogger()) do
        solve_and_store_power_flow!(ACPowerFlow(), sys)
    end
    conv || @warn "Fluxo de potência não convergiu"
    return conv
end

"Potência ativa/reativa total de uma carga (StandardLoad = modelo ZIP)."
function load_PQ(ld::StandardLoad)
    P = get_constant_active_power(ld) + get_current_active_power(ld) +
        get_impedance_active_power(ld)
    Q = get_constant_reactive_power(ld) + get_current_reactive_power(ld) +
        get_impedance_reactive_power(ld)
    return P, Q
end
load_PQ(ld) = (get_active_power(ld), get_reactive_power(ld))

"Escala todas as componentes ZIP de todas as cargas por `factor`."
function scale_loads!(sys, factor)
    for ld in get_components(StandardLoad, sys)
        set_constant_active_power!(ld, get_constant_active_power(ld) * factor)
        set_constant_reactive_power!(ld, get_constant_reactive_power(ld) * factor)
        set_current_active_power!(ld, get_current_active_power(ld) * factor)
        set_current_reactive_power!(ld, get_current_reactive_power(ld) * factor)
        set_impedance_active_power!(ld, get_impedance_active_power(ld) * factor)
        set_impedance_reactive_power!(ld, get_impedance_reactive_power(ld) * factor)
    end
    return sys
end

"Tira de serviço o gerador da barra `bus_num` (e converte a barra para PQ)."
function take_generator_offline!(sys, bus_num)
    for g in get_components(ThermalStandard, sys)
        if get_number(get_bus(g)) == bus_num
            set_available!(g, false)
            b = get_bus(g)
            get_bustype(b) == ACBusTypes.PV && set_bustype!(b, ACBusTypes.PQ)
        end
    end
    return sys
end

"Corrente de base [kA] na barra `bus_num` (S_base em MVA, V_base linha-linha)."
function base_current_kA(sys, bus_num)
    b = first(x for x in get_components(ACBus, sys) if get_number(x) == bus_num)
    return get_base_power(sys) / (sqrt(3) * get_base_voltage(b))
end

"""
    zbus_short_circuit(sys; fault_bus, z_fault=0.0, include_loads=false)

Curto-circuito trifásico na barra `fault_bus` pelo método Zbus.
Pressupõe que o fluxo de potência já foi resolvido (tensões pré-falta no sistema).

Modelagem: Ybus da rede + reatância subtransitória X"d de cada gerador como
shunt para a terra. Opcionalmente inclui as cargas como impedância constante.

Retorna NamedTuple: If, Zth, Vpre, Vpos, bus_order, Ibase_kA, scc_mva.
"""
function zbus_short_circuit(sys; fault_bus, z_fault = 0.0 + 0.0im, include_loads = false)
    S_base = get_base_power(sys)
    # Ybus PURA da rede (linhas + trafos + shunts de linha). As cargas NÃO entram
    # aqui (são adicionadas explicitamente só na variante include_loads), evitando
    # contar a parcela de impedância das cargas ZIP duas vezes.
    ybus = Ybus(sys; include_constant_impedance_loads = false)
    Y = Matrix(ybus.data)
    bus_order = collect(ybus.axes[1])
    n = size(Y, 1)
    idx_of = Dict(b => i for (i, b) in enumerate(bus_order))
    f = idx_of[fault_bus]
    buses = Dict(get_number(b) => b for b in get_components(ACBus, sys))

    # Tensões pré-falta (solução do fluxo de potência armazenada no sistema)
    V_pf = ComplexF64[get_magnitude(buses[b]) * cis(get_angle(buses[b])) for b in bus_order]

    # Reatância subtransitória dos geradores disponíveis -> shunt p/ a terra
    for sg in get_components(ThermalStandard, sys)
        get_available(sg) || continue
        dyn = get_dynamic_injector(sg)
        dyn === nothing && continue
        mach = get_machine(dyn)
        z_sys = (get_R(mach) + im * get_Xd_pp(mach)) * (S_base / get_base_power(dyn))
        i = idx_of[get_number(get_bus(sg))]
        Y[i, i] += 1 / z_sys
    end

    # Cargas como impedância constante (opcional)
    if include_loads
        for ld in get_components(StandardLoad, sys)
            get_available(ld) || continue
            i = idx_of[get_number(get_bus(ld))]
            P, Q = load_PQ(ld)
            Y[i, i] += conj(P + im * Q) / abs2(V_pf[i])
        end
    end

    Z = inv(Y)
    If = V_pf[f] / (Z[f, f] + z_fault)
    Vpos = [V_pf[i] - (Z[i, f] / (Z[f, f] + z_fault)) * V_pf[f] for i in 1:n]

    Vbase_kV = get_base_voltage(buses[fault_bus])
    Ibase_kA = S_base / (sqrt(3) * Vbase_kV)
    scc_mva = abs(If) * abs(V_pf[f]) * S_base

    return (; If, Zth = Z[f, f], Vpre = V_pf, Vpos, bus_order, Ibase_kA, scc_mva, idx_of)
end

end # module
