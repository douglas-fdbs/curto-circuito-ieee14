# Explicação dos scripts Julia — `julia/scripts/`

> Guia didático, **trecho a trecho**, de cada script do estudo de curto-circuito.
> Pensado para quem está aprendendo Julia e/ou quer entender o código por partes.
>
> - Para aprender a **linguagem do zero**, veja [others/GUIA_JULIA.md](others/GUIA_JULIA.md).
>   Este documento aqui é o complemento: foca no **que cada script faz e por quê**.
> - Para entender os **arquivos de saída** (CSVs), veja
>   [data/results/EXPLICACAO_RESULTADOS.md](data/results/EXPLICACAO_RESULTADOS.md).

## Como ler este documento

Cada script tem uma seção com:
1. **O que faz** (resumo de uma frase).
2. **Entradas / saídas** (de onde lê, o que grava).
3. **Trecho a trecho**: o código em blocos, com a explicação da engenharia
   *e* dos recursos de Julia usados.

Os idiomas de Julia que se repetem em **todos** os scripts estão explicados uma
única vez no [Glossário](#glossário-de-julia-o-que-se-repete-em-todo-script)
abaixo — depois disso, só comento o que é novo.

## A esteira (pipeline) dos scripts

```
01_load_system   → carrega o IEEE 14 e inventaria componentes (CSVs 01_*)
02_ybus          → monta a matriz Ybus (CSVs 02_*, binário .jls)
03_shortcircuit  → curto estático na barra 7 pelo método Zbus (CSVs 03_*)
04_dynamic       → curto no tempo com PowerSimulationsDynamics (CSVs 04_*, figuras)
   src/SCUtils   → módulo com as funções reaproveitadas por 05 e 06
05_scenarios     → varia carga/geração e recalcula o curto (CSV 05_*, figuras)
06_solar_pv      → adiciona usina fotovoltaica e compara (CSVs 06_*, figuras)
07_export_latex  → exporta matrizes/tabelas em LaTeX e ASCII p/ o artigo
```

Cada script é **independente**: carrega o sistema do zero. Isso é proposital —
você pode rodar qualquer um isoladamente. O preço é recarregar o caso toda vez
(~1–2 min no primeiro `using`).

### Como rodar

```bash
export PATH="$HOME/.juliaup/bin:$PATH"
cd julia
julia --project=. scripts/01_load_system.jl    # troque o número conforme o script
```

O `--project=.` diz ao Julia para usar o ambiente isolado do projeto
(`Project.toml`/`Manifest.toml`), com as versões exatas dos pacotes.

---

## Glossário de Julia (o que se repete em todo script)

Estes padrões aparecem em quase todos os arquivos. Entenda-os uma vez:

| Trecho | O que é / significa |
|---|---|
| `using PowerSystems` | Carrega um pacote e traz suas funções para o escopo (pode chamar `get_name(...)` direto). |
| `import Logging` | Carrega o pacote mas **sem** trazer os nomes — você usa `Logging.NullLogger()`. Mais conservador que `using`. |
| `const PSY = PowerSystems` | Cria um **apelido** constante. `const` aqui evita que o nome mude de tipo (ajuda performance e legibilidade). |
| `@__DIR__` | Macro que devolve a pasta **deste arquivo** `.jl`. Base para montar caminhos que funcionam de qualquer lugar. |
| `joinpath(a, b)` | Junta partes de caminho com a barra certa do sistema operacional (`a/b`). |
| `normpath(...)` | Resolve `..` e `.` no caminho (normaliza). |
| `mkpath(dir)` | Cria a pasta (e as intermediárias) se não existirem. Não dá erro se já existe. |
| `"="^70` | **Repetição de string**: 70 sinais de igual. Usado para imprimir linhas separadoras. |
| `println("a", b, "c")` | Imprime os argumentos concatenados + quebra de linha. |
| `"texto $(expr)"` | **Interpolação**: insere o valor de `expr` dentro da string. |
| `@printf("%.4f\n", x)` | Impressão formatada estilo C (4 casas decimais). Vem do pacote `Printf`. |
| `get_name(x)`, `get_number(x)`… | Convenção do **PowerSystems.jl**: todo dado de um componente é lido por uma função `get_*`. |
| `df = DataFrame(col = Tipo[], ...)` | Cria uma tabela vazia com colunas tipadas. `Int[]` = vetor vazio de inteiros. |
| `push!(df, (a, b, c))` | Acrescenta **uma linha** à tabela. O `!` no nome avisa que a função **modifica** seu argumento (convenção de Julia). |
| `[f(x) for x in coll]` | **List comprehension**: constrói um vetor aplicando `f` a cada item. |
| `Dict(k => v for ...)` | Constrói um dicionário (mapa chave→valor) por comprehension. |
| `real.(Y)`, `abs.(v)` | O **ponto** é *broadcasting*: aplica a função elemento a elemento em toda a matriz/vetor. |
| `im` | A unidade imaginária. `2 + 3im` é um número complexo. |
| `(; a, b, c)` | **NamedTuple**: agrupa valores com nome. `r.a` acessa o campo. Forma leve de "retornar várias coisas". |
| `function f(; x, y)` | O `;` na assinatura torna `x` e `y` **argumentos nomeados** (keyword): chama-se `f(x=1, y=2)`. |
| `cond ? a : b` | Operador ternário: vale `a` se `cond` for verdadeiro, senão `b`. |
| `CSV.write(caminho, df)` | Grava a tabela em arquivo CSV. |

> **Por que cada script repete `const ROOT = ...` e `mkpath(RESULTS_DIR)`?**
> Para ser autossuficiente: monta os caminhos relativos à raiz do projeto
> (subindo dois níveis a partir de `julia/scripts/`) e garante que a pasta de
> saída exista antes de gravar.

---

## `src/SCUtils.jl` — o módulo compartilhado

> **O que faz:** reúne as funções reaproveitadas pelos scripts 05 e 06
> (carregar sistema, resolver fluxo, escalar carga, tirar gerador, e o cálculo
> de curto por Zbus). Ler este módulo **antes** do 05/06 facilita muito.

Explico ele primeiro porque os scripts 05 e 06 dependem dele.

### Cabeçalho: o que é um módulo

```julia
module SCUtils
using PowerSystems
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using PowerFlows
using LinearAlgebra
import Logging

export build_14bus, solve_pf!, load_PQ, scale_loads!, take_generator_offline!,
       zbus_short_circuit, base_current_kA
```

- `module SCUtils ... end` cria um **namespace** próprio. Tudo que é definido
  dentro fica "encapsulado".
- `export` lista os nomes que ficam **visíveis** para quem fizer `using .SCUtils`.
  O que não está aqui continua acessível, mas só com prefixo (`SCUtils.algo`).
- O `.` em `using .SCUtils` (lá no script 05) significa "módulo local", carregado
  via `include`, e não um pacote instalado.

### `build_14bus` — carregar o sistema sem poluir o terminal

```julia
function build_14bus()
    sys = Logging.with_logger(Logging.NullLogger()) do
        build_system(PSIDSystems, "14 Bus Base Case")
    end
    set_units_base_system!(sys, "SYSTEM_BASE")
    return sys
end
```

- `build_system(PSIDSystems, "14 Bus Base Case")` baixa/monta o sistema IEEE 14
  com dados dinâmicos, do PowerSystemCaseBuilder.
- O **bloco `do ... end`** é um recurso elegante de Julia: tudo dentro dele roda
  "dentro" de `with_logger(NullLogger())`, ou seja, com o log **silenciado**
  (o caso emite warnings inofensivos de validação de faixa). É açúcar sintático
  para passar uma função anônima como primeiro argumento.
- `set_units_base_system!(sys, "SYSTEM_BASE")` fixa a base de unidades como
  **pu na base do sistema (100 MVA)** — essencial para as contas baterem.

### `solve_pf!` — fluxo de potência

```julia
function solve_pf!(sys)
    conv = Logging.with_logger(Logging.NullLogger()) do
        solve_and_store_power_flow!(ACPowerFlow(), sys)
    end
    conv || @warn "Fluxo de potência não convergiu"
    return conv
end
```

- `solve_and_store_power_flow!` resolve o fluxo AC e **guarda as tensões de volta
  no sistema** (por isso o `!` no nome: modifica `sys`).
- `conv || @warn ...` é um idioma comum: se `conv` for `true`, o `||` (ou-lógico)
  já "curto-circuita" e não avalia o lado direito; se for `false`, dispara o
  warning. Equivale a `if !conv; @warn ...; end`.

### `load_PQ` — multiple dispatch na prática

```julia
function load_PQ(ld::StandardLoad)
    P = get_constant_active_power(ld) + get_current_active_power(ld) +
        get_impedance_active_power(ld)
    Q = ...
    return P, Q
end
load_PQ(ld) = (get_active_power(ld), get_reactive_power(ld))
```

- Há **duas definições** da mesma função `load_PQ`. Julia escolhe qual usar pelo
  **tipo do argumento** — isso é *multiple dispatch*, o coração da linguagem.
- A primeira (`ld::StandardLoad`) trata o modelo **ZIP**, somando as três parcelas
  (potência constante + corrente constante + impedância constante).
- A segunda (sem anotação de tipo) é o caso **genérico** para qualquer outro tipo
  de carga. É o "fallback".
- `return P, Q` devolve uma **tupla** de dois valores.

### `scale_loads!` — escalar a demanda

```julia
function scale_loads!(sys, factor)
    for ld in get_components(StandardLoad, sys)
        set_constant_active_power!(ld, get_constant_active_power(ld) * factor)
        ... (as 6 componentes ZIP) ...
    end
    return sys
end
```

- `get_components(StandardLoad, sys)` devolve **todas** as cargas do tipo
  `StandardLoad`. O `for ld in ...` itera sobre elas.
- Para cada uma, multiplica as 6 componentes ZIP (P e Q × constante/corrente/
  impedância) pelo `factor` (ex.: `0.6` = carga leve). Os `set_*!` gravam de volta.

### `take_generator_offline!` — tirar uma máquina de serviço

```julia
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
```

- Acha o gerador na barra `bus_num`, marca como indisponível (`set_available!(g, false)`).
- A linha `get_bustype(b) == ACBusTypes.PV && set_bustype!(...)` usa o mesmo
  idioma do `||`, mas com `&&`: **só** converte a barra de PV para PQ se ela
  era PV (sem o gerador, ela deixa de controlar tensão).

### `zbus_short_circuit` — o cálculo de curto (núcleo do trabalho)

A docstring (texto entre `"""..."""` antes da função) documenta a assinatura:

```julia
function zbus_short_circuit(sys; fault_bus, z_fault = 0.0 + 0.0im, include_loads = false)
```

- Tudo após o `;` é **keyword**: `fault_bus` é obrigatório, `z_fault` e
  `include_loads` têm valores padrão.

Passo a passo do corpo:

```julia
ybus = Ybus(sys; include_constant_impedance_loads = false)
Y = Matrix(ybus.data)
bus_order = collect(ybus.axes[1])
n = size(Y, 1)
idx_of = Dict(b => i for (i, b) in enumerate(bus_order))
f = idx_of[fault_bus]
```

- **`include_constant_impedance_loads = false`** é a decisão crucial: monta a Ybus
  **pura da rede** (só linhas + trafos + shunts), *sem* embutir a impedância das
  cargas. As cargas só entram depois, opcionalmente, para não contá-las duas vezes.
- `bus_order` é a ordem das barras na matriz (pode não ser 1,2,...,14).
- `idx_of` é um **dicionário** "número da barra → índice na matriz". `enumerate`
  dá pares `(i, b)` = (posição, valor). `f` é o índice da barra de falta.

```julia
V_pf = ComplexF64[get_magnitude(buses[b]) * cis(get_angle(buses[b])) for b in bus_order]
```

- Monta o vetor de **tensões pré-falta** como números complexos.
  `cis(θ) = cos θ + i·sen θ = e^{iθ}`. Então `|V|·cis(ângulo)` é o fasor da tensão.
- `ComplexF64[ ... ]` força o vetor a ser de complexos de 64 bits.

```julia
for sg in get_components(ThermalStandard, sys)
    get_available(sg) || continue
    dyn = get_dynamic_injector(sg)
    dyn === nothing && continue
    mach = get_machine(dyn)
    z_sys = (get_R(mach) + im * get_Xd_pp(mach)) * (S_base / get_base_power(dyn))
    i = idx_of[get_number(get_bus(sg))]
    Y[i, i] += 1 / z_sys
end
```

- Para cada gerador disponível, pega a **reatância subtransitória X″d** (`get_Xd_pp`)
  e a resistência da máquina, formando a impedância `z = R + jX″d`.
- `* (S_base / get_base_power(dyn))` **converte** essa impedância da base da
  máquina para a base do sistema (100 MVA).
- `get_available(sg) || continue` pula geradores fora de serviço; `dyn === nothing
  && continue` pula quem não tem modelo dinâmico. `===` é igualdade **idêntica**
  (mesmo objeto / `nothing`).
- `Y[i, i] += 1 / z_sys` soma a **admitância** do gerador (1/z) na diagonal da
  barra dele — é o gerador modelado como fonte atrás de X″d, aterrada.

```julia
if include_loads
    for ld in get_components(StandardLoad, sys)
        ...
        Y[i, i] += conj(P + im * Q) / abs2(V_pf[i])
    end
end
```

- Variante opcional: adiciona cada carga como **impedância constante**. A admitância
  de uma carga S = P+jQ sob tensão V é `y = conj(S)/|V|²`. `abs2(z) = |z|²`
  (evita a raiz quadrada, é mais rápido).

```julia
Z = inv(Y)
If = V_pf[f] / (Z[f, f] + z_fault)
Vpos = [V_pf[i] - (Z[i, f] / (Z[f, f] + z_fault)) * V_pf[f] for i in 1:n]
```

- **`Z = inv(Y)`** inverte a Ybus → matriz de impedâncias **Zbus**.
- **`If = V_pré(f) / (Z[f,f] + z_falta)`** é a corrente de curto (Thévenin no nó
  de falta). `Z[f,f]` é a impedância de Thévenin vista da barra de falta.
- **`Vpos[i]`** aplica o teorema da superposição: a tensão em cada barra durante
  a falta. Para falta franca (`z_fault=0`) na própria barra `f`, `Vpos[f]→0`.

```julia
return (; If, Zth = Z[f, f], Vpre = V_pf, Vpos, bus_order, Ibase_kA, scc_mva, idx_of)
```

- Devolve um **NamedTuple** com tudo que os scripts 05/06 precisam. Note `If`
  sozinho: `(; If)` é atalho para `(If = If)`.

---

## `01_load_system.jl` — carregar e inventariar o sistema

> **O que faz:** carrega o IEEE 14 e lista todos os componentes (barras, linhas,
> trafos, geradores, injetores dinâmicos, cargas), exibindo no terminal e
> gravando um CSV por categoria.
> **Saídas:** `data/results/01_*.csv`.

### Carregar o sistema

```julia
sys = build_system(PSIDSystems, "14 Bus Base Case")
set_units_base_system!(sys, "SYSTEM_BASE")
println(sys)
```

- `PSIDSystems` é a coleção de casos *com dados dinâmicos* (a versão que tem
  máquinas, AVR etc., necessária para o script 04). `println(sys)` imprime um
  resumo do sistema.

### Inventário de barras (padrão que se repete)

```julia
buses = sort(collect(get_components(ACBus, sys)); by = get_number)

df_bus = DataFrame(number = Int[], name = String[], bustype = String[],
                   base_voltage = Float64[], vm_pu = Float64[], va_rad = Float64[])
for b in buses
    push!(df_bus, (get_number(b), get_name(b), string(get_bustype(b)),
                   get_base_voltage(b), get_magnitude(b), get_angle(b)))
end
show(df_bus, allrows = true); println()
CSV.write(joinpath(RESULTS_DIR, "01_buses.csv"), df_bus)
```

Esse é o **molde** repetido para cada categoria:
1. `get_components(Tipo, sys)` → pega os componentes; `collect` transforma em vetor;
   `sort(...; by = get_number)` ordena pelo número da barra.
2. Cria um `DataFrame` vazio com colunas tipadas.
3. `for ... push!(df, (...))` preenche linha a linha.
4. `string(get_bustype(b))` converte o enum (REF/PV/PQ) em texto.
5. `show(df, allrows = true)` mostra **todas** as linhas no terminal (sem cortar).
6. `CSV.write(...)` grava.

> Se você entender este bloco, entende as seções 3–7 do script: são o mesmo molde
> para `Line`, `Transformer2W`/`TapTransformer`, geradores, injetores e cargas.

### Linhas: lendo o arco e o shunt

```julia
arc = get_arc(l)
push!(df_line, (get_name(l), get_number(get_from(arc)), get_number(get_to(arc)),
                get_r(l), get_x(l), get_b(l).from + get_b(l).to, get_rating(l)))
```

- Um `Line` tem um **arco** (`get_arc`) com as barras de origem (`get_from`) e
  destino (`get_to`).
- `get_b(l)` devolve um objeto com dois campos (`.from` e `.to`) — a susceptância
  shunt do modelo π é a soma das duas pontas.

### Transformadores: iterando sobre tipos

```julia
for T in (Transformer2W, TapTransformer)
    for t in get_components(T, sys)
        ...
    end
end
```

- O laço externo itera sobre **tipos** (`Transformer2W` e `TapTransformer` são
  valores de primeira classe em Julia — dá para guardar tipos numa tupla e
  iterar). Útil para tratar várias categorias com o mesmo código.

### Cargas: o detalhe do modelo ZIP

```julia
load_P(ld::StandardLoad) = get_constant_active_power(ld) +
                           get_current_active_power(ld) +
                           get_impedance_active_power(ld)
load_P(ld) = get_active_power(ld)
```

- Mesmo *multiple dispatch* do SCUtils: `StandardLoad` (ZIP) soma três parcelas;
  os demais tipos usam `get_active_power` direto. Definição em **uma linha**
  (`f(x) = corpo`) é a forma curta de declarar função em Julia.

### Resumo final

A seção 8 só imprime contagens (`nrow(df_bus)` = número de linhas da tabela) e a
base de potência/frequência. Nada novo de Julia.

---

## `02_ybus.jl` — a matriz de admitâncias nodal

> **O que faz:** monta a Ybus (com PowerNetworkMatrices), mede suas propriedades
> (esparsidade, simetria) e exporta em CSV (G e B), em lista de não-nulos e em
> binário `.jls`.
> **Saídas:** `data/results/02_ybus_*.csv`, `02_ybus.jls`.

### Construir a Ybus

```julia
ybus = Ybus(sys)
Y = Matrix(ybus.data)        # densa, complexa
bus_order = ybus.axes[1]     # ordem das barras na matriz
n = size(Y, 1)
```

- `Ybus(sys)` constrói a matriz. Aqui **sem** o argumento `include_constant_...`,
  ou seja, é a Ybus **do sistema** (com as cargas ZIP embutidas) — a "matriz de
  admitâncias nodal" do item 1 do trabalho.
- `ybus.data` é esparsa; `Matrix(...)` a converte para **densa** (cheia).
- `ybus.axes[1]` é o rótulo das linhas (ordem das barras).
- `size(Y, 1)` = número de linhas (14).

### Propriedades estruturais

```julia
nnz_count = count(!iszero, Y)
sparsity  = 100 * (1 - nnz_count / (n^2))
is_sym    = isapprox(Y, transpose(Y); atol = 1e-10)
```

- `count(!iszero, Y)` conta quantos elementos **não** são zero. `!iszero` é a
  função `iszero` negada — passada como argumento (funções são valores).
- `sparsity` = porcentagem de zeros.
- `isapprox(A, B; atol=...)` testa igualdade **aproximada** (tolerância numérica) —
  aqui, se a matriz é simétrica (`Y ≈ Yᵀ`). Comparar floats com `==` é arriscado;
  por isso `isapprox`.

### Lista de elementos não-nulos

```julia
for i in 1:n, j in 1:n
    y = Y[i, j]
    if !iszero(y)
        push!(df_elem, (i, j, bus_order[i], bus_order[j],
                        real(y), imag(y), abs(y), rad2deg(angle(y))))
    end
end
```

- `for i in 1:n, j in 1:n` é um **laço duplo** compacto (equivale a dois `for`
  aninhados) — varre todas as posições da matriz.
- Para cada elemento não-nulo grava parte real (`real`), imaginária (`imag`),
  módulo (`abs`) e ângulo em graus (`rad2deg(angle(y))`).

### Exportar a matriz inteira e o binário

```julia
col_names = ["bus_$(b)" for b in bus_order]
df_G = DataFrame(real.(Y), col_names); insertcols!(df_G, 1, :bus => bus_order)
...
import Serialization
Serialization.serialize(joinpath(RESULTS_DIR, "02_ybus.jls"), (Y = Y, bus_order = collect(bus_order)))
```

- `real.(Y)` (com ponto) extrai a parte real de **toda** a matriz de uma vez.
- `DataFrame(matriz, nomes)` cria a tabela; `insertcols!(df, 1, :bus => ...)`
  insere a coluna de rótulo das barras na **posição 1**.
- `Serialization.serialize` grava o objeto Julia **exato** (matriz complexa +
  ordem) em binário, para o próximo script reusar sem reconstruir nem perder
  precisão. Note `import Serialization` (usa com prefixo) — havia ambiguidade de
  nome com `serialize`, daí o `import` em vez de `using`.

---

## `03_shortcircuit_static.jl` — curto trifásico pelo método Zbus

> **O que faz:** calcula a corrente de curto franco na barra 7 e as tensões em
> todas as barras, pelo método Zbus + superposição, em duas variantes (só
> geradores; geradores + cargas).
> **Saídas:** `data/results/03_*.csv`, `03_results.jls`.

O cabeçalho do script traz as fórmulas-chave:

```
I_falta  = V_pf[f] / Z[f,f]
V_pos[i] = V_pf[i] - (Z[i,f]/Z[f,f]) * V_pf[f]
```

Boa parte da lógica é idêntica ao `zbus_short_circuit` do SCUtils — aqui ela está
"aberta" (não encapsulada em função), o que é didático para acompanhar passo a passo.

### Constantes do estudo

```julia
const FAULT_BUS = 7
const Z_FAULT   = 0.0 + 0.0im   # falta franca (impedância de falta nula)
```

- `const` em variáveis de topo melhora a performance (o tipo não muda) e deixa
  claro que são parâmetros fixos. `0.0 + 0.0im` é o complexo zero.

### Ybus pura + índices

```julia
sys = Logging.with_logger(Logging.NullLogger()) do
    build_system(PSIDSystems, "14 Bus Base Case")
end
set_units_base_system!(sys, "SYSTEM_BASE")
S_base = get_base_power(sys)

ybus = Ybus(sys; include_constant_impedance_loads = false)
Y_net = Matrix(ybus.data)
bus_order = collect(ybus.axes[1])
n = size(Y_net, 1)
idx_of = Dict(b => i for (i, b) in enumerate(bus_order))
f = idx_of[FAULT_BUS]
buses = Dict(get_number(b) => b for b in get_components(ACBus, sys))
```

- **Diferença importante para o script 02:** aqui usa-se
  `include_constant_impedance_loads = false` → Ybus **sem** cargas, porque para o
  curto clássico o modelo é "só geradores". (No 02, a Ybus exibida é a do sistema.)
- `buses` mapeia número→objeto barra (para pegar tensão e tensão de base depois).

### Tensões pré-falta

```julia
V_pf = ComplexF64[]
for b in bus_order
    bus = buses[b]
    push!(V_pf, get_magnitude(bus) * cis(get_angle(bus)))   # cis(x)=exp(ix)
end
```

- Constrói o vetor de fasores pré-falta a partir da solução do fluxo já embutida
  no caso base. (No SCUtils isso é uma comprehension; aqui é um laço explícito —
  mesma coisa.)

### Geradores como shunt (com tabela no terminal)

```julia
gen_shunt = zeros(ComplexF64, n)
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
    @printf("%-16s%-7d%-12.5f%-9.1f%-12.5f\n", get_name(sg), bus_num, Xpp, Sdev, imag(z_sys))
end
```

- `zeros(ComplexF64, n)` cria um vetor de `n` zeros complexos. `gen_shunt[i]`
  acumula a admitância dos geradores na barra `i`.
- A grande novidade aqui é a **impressão tabular** com `@printf`: `%-16s` =
  string alinhada à esquerda em 16 colunas; `%-7d` = inteiro; `%-12.5f` = float
  com 5 casas. Útil para conferir os X″d convertidos.

### Cargas como impedância constante

```julia
load_shunt = zeros(ComplexF64, n)
for ld in get_components(StandardLoad, sys)
    bus_num = get_number(get_bus(ld))
    i = idx_of[bus_num]
    S = load_P(ld) + im * load_Q(ld)          # pu na base do sistema
    V = V_pf[i]
    load_shunt[i] += conj(S) / abs2(V)        # y = conj(S)/|V|^2
end
```

- Mesmo cálculo de admitância de carga visto no SCUtils, separado num vetor
  próprio (`load_shunt`) para montar a variante B somando-o à A.

### A função de curto e as duas variantes

```julia
function short_circuit(Y_fault, V_pf, f, Zf)
    Z = inv(Y_fault)
    If = V_pf[f] / (Z[f, f] + Zf)
    Vpos = [V_pf[i] - (Z[i, f] / (Z[f, f] + Zf)) * V_pf[f] for i in 1:length(V_pf)]
    return (Z = Z, If = If, Vpos = Vpos, Zth = Z[f, f])
end

Y_A = copy(Y_net); for i in 1:n; Y_A[i, i] += gen_shunt[i]; end
res_A = short_circuit(Y_A, V_pf, f, Z_FAULT)

Y_B = copy(Y_A); for i in 1:n; Y_B[i, i] += load_shunt[i]; end
res_B = short_circuit(Y_B, V_pf, f, Z_FAULT)
```

- `copy(Y_net)` é essencial: **sem** copiar, `Y_A[i,i] += ...` alteraria a matriz
  original (em Julia, matrizes são passadas por referência).
- `Y_A` = rede + geradores (variante clássica A). `Y_B` = `Y_A` + cargas
  (variante B). Daí dois resultados.
- Os `;` permitem escrever o `for` curtinho numa linha só.

### Conversão para kA

```julia
Vbase_f_kV = get_base_voltage(buses[FAULT_BUS])
Ibase_f_kA = S_base / (sqrt(3) * Vbase_f_kV)
```

- Corrente de base trifásica: `I_base = S_base / (√3 · V_base)`. Multiplicando a
  corrente em pu por `Ibase_f_kA` dá kA. A potência de curto é `|If|·|V|·S_base`.

### Contribuições dos ramos (validação por KCL)

```julia
neighbors = [j for j in 1:n if j != f && !iszero(Y_net[f, j])]
Itot = 0.0 + 0.0im
for j in neighbors
    y_series = -Y_net[f, j]
    I_j = (res_A.Vpos[j] - res_A.Vpos[f]) * y_series
    global Itot += I_j
    push!(df_contrib, (bus_order[j], abs(I_j), abs(I_j) * Ibase_f_kA))
end
```

- `neighbors` usa comprehension **com filtro** (`if ...`): só as barras `j` que
  têm ramo direto com a 7 (`Y_net[f,j] ≠ 0`).
- O elemento fora da diagonal da Ybus é `-y_série`, então `y_series = -Y_net[f,j]`
  recupera a admitância do ramo. A corrente que `j` injeta na falta é
  `(V_j - V_7)·y_série`.
- **`global Itot`**: dentro de um laço no escopo de topo (script), atribuir a uma
  variável de fora exige declarar `global`. (Dentro de funções isso não é
  necessário — outro motivo para preferir funções.)
- A soma `|Itot|` deve bater com `|If|` direto — é a verificação por lei de
  Kirchhoff das correntes.

A seção 9 serializa os resultados (`03_results.jls`) e grava o resumo — mesmos
padrões já vistos.

---

## `04_dynamic_simulation.jl` — curto no domínio do tempo (PSD.jl)

> **O que faz:** simula o transitório do curto na barra 7 com
> PowerSimulationsDynamics.jl (EDOs das máquinas), em dois casos (franco
> permanente e severo eliminado), gerando séries temporais e gráficos.
> **Saídas:** `data/results/04*.csv` e figuras em `data/figures/04*`.

Este é o script mais "de simulação". O cabeçalho explica a decisão numérica
importante: o solver DAE (IDA) não converge na restauração brusca de uma falta
quase franca numa **barra de transferência**, então:
- **Caso A** = falta franca **permanente** (para comparar com o estático);
- **Caso B** = falta severa **eliminada** em 100 ms (para ver a recuperação).

### A função `simulate_fault` (keyword args + função interna reutilizável)

```julia
function simulate_fault(; z_fault, t_clear, tspan, dtmax = 0.01, fault_bus = FAULT_BUS)
    sys = ...build_system...
    set_units_base_system!(sys, "SYSTEM_BASE")
    for l in get_components(StandardLoad, sys)
        transform_load_to_constant_impedance(l)
    end
```

- Todos os parâmetros são **keyword** (após o `;`). Chamadas ficam legíveis:
  `simulate_fault(; z_fault = 1e-3, t_clear = nothing, tspan = (0.0, 1.6))`.
- `transform_load_to_constant_impedance(l)` converte as cargas para impedância
  constante — dá robustez quando a tensão despenca durante a falta.

### Montar a perturbação (NetworkSwitch)

```julia
ybus = Ybus(sys; include_constant_impedance_loads = false)
...
Y_pre = SparseMatrixCSC{ComplexF32, Int}(ybus.data)
Y_fault = copy(Y_pre)
Yf_shunt = ComplexF32(1.0 / z_fault)
Y_fault[f, f] += Yf_shunt

perturbations = t_clear === nothing ?
    [NetworkSwitch(T_FAULT, Y_fault)] :
    [NetworkSwitch(T_FAULT, Y_fault), NetworkSwitch(t_clear, Y_pre)]
```

- A falta é modelada **mudando a rede**: cria-se `Y_fault` = Ybus com uma grande
  admitância shunt na barra de falta (`1/z_fault`), o que força a tensão a ~0.
- `ComplexF32` (precisão simples) é exigência do PSID nesta API.
- `NetworkSwitch(t, Y)` agenda "no instante `t`, troque a Ybus por `Y`". Se há
  `t_clear`, agenda **duas** trocas: aplicar a falta e depois restaurar `Y_pre`
  (eliminar). O ternário escolhe entre uma ou duas perturbações.

### Executar e ler resultados

```julia
sim = PSID.Simulation(ResidualModel, sys, mktempdir(), tspan, perturbations)
status = execute!(sim, IDA(); dtmax = dtmax, saveat = dtmax)
results = read_results(sim)

volt = Dict(b => get_voltage_magnitude_series(results, b) for b in bus_order)
```

- `Simulation(...)` monta o problema; `mktempdir()` dá uma pasta temporária para
  arquivos internos. `execute!(sim, IDA(); ...)` roda com o solver **IDA**
  (Sundials, próprio para sistemas algébrico-diferenciais).
- `saveat = dtmax` salva a solução em passos regulares.
- `get_voltage_magnitude_series(results, b)` devolve `(tempo, tensão)` da barra
  `b` ao longo do tempo. O `Dict(... for b in ...)` guarda isso para todas.

### Extrair a corrente de falta: pico subtransitório × amortecida

```julia
t, vf = volt[fault_bus]
t_end_fault = t_clear === nothing ? tspan[2] : t_clear
if_mag = [(T_FAULT <= t[k] < t_end_fault) ? vf[k] * abs(Yf_shunt) : 0.0
          for k in eachindex(t)]
# pico subtransitório: média do 1º ciclo após a falta (pula a amostra-lixo do
# instante exato do chaveamento, V_pré*Y_falta)
subtr = findall(k -> (T_FAULT + 1e-4) <= t[k] <= (T_FAULT + 0.02), eachindex(t))
if_subtr = isempty(subtr) ? 0.0 : mean(if_mag[subtr])
# amortecida: janela tardia, mostra o decaimento subtransitório->transitório
settled = findall(k -> (T_FAULT + 0.30) <= t[k] <= (t_end_fault - 0.05), eachindex(t))
if_settled = isempty(settled) ? if_subtr : mean(if_mag[settled])
```

- `t, vf = volt[fault_bus]` **desempacota** a tupla (tempo, tensão).
- A corrente de falta no nó é `|I| = |V|·|Y_shunt|` (KCL no nó), só durante a
  janela da falta (o ternário zera fora dela).
- `findall(predicado, coleção)` devolve os **índices** onde o predicado é
  verdadeiro. `k -> ...` é uma **função anônima** (lambda).
- **Dois pontos de medição, e o porquê:** a corrente de falta **decai com o tempo**
  (a reatância efetiva sobe de X″d para X′d). O `if_subtr` mede o **pico
  subtransitório** (1º ciclo após a falta) — é o valor comparável ao método estático
  Zbus e ao ANAFAS, que também usam X″d. O `if_settled` mede a corrente **amortecida**
  do regime transitório (janela tardia). Medir cedo (subtransitório) é o que alinha o
  dinâmico com o estático (~27 kA); medir tarde dá a corrente já decaída (~23 kA).
- A janela do `subtr` começa em `T_FAULT + 1e-4` de propósito: pula a amostra do
  **instante exato do chaveamento**, em que `if_mag = V_pré · |Y_falta|` é lixo
  numérico (a tensão ainda não colapsou). `mean(if_mag[...])` (de `Statistics`) tira a
  média na janela.

### O restante: gráficos e exportação

A partir daí o script chama `simulate_fault` para os Casos A e B e gera os
gráficos com `Plots.jl`:

```julia
p1 = plot(; xlabel = "tempo [s]", ylabel = "Tensão [pu]", title = "...", legend = :bottomright)
for b in buses_plot
    tt, vv = B.volt[b]
    plot!(p1, tt, vv; label = "BUS $b", lw = 1.8)
end
vline!(p1, [T_FAULT, T_CLEAR_B]; ls = :dash, color = :gray, label = "falta/elim.")
savefig(p1, joinpath(FIG_DIR, "04b_tensoes.png"))
```

- Padrão do `Plots.jl`: `plot(...)` cria a figura; **`plot!`** (com `!`) **adiciona**
  curvas à figura existente; `vline!` marca linhas verticais (instantes de falta/
  eliminação); `savefig` grava o PNG.
- As séries temporais do Caso B são montadas em `DataFrame` adicionando uma coluna
  por barra (`df_v[!, Symbol("V_bus$b")] = ...`) — `Symbol("...")` cria o nome da
  coluna dinamicamente, e `df[!, :col] = vetor` insere a coluna.

---

## `05_scenarios.jl` — cenários de carga e geração

> **O que faz:** roda o curto da barra 7 em 4 cenários (base, carga leve, carga
> pesada, gerador fora), usando as funções do `SCUtils`. Tabela + 2 gráficos.
> **Saídas:** `data/results/05_scenarios_summary.csv`, figuras `05_*`.

### Trazer o módulo local

```julia
include(joinpath(@__DIR__, "..", "src", "SCUtils.jl"))
using .SCUtils
```

- `include(arquivo)` literalmente "cola" o conteúdo do arquivo aqui — define o
  módulo `SCUtils`. `using .SCUtils` (com ponto) traz as funções exportadas.

### Definir os cenários como dados

```julia
scenarios = [
    ("Base", 1.0, nothing),
    ("Carga leve (60%)", 0.6, nothing),
    ("Carga pesada (140%)", 1.4, nothing),
    ("Gerador b2 fora", 1.0, 2),
]
```

- Um **vetor de tuplas** `(nome, fator_de_carga, barra_do_gerador_fora)`.
  `nothing` = "nenhum gerador fora". Modelar configuração como dados (e não como
  `if`s espalhados) deixa o laço principal limpo.

### O laço principal

```julia
for (name, load_factor, gen_off) in scenarios
    sys = build_14bus()
    scale_loads!(sys, load_factor)
    gen_off !== nothing && take_generator_offline!(sys, gen_off)
    solve_pf!(sys)

    Ptot = sum(first(load_PQ(ld)) for ld in get_components(StandardLoad, sys)) *
           get_base_power(sys)

    r  = zbus_short_circuit(sys; fault_bus = FAULT_BUS, include_loads = false)
    rL = zbus_short_circuit(sys; fault_bus = FAULT_BUS, include_loads = true)

    push!(results, (name, Ptot, abs(r.Vpre[r.idx_of[FAULT_BUS]]), abs(r.Zth),
                    abs(r.If), abs(r.If) * r.Ibase_kA, r.scc_mva,
                    abs(rL.If), abs(rL.If) * rL.Ibase_kA))
    vprofiles[name] = abs.(r.Vpos)
    global bus_order_ref = r.bus_order
    ...
end
```

- `for (name, load_factor, gen_off) in scenarios` **desempacota** cada tupla
  direto nas variáveis do laço.
- Para cada cenário: monta o sistema, escala a carga, (opcional) tira o gerador,
  resolve o fluxo, calcula o curto **sem** e **com** cargas, e guarda na tabela.
- `sum(first(load_PQ(ld)) for ld in ...)` soma a parte ativa (`first` da tupla
  `(P,Q)`) de todas as cargas → carga total em pu; `× base_power` → MW.
- `r.idx_of[FAULT_BUS]` reaproveita o dicionário devolvido pela função para achar
  o índice da barra 7 e ler a tensão pré-falta dela.
- `global bus_order_ref` porque estamos escrevendo numa variável de topo dentro do
  laço (mesmo motivo do script 03).

### Gráficos com rótulos sobre as barras

```julia
p1 = bar(results.cenario, results.If_kA; ylabel = "Corrente de falta [kA]", ...)
for (i, v) in enumerate(results.If_kA)
    annotate!(p1, i, v + 0.5, text(@sprintf("%.1f", v), 8))
end
```

- `bar(...)` faz um gráfico de barras (uma por cenário). `results.If_kA` acessa a
  coluna da tabela como vetor.
- `annotate!` escreve o valor (1 casa) acima de cada barra; `enumerate` dá
  (posição, valor) para saber onde colocar o texto.

---

## `06_solar_pv.jl` — impacto de geração fotovoltaica

> **O que faz:** adiciona uma usina FV (inversor *grid-following*) na barra 4 e
> compara, via simulação dinâmica, a resposta ao curto na barra 7 **com** e
> **sem** a FV — evidenciando a corrente de falta limitada dos inversores.
> **Saídas:** `data/results/06_*.csv`, figuras `06_*`.

### Definir o inversor (modelo composto)

```julia
function grid_following_inverter(static_device)
    return DynamicInverter(;
        name = get_name(static_device),
        ω_ref = 1.0,
        converter = AverageConverter(; rated_voltage = 138.0, rated_current = 100.0),
        outer_control = OuterControl(
            ActivePowerPI(; Kp_p = 2.0, Ki_p = 30.0, ωz = 0.132 * 2π * 50),
            ReactivePowerPI(; Kp_q = 2.0, Ki_q = 30.0, ωf = 0.132 * 2π * 50)),
        inner_control = CurrentModeControl(; kpc = 0.37, kic = 0.7, kffv = 1.0),
        dc_source = FixedDCSource(; voltage = 600.0),
        freq_estimator = KauraPLL(; ω_lp = 500.0, kp_pll = 0.084, ki_pll = 4.69),
        filter = LCLFilter(; lf = 0.009, rf = 0.016, cf = 2.5, lg = 0.002, rg = 0.003))
end
```

- Um inversor no PSID é montado como uma **composição** de blocos: conversor,
  controle externo (P/Q), controle interno de corrente, fonte CC, PLL (estimador
  de frequência) e filtro LCL. Cada bloco tem seus ganhos.
- Note `2π` escrito literalmente — Julia aceita Unicode (`π`, `ω`, `ω_ref`) em
  nomes e constantes. Digita-se `\pi` + TAB no REPL/editor.

### Construir o sistema com a usina

```julia
function build_system_pv(; with_pv::Bool)
    sys = ...build...
    if with_pv
        bus = first(b for b in get_components(ACBus, sys) if get_number(b) == PV_BUS)
        pv = RenewableDispatch(; name = PV_NAME, available = true, bus = bus,
            active_power = PV_P, reactive_power = 0.0, rating = 1.0,
            prime_mover_type = PrimeMovers.PVe, ...
            base_power = PV_S)
        add_component!(sys, pv)
        add_component!(sys, grid_following_inverter(pv), pv)
    end
    for l in get_components(StandardLoad, sys)
        transform_load_to_constant_impedance(l)
    end
    return sys
end
```

- `first(b for b in ... if ...)` pega o **primeiro** elemento que satisfaz o
  filtro (a barra 4). É uma comprehension "preguiçosa" passada a `first`.
- Cria o componente **estático** `RenewableDispatch` (`add_component!(sys, pv)`) e
  acopla a ele o **injetor dinâmico** (o inversor) com `add_component!(sys, inv, pv)`
  — o terceiro argumento liga o dinâmico ao estático.
- `with_pv::Bool` anota o tipo do keyword (documenta e valida).

### Simular e medir a resposta da FV

```julia
pv_Ir = get_real_current_series(pv.res, PV_NAME)
pv_Ii = get_imaginary_current_series(pv.res, PV_NAME)
pv_Imag = sqrt.(pv_Ir[2] .^ 2 .+ pv_Ii[2] .^ 2)
```

- Lê as séries de corrente **real** e **imaginária** da usina; o módulo é
  `√(Iᵣ² + Iᵢ²)`, calculado com broadcasting: `sqrt.`, `.^` e `.+` operam
  elemento a elemento nos vetores. `pv_Ir[2]` é o vetor de valores (o `[1]` é o
  tempo).

```julia
settled_idx(t) = findall(k -> (T_FAULT + 0.05) <= t[k] <= (T_FAULT + 0.30), eachindex(t))
if_base = mean(base.iflt[ib])
println("    Δ : ", round((if_pv - if_base) / if_base * 100, digits = 2), " %")
```

- Mesma ideia do script 04: uma janela "estabilizada" logo após a falta, e a
  média da corrente nela. O `Δ` mostra que a FV quase não muda a corrente de
  curto (+1,9%), enquanto a **corrente da própria FV** fica limitada a ~1,1 pu —
  o ponto central do estudo.

O restante são 4 gráficos comparativos (tensão na barra 7, na barra da FV,
velocidade do gerador de referência, e P/Q/|I| da usina) e a exportação dos CSVs,
nos mesmos padrões já vistos.

---

## `07_export_latex.jl` — exportar matrizes e tabelas para o artigo

> **O que faz:** gera os fragmentos LaTeX (`\input` no Overleaf) e as versões
> ASCII (`.txt`) das matrizes (Ybus G/B/|Y|, Zbus) e das 3 tabelas comparativas
> Zbus×PSD×ANAFAS, além do "spy plot" da Ybus.
> **Saídas:** `data/headquarters/latex/*.tex`, `data/headquarters/txt/*.txt`,
> `data/figures/07_ybus_spy.png`.

Este é o script mais longo, mas é basicamente **formatação**. A "matemática" do
curto é a mesma do 03/SCUtils; aqui ela vira texto bonito.

### Helpers de formatação LaTeX

```julia
function rfmt(x::Real; d::Int = 3, zero_dash::Bool = false)
    if abs(x) < 10.0^(-d - 1)
        return zero_dash ? "\\cdot" : "0"
    end
    s = Printf.format(Printf.Format("%.$(d)f"), x)
    s = replace(s, r"^-0\.0*$" => "0")   # evita "-0.000"
    return s
end
```

- Formata um número com `d` casas. Se for ~zero, devolve `"0"` ou `"\cdot"`
  (ponto central, para deixar a matriz limpa).
- **`Printf.format(Printf.Format("%.$(d)f"), x)`**: a macro `@sprintf` exige o
  formato como **literal** (não dá para variar `d`). A versão funcional
  `Printf.Format(...)` aceita o formato montado por interpolação → precisão
  dinâmica.
- `replace(s, regex => subst)` troca via **expressão regular** (`r"..."`): aqui,
  conserta o caso `"-0.000"` para `"0"`. `\\` é a barra invertida escapada (em
  LaTeX `\cdot`).

```julia
function matrix_to_latex(M::AbstractMatrix{<:Real}; d = 3, zero_dash = true)
    io = IOBuffer()
    println(io, "\\begin{bmatrix}")
    for i in 1:n
        cells = [rfmt(M[i, j]; d, zero_dash) for j in 1:m]
        println(io, "  ", join(cells, " & "), " \\\\")
    end
    print(io, "\\end{bmatrix}")
    return String(take!(io))
end
```

- **`IOBuffer()`** é um "arquivo na memória": você vai escrevendo nele com
  `println(io, ...)` e no fim `String(take!(io))` extrai tudo como string. É o
  jeito eficiente de montar texto grande em Julia (melhor que concatenar com `*`).
- Monta o ambiente `bmatrix` do LaTeX: cada linha vira células separadas por
  `&`, terminadas em `\\` (em Julia, `"\\\\"` = duas barras = o `\\` do LaTeX).
- `[rfmt(M[i,j]; d, zero_dash) for j in 1:m]` — note `; d, zero_dash`: passar
  `d` é atalho para `d = d` (mesmo nome da variável local).
- `AbstractMatrix{<:Real}` aceita qualquer matriz de reais (`<:Real` = "subtipo
  de Real"). É escrever a função de forma genérica.

### Helpers ASCII (.txt) — as matrizes "desenhadas"

```julia
function cell(x::Real; d::Int, w::Int)
    s = abs(x) < 10.0^(-d - 1) ? "." : Printf.format(Printf.Format("%.$(d)f"), x)
    return lpad(s, w)
end

function matrix_to_txt(M, bus_order, titulo; d = 2, w = 7)
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
                join(cell(M[i, j]; d, w) for j in 1:n))
    end
    println(io, "="^total)
    return String(take!(io))
end
```

- `lpad(s, w)` / `rpad(s, w)` alinham a string à **direita/esquerda** numa largura
  `w` (preenchendo com espaços) → colunas alinhadas no `.txt`.
- `lpad.(string.(bus_order), w)` (com pontos) converte cada número de barra em
  string e alinha — tudo de uma vez (broadcasting). `join(...)` cola sem
  separador.
- Resultado: o cabeçalho `B\B |` e a grade 14×14 que você vê em
  [data/headquarters/txt/ybus_G.txt](data/headquarters/txt/ybus_G.txt).

### Sistema, fluxo e as DUAS Ybus

```julia
ybus = Ybus(sys; include_constant_impedance_loads = false)
Y_net = ComplexF64.(Matrix(ybus.data))      # rede pura → usada no cálculo do curto
...
Y_sys = ComplexF64.(Matrix(Ybus(sys).data)) # do sistema (c/ cargas) → usada na EXIBIÇÃO
G = real.(Y_sys); B = imag.(Y_sys); absY = abs.(Y_sys)
```

- **Decisão importante** (e fácil de confundir): há **duas** Ybus.
  - `Y_sys` (com cargas) é a que vai para as **matrizes exibidas** G/B/|Y| —
    coincide com o script 02 e o item 1 do trabalho.
  - `Y_net` (sem cargas) é a usada no **cálculo** de Zbus/corrente de curto.
  - São propositalmente diferentes. (Ver [COMPARACAO_ANAFAS.md](COMPARACAO_ANAFAS.md).)

### O spy plot

```julia
pts_i = Int[]; pts_j = Int[]
for i in 1:n, j in 1:n
    if abs(Y_net[i, j]) > 1e-9
        push!(pts_i, i); push!(pts_j, j)
    end
end
spy = scatter(pts_j, pts_i; yflip = true, markershape = :square, ...)
```

- Coleta as coordenadas dos elementos não-nulos e plota como quadradinhos. O
  `yflip = true` inverte o eixo Y para a linha 1 ficar no topo (como se lê uma
  matriz). Visualiza a esparsidade da Ybus.

### A função `short_circuit` parametrizada e as 4 variantes

```julia
function short_circuit(; vpre::Symbol, with_loads::Bool)
    ...
    Vpf = if vpre == :flat
        ComplexF64[1.0 + 0.0im for _ in bus_order]
    else
        ComplexF64[get_magnitude(buses[b]) * cis(get_angle(buses[b])) for b in bus_order]
    end
    ...
end

variants = Dict(
    :flat_noload => short_circuit(; vpre = :flat, with_loads = false),
    :flat_load   => short_circuit(; vpre = :flat, with_loads = true),
    :flow_noload => short_circuit(; vpre = :flow, with_loads = false),
    :flow_load   => short_circuit(; vpre = :flow, with_loads = true),
)
```

- **`Symbol`** (`:flat`, `:flow`) é um identificador leve, ideal para "opções".
  `vpre::Symbol` aceita só símbolos.
- `Vpf = if ... else ... end`: em Julia, `if` é uma **expressão** que devolve
  valor — dá para atribuir o resultado direto. Tensão pré-falta **flat** (1,0 pu,
  padrão clássico do ANAFAS) ou **do fluxo**.
- `for _ in bus_order`: o `_` é "não me importo com a variável", só quero repetir.
- As 4 combinações (flat/fluxo × com/sem carga) ficam num `Dict` indexado por
  símbolo — assim as seções seguintes pegam `variants[:flat_noload]` etc. A
  variante **flat/sem carga** é a referência comparável ao ANAFAS clássico.

### As tabelas comparativas e o erro percentual

```julia
const ANAFAS_If_pu = 6.426
const ANAFAS_V = Dict(2=>0.840, 3=>0.813, ...)
relerr(julia, ref) = (julia - ref) / ref * 100
errstr(e) = string(e >= 0 ? "+" : "-", round(abs(e), digits = 1), "\\%")
```

- Os resultados do **ANAFAS** (rodados pelo usuário) entram como constantes.
- `relerr` é o erro percentual com o ANAFAS como **referência** (convenção do
  artigo do IFG). `errstr` formata com sinal e `\%` (o `%` precisa ser escapado
  em LaTeX).

A montagem de cada tabela é o mesmo padrão `IOBuffer` + `@sprintf`, escrevendo as
linhas `tabular`/`booktabs` (`\toprule`, `\midrule`, `\bottomrule`). A versão
`.txt` usa `table_to_txt`, que calcula a **largura de cada coluna** automaticamente:

```julia
w = [maximum(length, vcat([headers[c]], [r[c] for r in rows])) for c in 1:ncol]
```

- Para cada coluna `c`, pega o **comprimento máximo** entre o cabeçalho e todas as
  células daquela coluna → garante alinhamento perfeito no ASCII.

### Diagnóstico no terminal

Antes de gravar, o script imprime no terminal qual variante fica mais próxima do
ANAFAS (corrente e contribuições). É só `@printf` num laço sobre as variantes —
ajuda a justificar, no artigo, **por que** a tabela de contribuições usa a
variante flat (a que melhor reproduz a divisão de corrente do ANAFAS).

---

## Resumo: onde cada conceito de Julia aparece

| Conceito | Onde ver primeiro |
|---|---|
| `using` / `import` / apelido `const` | qualquer cabeçalho |
| `DataFrame` + `push!` + `CSV.write` | [01_load_system.jl](julia/scripts/01_load_system.jl) |
| Multiple dispatch (`f(x::Tipo)` vs `f(x)`) | `load_P` em [01](julia/scripts/01_load_system.jl) e `load_PQ` em [SCUtils](julia/src/SCUtils.jl) |
| Broadcasting (`real.`, `abs.`, `.^`) | [02_ybus.jl](julia/scripts/02_ybus.jl), [06](julia/scripts/06_solar_pv.jl) |
| Complexos (`im`, `cis`, `conj`, `abs2`) | [03_shortcircuit_static.jl](julia/scripts/03_shortcircuit_static.jl) |
| `inv`, `Matrix`, álgebra linear | [03](julia/scripts/03_shortcircuit_static.jl), [SCUtils](julia/src/SCUtils.jl) |
| Módulo + `export` + `include` | [src/SCUtils.jl](julia/src/SCUtils.jl), usado em [05](julia/scripts/05_scenarios.jl) |
| Keyword args (`function f(; a, b)`) | [04](julia/scripts/04_dynamic_simulation.jl), [SCUtils](julia/src/SCUtils.jl) |
| Função anônima + `findall` + `mean` | [04](julia/scripts/04_dynamic_simulation.jl), [06](julia/scripts/06_solar_pv.jl) |
| `do ... end` (logger silencioso) | quase todos |
| `global` em laço de topo | [03](julia/scripts/03_shortcircuit_static.jl), [05](julia/scripts/05_scenarios.jl) |
| `Symbol` como opção + `if` como expressão | [07_export_latex.jl](julia/scripts/07_export_latex.jl) |
| `IOBuffer` para montar texto | [07_export_latex.jl](julia/scripts/07_export_latex.jl) |
| `Plots.jl` (`plot!`, `vline!`, `savefig`) | [04](julia/scripts/04_dynamic_simulation.jl), [05](julia/scripts/05_scenarios.jl), [06](julia/scripts/06_solar_pv.jl) |
