#==============================================================================
 Script 07 - Exportação de matrizes e tabelas em LaTeX para o artigo
 ------------------------------------------------------------------------------
 Gera, a partir dos resultados de curto-circuito, fragmentos LaTeX prontos para
 \input{} no Overleaf:

   * Matriz Ybus (condutâncias G, susceptâncias B e módulo |Y|) como matrizes
     visuais (ambiente bmatrix), além de um "spy plot" da esparsidade.
   * Matriz Zbus (módulo |Z| e a coluna do ponto de falta) como matriz/vetor.
   * Vetores de tensão pré-falta e durante a falta.
   * Tabelas comparativas Ybus x PSD.jl x ANAFAS (com coluna ANAFAS a preencher).

 Para permitir uma comparação JUSTA com o ANAFAS, o curto na barra 7 é calculado
 em QUATRO variantes, combinando:
   - Tensão pré-falta:  FLAT (1,0 pu, padrão clássico do ANAFAS)  ou  FLUXO (do
     fluxo de potência do caso base);
   - Cargas:            DESPREZADAS  ou  como IMPEDÂNCIA CONSTANTE.
 (ver COMPARACAO_ANAFAS.md para a metodologia.)

 Saídas em data/latex/*.tex e a figura data/figures/07_ybus_spy.png.
==============================================================================#

using PowerSystems
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using PowerFlows
using LinearAlgebra
using DataFrames
using CSV
using Printf
using Plots
import Logging

const PSY = PowerSystems
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULTS_DIR = joinpath(ROOT, "data", "results")
const LATEX_DIR = joinpath(ROOT, "data", "headquarters", "latex")  # fragmentos \input
const TXT_DIR = joinpath(ROOT, "data", "headquarters", "txt")      # matrizes ASCII visuais
const FIG_DIR = joinpath(ROOT, "data", "figures")
mkpath(LATEX_DIR); mkpath(TXT_DIR); mkpath(FIG_DIR)
gr()

const FAULT_BUS = 7

#==============================================================================
 1. Helpers de formatação LaTeX
==============================================================================#

"Formata um real com `d` casas; zera o '-0.000' e marca zero exato como '0'."
function rfmt(x::Real; d::Int = 3, zero_dash::Bool = false)
    if abs(x) < 10.0^(-d - 1)
        return zero_dash ? "\\cdot" : "0"
    end
    # Printf.Format permite precisão dinâmica (o @sprintf exige formato literal)
    s = Printf.format(Printf.Format("%.$(d)f"), x)
    s = replace(s, r"^-0\.0*$" => "0")   # evita "-0.000"
    return s
end

"Formata um complexo como 'a+bj' (para tabelas, não para matriz grande)."
function cfmt(z::Complex; d::Int = 3)
    a, b = real(z), imag(z)
    sign = b >= 0 ? "+" : "-"
    return string(rfmt(a; d = d), sign, rfmt(abs(b); d = d), "j")
end

"Converte uma matriz real em um ambiente bmatrix do LaTeX."
function matrix_to_latex(M::AbstractMatrix{<:Real}; d::Int = 3, zero_dash::Bool = true)
    n, m = size(M)
    io = IOBuffer()
    println(io, "\\begin{bmatrix}")
    for i in 1:n
        cells = [rfmt(M[i, j]; d = d, zero_dash = zero_dash) for j in 1:m]
        println(io, "  ", join(cells, " & "), " \\\\")
    end
    print(io, "\\end{bmatrix}")
    return String(take!(io))
end

"Converte um vetor real em um vetor-coluna bmatrix do LaTeX."
function vector_to_latex(v::AbstractVector{<:Real}; d::Int = 4)
    io = IOBuffer()
    println(io, "\\begin{bmatrix}")
    for x in v
        println(io, "  ", rfmt(x; d = d), " \\\\")
    end
    print(io, "\\end{bmatrix}")
    return String(take!(io))
end

"Embrulha um corpo LaTeX num arquivo com cabeçalho explicativo e o grava."
function write_tex(fname::String, body::String; comment::String = "")
    path = joinpath(LATEX_DIR, fname)
    open(path, "w") do io
        println(io, "% ", "="^70)
        isempty(comment) || foreach(l -> println(io, "% ", l), split(comment, "\n"))
        println(io, "% Gerado automaticamente por 07_export_latex.jl — não editar à mão.")
        println(io, "% ", "="^70)
        println(io, body)
    end
    println("  ✓ ", fname)
    return path
end

#------------------------------------------------------------------------------
# Helpers de formatação ASCII (.txt) — matrizes "visuais" como na imagem
#------------------------------------------------------------------------------

"Célula numérica de largura `w`, `d` casas; zero exato vira '.'."
function cell(x::Real; d::Int, w::Int)
    s = abs(x) < 10.0^(-d - 1) ? "." : Printf.format(Printf.Format("%.$(d)f"), x)
    return lpad(s, w)
end

"Renderiza uma matriz real como bloco ASCII (título + cabeçalho B\\B + linhas)."
function matrix_to_txt(M::AbstractMatrix{<:Real}, bus_order, titulo::String;
                       d::Int = 2, w::Int = 7)
    n = size(M, 1)
    total = 6 + n * w
    io = IOBuffer()
    println(io, "="^total)
    println(io, " ", titulo)
    println(io, "="^total)
    println(io, rpad(" B\\B |", 6), join(lpad.(string.(bus_order), w)))
    println(io, "-"^total)
    for i in 1:n
        println(io, lpad(string(bus_order[i]), 4), " |",
                join(cell(M[i, j]; d = d, w = w) for j in 1:n))
    end
    println(io, "="^total)
    return String(take!(io))
end

"Renderiza um vetor real como bloco ASCII (título + Barra | valor)."
function vector_to_txt(v::AbstractVector{<:Real}, bus_order, titulo::String; d::Int = 4)
    w = 10
    total = 7 + w
    io = IOBuffer()
    println(io, "="^total)
    println(io, " ", titulo)
    println(io, "="^total)
    println(io, "Barra |", lpad("valor", w))
    println(io, "-"^total)
    for i in 1:length(v)
        s = Printf.format(Printf.Format("%.$(d)f"), v[i])
        println(io, lpad(string(bus_order[i]), 5), " |", lpad(s, w))
    end
    println(io, "="^total)
    return String(take!(io))
end

"Grava um bloco ASCII em data/headquarters/txt/."
function write_txt(fname::String, body::String)
    open(joinpath(TXT_DIR, fname), "w") do io
        print(io, body)
    end
    println("  ✓ txt/", fname)
end

"Formata um número com `d` casas (sem tratamento de zero)."
fmtn(x::Real; d::Int = 2) = Printf.format(Printf.Format("%.$(d)f"), x)

"Erro percentual com sinal e símbolo %, para .txt (ex.: '+3.1%')."
errpct(e::Real) = string(e >= 0 ? "+" : "-", fmtn(abs(e); d = 1), "%")

"Renderiza uma tabela (cabeçalhos + linhas de strings) como bloco ASCII."
function table_to_txt(titulo::String, headers::Vector{String},
                      rows::Vector{Vector{String}})
    ncol = length(headers)
    aligns = [c == 1 ? :left : :right for c in 1:ncol]   # 1ª coluna à esquerda
    w = [maximum(length, vcat([headers[c]], [r[c] for r in rows])) for c in 1:ncol]
    pad(s, c) = aligns[c] == :left ? rpad(s, w[c]) : lpad(s, w[c])
    fmtrow(r) = join((pad(r[c], c) for c in 1:ncol), "  ")
    total = max(sum(w) + 2 * (ncol - 1), length(titulo) + 1)
    io = IOBuffer()
    println(io, "="^total)
    println(io, " ", titulo)
    println(io, "="^total)
    println(io, fmtrow(headers))
    println(io, "-"^total)
    for r in rows
        println(io, fmtrow(r))
    end
    println(io, "="^total)
    return String(take!(io))
end

#==============================================================================
 2. Sistema, fluxo de potência e Ybus (Float64)
==============================================================================#
println("="^70)
println(" Exportando matrizes e tabelas LaTeX")
println("="^70)

sys = Logging.with_logger(Logging.NullLogger()) do
    build_system(PSIDSystems, "14 Bus Base Case")
end
set_units_base_system!(sys, "SYSTEM_BASE")
Logging.with_logger(Logging.NullLogger()) do
    solve_and_store_power_flow!(ACPowerFlow(), sys)
end

S_base = get_base_power(sys)

# Ybus PURA da rede, em Float64
ybus = Ybus(sys; include_constant_impedance_loads = false)
Y_net = ComplexF64.(Matrix(ybus.data))
bus_order = collect(ybus.axes[1])
n = size(Y_net, 1)
idx_of = Dict(b => i for (i, b) in enumerate(bus_order))
f = idx_of[FAULT_BUS]
buses = Dict(get_number(b) => b for b in get_components(ACBus, sys))

#==============================================================================
 3. Exportar a Ybus como matrizes LaTeX + spy plot
==============================================================================#
println("\n--- Ybus (matrizes LaTeX) ---")

# Para EXIBIÇÃO (item 1 do trabalho): a "matriz de admitâncias nodal" é a Ybus do
# SISTEMA, com as cargas como impedância constante (padrão do PNM, = script 02).
# (A Ybus de rede pura — Y_net, sem cargas — é usada só no cálculo de curto/Zbus.)
Y_sys = ComplexF64.(Matrix(Ybus(sys).data))
G = real.(Y_sys)
B = imag.(Y_sys)
absY = abs.(Y_sys)

write_tex("ybus_G.tex", matrix_to_latex(G; d = 2);
    comment = "Matriz de condutâncias G = Re(Ybus do sistema, c/ cargas Z) [pu, 100 MVA] — 14x14")
write_tex("ybus_B.tex", matrix_to_latex(B; d = 2);
    comment = "Matriz de susceptâncias B = Im(Ybus do sistema, c/ cargas Z) [pu, 100 MVA] — 14x14")
write_tex("ybus_modulo.tex", matrix_to_latex(absY; d = 2);
    comment = "Matriz de módulos |Ybus| do sistema (c/ cargas Z) [pu, 100 MVA] — 14x14")

# Versões ASCII (.txt) das mesmas matrizes
write_txt("ybus_G.txt", matrix_to_txt(G, bus_order,
    "MATRIZ DE CONDUTÂNCIAS [G] (Parte Real da Ybus) - em pu"; d = 2))
write_txt("ybus_B.txt", matrix_to_txt(B, bus_order,
    "MATRIZ DE SUSCEPTÂNCIAS [B] (Parte Imaginária da Ybus) - em pu"; d = 2))
write_txt("ybus_modulo.txt", matrix_to_txt(absY, bus_order,
    "MATRIZ DE ADMITÂNCIAS |Ybus| (módulo) - em pu"; d = 2))

# Spy plot da estrutura de esparsidade
pts_i = Int[]; pts_j = Int[]
for i in 1:n, j in 1:n
    if abs(Y_net[i, j]) > 1e-9
        push!(pts_i, i); push!(pts_j, j)
    end
end
spy = scatter(pts_j, pts_i;
    yflip = true, markershape = :square, markersize = 6, legend = false,
    xticks = (1:n, string.(bus_order)), yticks = (1:n, string.(bus_order)),
    xlabel = "coluna (barra j)", ylabel = "linha (barra i)",
    title = "Estrutura de esparsidade da Ybus (14×14)",
    xlims = (0.5, n + 0.5), ylims = (0.5, n + 0.5), size = (560, 520),
    markercolor = :steelblue)
savefig(spy, joinpath(FIG_DIR, "07_ybus_spy.png"))
println("  ✓ 07_ybus_spy.png (figura)")

#==============================================================================
 4. Cálculo de curto-circuito parametrizado (para as variantes)
==============================================================================#
"""
Curto trifásico na barra `f` pelo método Zbus.
`vpre`        : :flat (1,0 pu) ou :flow (tensões do fluxo)
`with_loads`  : inclui cargas como impedância constante
Retorna (; If, Zth, Vpre, Vpos, Z, contrib)
"""
function short_circuit(; vpre::Symbol, with_loads::Bool)
    Y = copy(Y_net)

    # Tensões pré-falta
    Vpf = if vpre == :flat
        ComplexF64[1.0 + 0.0im for _ in bus_order]
    else
        ComplexF64[get_magnitude(buses[b]) * cis(get_angle(buses[b])) for b in bus_order]
    end

    # Geradores: reatância subtransitória -> shunt p/ terra
    for sg in get_components(ThermalStandard, sys)
        get_available(sg) || continue
        dyn = get_dynamic_injector(sg)
        dyn === nothing && continue
        mach = get_machine(dyn)
        z = (get_R(mach) + im * get_Xd_pp(mach)) * (S_base / get_base_power(dyn))
        Y[idx_of[get_number(get_bus(sg))], idx_of[get_number(get_bus(sg))]] += 1 / z
    end

    # Cargas como impedância constante (admitância = conj(S)/|V|^2)
    if with_loads
        for ld in get_components(StandardLoad, sys)
            get_available(ld) || continue
            i = idx_of[get_number(get_bus(ld))]
            P = get_constant_active_power(ld) + get_current_active_power(ld) +
                get_impedance_active_power(ld)
            Q = get_constant_reactive_power(ld) + get_current_reactive_power(ld) +
                get_impedance_reactive_power(ld)
            Y[i, i] += conj(P + im * Q) / abs2(Vpf[i])
        end
    end

    Z = inv(Y)
    If = Vpf[f] / Z[f, f]
    Vpos = [Vpf[i] - (Z[i, f] / Z[f, f]) * Vpf[f] for i in 1:n]

    # Contribuições dos ramos vizinhos (corrente que cada vizinho injeta na falta)
    contrib = Tuple{Int, ComplexF64}[]
    for j in 1:n
        (j == f || abs(Y_net[f, j]) < 1e-9) && continue
        y_series = -Y_net[f, j]
        I_j = (Vpos[j] - Vpos[f]) * y_series
        push!(contrib, (bus_order[j], I_j))
    end

    return (; If, Zth = Z[f, f], Vpre = Vpf, Vpos, Z, contrib)
end

# As 4 variantes
variants = Dict(
    :flat_noload  => short_circuit(; vpre = :flat, with_loads = false),
    :flat_load    => short_circuit(; vpre = :flat, with_loads = true),
    :flow_noload  => short_circuit(; vpre = :flow, with_loads = false),
    :flow_load    => short_circuit(; vpre = :flow, with_loads = true),
)

# Corrente de base na barra de falta
Vbase_f = get_base_voltage(buses[FAULT_BUS])
Ibase_f = S_base / (sqrt(3) * Vbase_f)   # kA

#==============================================================================
 5. Exportar a Zbus (variante flat, sem carga = referência ANAFAS clássico)
==============================================================================#
println("\n--- Zbus (matrizes LaTeX) ---")
ref = variants[:flat_noload]
Zabs = abs.(ref.Z)

write_tex("zbus_modulo.tex", matrix_to_latex(Zabs; d = 4, zero_dash = false);
    comment = "Matriz de módulos |Zbus| = |inv(Ybus+geradores)| [pu] — variante flat/sem carga — 14x14")

# Coluna do ponto de falta (a relevante p/ o curto na barra 7): módulo e completa
write_tex("zbus_coluna_falta.tex", vector_to_latex(abs.(ref.Z[:, f]); d = 4);
    comment = "Coluna $(FAULT_BUS) da Zbus: |Z_{i,$(FAULT_BUS)}| [pu]. Z_{$(FAULT_BUS),$(FAULT_BUS)} é a imp. de Thévenin no ponto de falta.")

# Versões ASCII (.txt) da Zbus
write_txt("zbus_modulo.txt", matrix_to_txt(Zabs, bus_order,
    "MATRIZ DE IMPEDÂNCIAS |Zbus| (módulo) - em pu [flat/sem carga]"; d = 4, w = 8))
write_txt("zbus_coluna_falta.txt", vector_to_txt(abs.(ref.Z[:, f]), bus_order,
    "COLUNA $(FAULT_BUS) DA ZBUS |Z_i,$(FAULT_BUS)| (pu) - Z_$(FAULT_BUS),$(FAULT_BUS) = Thevenin"; d = 4))

#==============================================================================
 6. Vetores de tensão (pré-falta e durante a falta) em LaTeX
==============================================================================#
println("\n--- Vetores de tensão (LaTeX) ---")
write_tex("vetor_vpre_flow.tex", vector_to_latex(abs.(variants[:flow_noload].Vpre); d = 4);
    comment = "Vetor de tensões pré-falta |V0| [pu] (do fluxo de potência).")
write_tex("vetor_vfault_flat.tex", vector_to_latex(abs.(ref.Vpos); d = 4);
    comment = "Vetor de tensões durante a falta |V| [pu] — variante flat/sem carga.")

# Versões ASCII (.txt) dos vetores de tensão
write_txt("vetor_vpre_flow.txt", vector_to_txt(abs.(variants[:flow_noload].Vpre), bus_order,
    "TENSÕES PRÉ-FALTA |V0| (pu, do fluxo de potência)"; d = 4))
write_txt("vetor_vfault_flat.txt", vector_to_txt(abs.(ref.Vpos), bus_order,
    "TENSÕES DURANTE A FALTA |V| (pu, variante flat/sem carga)"; d = 4))

#==============================================================================
 7. Tabelas comparativas (Zbus x PSD.jl x ANAFAS) com erros %
==============================================================================#
println("\n--- Tabelas comparativas (LaTeX) ---")

# Valores do PSD.jl (do script 04) para a tabela de corrente
psid_If_kA = 23.65   # Caso A (falta quase franca, permanente) — ver 04_summary.csv

#--- Dados do relatório ANAFAS (curto trifásico franco na barra 7) — 2026-06-08 ---
# ANAFAS 8.1; tensão pré-falta do .pwf (≈0,984 na barra 7); cargas e shunt incluídos.
# Tensões: barras 1,6,11,12,13 NÃO constam no relatório de estudo individual.
const ANAFAS_If_pu = 6.426
const ANAFAS_Vpre7 = 0.984
const ANAFAS_V = Dict(2=>0.840, 3=>0.813, 4=>0.596, 5=>0.660, 7=>0.000,
                      8=>0.280, 9=>0.213, 10=>0.279, 14=>0.347)   # módulo pu
const ANAFAS_CONTRIB = Dict(4=>2.915, 8=>1.590, 9=>1.936)        # módulo pu p/ barra 7

# Erro percentual com o ANAFAS como referência (conv. do artigo IFG)
relerr(julia, ref) = (julia - ref) / ref * 100
errstr(e) = string(e >= 0 ? "+" : "-", round(abs(e), digits = 1), "\\%")

# Diagnóstico no terminal: qual variante fica mais próxima do ANAFAS
println("\n  [comparação com ANAFAS] If(ANAFAS) = ", ANAFAS_If_pu, " pu = ",
        round(ANAFAS_If_pu * Ibase_f, digits = 2), " kA")
for (k, lbl) in [(:flat_noload, "flat/sem carga"), (:flat_load, "flat/carga"),
                 (:flow_noload, "fluxo/sem carga"), (:flow_load, "fluxo/carga")]
    r = variants[k]
    @printf("    %-16s If=%.3f pu  erro=%+.1f%%\n", lbl, abs(r.If),
            relerr(abs(r.If), ANAFAS_If_pu))
end
# Diagnóstico das contribuições por variante (qual divisão entre ramos bate melhor)
println("\n  [contribuições por variante vs ANAFAS] (4→7, 8→7, 9→7) pu:")
@printf("    %-16s 4→7=%.3f 8→7=%.3f 9→7=%.3f\n", "ANAFAS",
        ANAFAS_CONTRIB[4], ANAFAS_CONTRIB[8], ANAFAS_CONTRIB[9])
for (k, lbl) in [(:flat_noload, "flat/sem carga"), (:flat_load, "flat/carga"),
                 (:flow_noload, "fluxo/sem carga"), (:flow_load, "fluxo/carga")]
    cd = Dict(b => abs(I) for (b, I) in variants[k].contrib)
    tot = sum(abs(relerr(get(cd, b, 0.0), ANAFAS_CONTRIB[b])) for b in (4, 8, 9))
    @printf("    %-16s 4→7=%.3f 8→7=%.3f 9→7=%.3f  |Σ|err=%.1f%%\n", lbl,
            get(cd, 4, 0.0), get(cd, 8, 0.0), get(cd, 9, 0.0), tot)
end

# --- Tabela 1: corrente de falta e nível de curto na barra 7 (com erro) ---
io = IOBuffer()
println(io, "\\begin{tabular}{lcccc}")
println(io, "\\toprule")
println(io, "Abordagem & \$|I_f|\$ [pu] & \$|I_f|\$ [kA] & SCC [MVA] & \$\\varepsilon\$ vs ANAFAS \\\\")
println(io, "\\midrule")
for (k, lbl) in [(:flat_noload, "Zbus (flat, sem carga)"),
                 (:flat_load,   "Zbus (flat, carga Z)"),
                 (:flow_noload, "Zbus (fluxo, sem carga)"),
                 (:flow_load,   "Zbus (fluxo, carga Z)")]
    r = variants[k]
    println(io, @sprintf("%s & %.3f & %.2f & %.1f & %s \\\\", lbl,
        abs(r.If), abs(r.If) * Ibase_f, abs(r.If) * abs(r.Vpre[f]) * S_base,
        errstr(relerr(abs(r.If), ANAFAS_If_pu))))
end
println(io, @sprintf("PSD.jl (dinâmico) & %.3f & %.2f & -- & %s \\\\",
    psid_If_kA / Ibase_f, psid_If_kA, errstr(relerr(psid_If_kA / Ibase_f, ANAFAS_If_pu))))
println(io, @sprintf("\\textbf{ANAFAS} (ref.) & %.3f & %.2f & %.1f & -- \\\\",
    ANAFAS_If_pu, ANAFAS_If_pu * Ibase_f, ANAFAS_If_pu * ANAFAS_Vpre7 * S_base))
println(io, "\\bottomrule")
print(io, "\\end{tabular}")
write_tex("tab_corrente_falta.tex", String(take!(io));
    comment = "Corrente de curto trifásico na barra 7. ANAFAS = referência do erro ε.\nMenor erro: variante flat/sem carga (clássica, comparável ao ANAFAS clássico).")

# --- Tabela 2: tensões durante a falta (com ANAFAS e erro) ---
io = IOBuffer()
println(io, "\\begin{tabular}{cccccc}")
println(io, "\\toprule")
println(io, "Barra & \$|V_0|\$ & Zbus flat & Zbus fluxo & ANAFAS & \$\\varepsilon\$ (flat) \\\\")
println(io, "\\midrule")
for i in 1:n
    b = bus_order[i]
    vflat = abs(variants[:flat_noload].Vpos[i])
    vflow = abs(variants[:flow_noload].Vpos[i])
    if haskey(ANAFAS_V, b)
        astr = @sprintf("%.3f", ANAFAS_V[b])
        estr = b == FAULT_BUS ? "--" : errstr(relerr(vflat, ANAFAS_V[b]))
    else
        astr = "n/d"; estr = "--"
    end
    println(io, @sprintf("%d & %.4f & %.4f & %.4f & %s & %s \\\\",
        b, abs(variants[:flow_noload].Vpre[i]), vflat, vflow, astr, estr))
end
println(io, "\\bottomrule")
print(io, "\\end{tabular}")
write_tex("tab_tensoes_falta.tex", String(take!(io));
    comment = "Tensões durante o curto na barra 7 (módulo, pu). ε = erro flat vs ANAFAS.\nANAFAS não reporta as barras ligadas à referência (1,6,11,12,13) -> n/d.")

# --- Tabela 3: contribuições dos ramos (Zbus flat x ANAFAS, com erro) ---
# Usa a variante FLAT/sem carga: como o ANAFAS adota tensão pré-falta ≈ flat, é a
# que melhor reproduz a DIVISÃO de corrente entre os ramos (erro |Σ| ≈ 9% vs ≈24%
# da variante fluxo). Correntes são fasores; o Total é o módulo de If.
refc = variants[:flat_noload]
Isum = sum(I for (_, I) in refc.contrib)
io = IOBuffer()
println(io, "\\begin{tabular}{cccccc}")
println(io, "\\toprule")
println(io, "Ramo & Zbus [pu] & ANAFAS [pu] & \$\\varepsilon\$ & Zbus [kA] & ANAFAS [kA] \\\\")
println(io, "\\midrule")
for (busj, Ij) in sort(refc.contrib; by = x -> x[1])
    jm = abs(Ij)
    if haskey(ANAFAS_CONTRIB, busj)
        am = ANAFAS_CONTRIB[busj]
        println(io, @sprintf("%d \$\\to\$ %d & %.3f & %.3f & %s & %.2f & %.2f \\\\",
            busj, FAULT_BUS, jm, am, errstr(relerr(jm, am)), jm * Ibase_f, am * Ibase_f))
    end
end
println(io, @sprintf("\\midrule Total & %.3f & %.3f & %s & %.2f & %.2f \\\\",
    abs(refc.If), ANAFAS_If_pu, errstr(relerr(abs(refc.If), ANAFAS_If_pu)),
    abs(refc.If) * Ibase_f, ANAFAS_If_pu * Ibase_f))
println(io, "\\bottomrule")
print(io, "\\end{tabular}")
write_tex("tab_contribuicoes.tex", String(take!(io));
    comment = "Contribuições p/ a falta na barra 7. Zbus = variante flat/sem carga (a mais\nfiel ao ANAFAS, que usa tensão pré-falta ≈ flat). Correntes são fasores.")

println("  [contribuições flat] soma fasorial = ", round(abs(Isum), digits = 4),
        " pu | If = ", round(abs(refc.If), digits = 4),
        " pu (pequeno desbalanço dos taps sob flat-start)")

#------------------------------------------------------------------------------
# Versões ASCII (.txt) das 3 tabelas comparativas
#------------------------------------------------------------------------------
# Tabela 1 - corrente
rows1 = Vector{String}[]
for (k, lbl) in [(:flat_noload, "Zbus (flat, sem carga)"),
                 (:flat_load,   "Zbus (flat, carga Z)"),
                 (:flow_noload, "Zbus (fluxo, sem carga)"),
                 (:flow_load,   "Zbus (fluxo, carga Z)")]
    r = variants[k]
    push!(rows1, [lbl, fmtn(abs(r.If); d = 3), fmtn(abs(r.If) * Ibase_f; d = 2),
                  fmtn(abs(r.If) * abs(r.Vpre[f]) * S_base; d = 1),
                  errpct(relerr(abs(r.If), ANAFAS_If_pu))])
end
push!(rows1, ["PSD.jl (dinâmico)", fmtn(psid_If_kA / Ibase_f; d = 3),
              fmtn(psid_If_kA; d = 2), "--", errpct(relerr(psid_If_kA / Ibase_f, ANAFAS_If_pu))])
push!(rows1, ["ANAFAS (ref.)", fmtn(ANAFAS_If_pu; d = 3), fmtn(ANAFAS_If_pu * Ibase_f; d = 2),
              fmtn(ANAFAS_If_pu * ANAFAS_Vpre7 * S_base; d = 1), "--"])
write_txt("tab_corrente_falta.txt", table_to_txt(
    "CORRENTE DE CURTO TRIFASICO NA BARRA 7 (ANAFAS = referencia do erro)",
    ["Abordagem", "|If| [pu]", "|If| [kA]", "SCC [MVA]", "erro vs ANAFAS"], rows1))

# Tabela 2 - tensões
rows2 = Vector{String}[]
for i in 1:n
    b = bus_order[i]
    vflat = abs(variants[:flat_noload].Vpos[i])
    vflow = abs(variants[:flow_noload].Vpos[i])
    astr = haskey(ANAFAS_V, b) ? fmtn(ANAFAS_V[b]; d = 3) : "n/d"
    estr = (haskey(ANAFAS_V, b) && b != FAULT_BUS) ? errpct(relerr(vflat, ANAFAS_V[b])) : "--"
    push!(rows2, [string(b), fmtn(abs(variants[:flow_noload].Vpre[i]); d = 4),
                  fmtn(vflat; d = 4), fmtn(vflow; d = 4), astr, estr])
end
write_txt("tab_tensoes_falta.txt", table_to_txt(
    "TENSOES DURANTE A FALTA NA BARRA 7 (modulo, pu); erro = flat vs ANAFAS",
    ["Barra", "|V0|", "Zbus flat", "Zbus fluxo", "ANAFAS", "erro(flat)"], rows2))

# Tabela 3 - contribuições
rows3 = Vector{String}[]
for (busj, Ij) in sort(refc.contrib; by = x -> x[1])
    haskey(ANAFAS_CONTRIB, busj) || continue
    jm = abs(Ij); am = ANAFAS_CONTRIB[busj]
    push!(rows3, [string(busj) * " -> " * string(FAULT_BUS), fmtn(jm; d = 3),
                  fmtn(am; d = 3), errpct(relerr(jm, am)),
                  fmtn(jm * Ibase_f; d = 2), fmtn(am * Ibase_f; d = 2)])
end
push!(rows3, ["Total", fmtn(abs(refc.If); d = 3), fmtn(ANAFAS_If_pu; d = 3),
              errpct(relerr(abs(refc.If), ANAFAS_If_pu)),
              fmtn(abs(refc.If) * Ibase_f; d = 2), fmtn(ANAFAS_If_pu * Ibase_f; d = 2)])
write_txt("tab_contribuicoes.txt", table_to_txt(
    "CONTRIBUICOES DE CORRENTE PARA A FALTA NA BARRA 7 (Zbus flat x ANAFAS)",
    ["Ramo", "Zbus [pu]", "ANAFAS [pu]", "erro", "Zbus [kA]", "ANAFAS [kA]"], rows3))

#==============================================================================
 8. Resumo das variantes no terminal
==============================================================================#
println("\n", "="^70)
println(" RESUMO DAS VARIANTES (corrente de falta na barra ", FAULT_BUS, ")")
println("="^70)
@printf("  %-26s %8s %8s %9s\n", "variante", "|If|pu", "|If|kA", "Zth")
for (k, label) in [
    (:flat_noload, "flat / sem carga"),
    (:flat_load,   "flat / carga Z"),
    (:flow_noload, "fluxo / sem carga"),
    (:flow_load,   "fluxo / carga Z"),
]
    r = variants[k]
    @printf("  %-26s %8.3f %8.2f %9.4f\n",
        label, abs(r.If), abs(r.If) * Ibase_f, abs(r.Zth))
end
println("\n  Corrente de base na barra ", FAULT_BUS, ": ", round(Ibase_f, digits = 4), " kA")
println("  (variante 'flat / sem carga' = referência p/ ANAFAS clássico)")

println("\n", "="^70)
println(" Arquivos LaTeX em data/latex/ :")
for fn in sort(readdir(LATEX_DIR))
    println("   - ", fn)
end
println(" Figura: data/figures/07_ybus_spy.png")
println("="^70)
