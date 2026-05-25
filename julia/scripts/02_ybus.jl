#==============================================================================
 Script 02 - Matriz de admitâncias nodal (Ybus) do IEEE 14 barras
 ------------------------------------------------------------------------------
 Monta a matriz Ybus da rede (linhas + transformadores + susceptâncias shunt)
 usando PowerNetworkMatrices.jl, analisa suas propriedades estruturais e
 exporta a matriz completa (parte real e imaginária) para CSV.

 Esta é a "matriz de admitâncias nodal" pedida no item 1 do trabalho. O uso
 dela para o cálculo de curto-circuito é feito no script 03.
==============================================================================#

using PowerSystems
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using LinearAlgebra
using SparseArrays
using DataFrames
using CSV
using Printf

const PSY = PowerSystems
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULTS_DIR = joinpath(ROOT, "data", "results")
mkpath(RESULTS_DIR)

#------------------------------------------------------------------------------
# 1. Carregar sistema e construir Ybus
#------------------------------------------------------------------------------
println("="^70)
println(" Construindo a matriz Ybus do IEEE 14 barras")
println("="^70)

sys = build_system(PSIDSystems, "14 Bus Base Case")
set_units_base_system!(sys, "SYSTEM_BASE")

ybus = Ybus(sys)
Y = Matrix(ybus.data)            # densa, complexa
bus_order = ybus.axes[1]         # ordem das barras na matriz

n = size(Y, 1)
println("\nDimensão da matriz: ", n, " x ", n)
println("Ordem das barras (linhas/colunas): ", bus_order)

#------------------------------------------------------------------------------
# 2. Propriedades estruturais
#------------------------------------------------------------------------------
nnz_count = count(!iszero, Y)
sparsity  = 100 * (1 - nnz_count / (n^2))
is_sym    = isapprox(Y, transpose(Y); atol = 1e-10)

println("\n--- Propriedades ---")
@printf("  Elementos não-nulos : %d de %d\n", nnz_count, n^2)
@printf("  Esparsidade         : %.1f %%\n", sparsity)
println("  Simétrica           : ", is_sym)

#------------------------------------------------------------------------------
# 3. Exibição formatada (módulo e ângulo dos elementos não-nulos)
#------------------------------------------------------------------------------
println("\n--- Elementos não-nulos da Ybus (i, j, G, B, |Y|, ∠Y°) ---")
df_elem = DataFrame(
    i = Int[], j = Int[],
    bus_i = Int[], bus_j = Int[],
    G = Float64[], B = Float64[],
    mag = Float64[], ang_deg = Float64[],
)
for i in 1:n, j in 1:n
    y = Y[i, j]
    if !iszero(y)
        push!(df_elem, (
            i, j, bus_order[i], bus_order[j],
            real(y), imag(y), abs(y), rad2deg(angle(y)),
        ))
    end
end
show(first(df_elem, 20), allrows = true); println()
println("  ... (", nrow(df_elem), " elementos não-nulos no total)")

#------------------------------------------------------------------------------
# 4. Exportar Ybus completa (parte real G e parte imaginária B)
#------------------------------------------------------------------------------
col_names = ["bus_$(b)" for b in bus_order]

df_G = DataFrame(real.(Y), col_names); insertcols!(df_G, 1, :bus => bus_order)
df_B = DataFrame(imag.(Y), col_names); insertcols!(df_B, 1, :bus => bus_order)

CSV.write(joinpath(RESULTS_DIR, "02_ybus_G_real.csv"), df_G)
CSV.write(joinpath(RESULTS_DIR, "02_ybus_B_imag.csv"), df_B)
CSV.write(joinpath(RESULTS_DIR, "02_ybus_elements.csv"), df_elem)

# Também salva em formato binário Julia para reuso exato pelos próximos scripts
import Serialization
Serialization.serialize(joinpath(RESULTS_DIR, "02_ybus.jls"), (Y = Y, bus_order = collect(bus_order)))

println("\n", "="^70)
println(" Ybus exportada:")
println("   - 02_ybus_G_real.csv   (condutâncias)")
println("   - 02_ybus_B_imag.csv   (susceptâncias)")
println("   - 02_ybus_elements.csv (lista de não-nulos)")
println("   - 02_ybus.jls          (binário p/ próximos scripts)")
println("="^70)
