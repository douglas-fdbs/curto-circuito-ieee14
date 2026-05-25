# Guia de Julia — entendendo a linguagem pelos scripts do trabalho

Este documento ensina a linguagem **Julia** do zero, usando os próprios scripts
deste projeto como exemplos. É voltado para quem **nunca** programou em Julia.
A ideia é: primeiro um panorama da linguagem e do ambiente, depois um mini-curso
dos conceitos essenciais e, por fim, a **leitura linha a linha** dos nossos scripts.

> Companheiro do [DESENVOLVIMENTO.md](../DESENVOLVIMENTO.md), que explica *o que* o
> trabalho faz. Aqui explicamos *como o código funciona* como linguagem.

## Índice
1. [O que é Julia e por que a usamos](#1-o-que-é-julia-e-por-que-a-usamos)
2. [Como rodar código Julia](#2-como-rodar-código-julia)
3. [Project.toml e Manifest.toml — os ambientes](#3-projecttoml-e-manifesttoml--os-ambientes)
4. [Mini-curso: conceitos essenciais da linguagem](#4-mini-curso-conceitos-essenciais-da-linguagem)
5. [Script 01 linha a linha](#5-script-01-linha-a-linha)
6. [Script 02 linha a linha (novos conceitos)](#6-script-02-linha-a-linha-novos-conceitos)
7. [SCUtils.jl: módulos, despacho múltiplo e do-blocks](#7-scutilsjl-módulos-despacho-múltiplo-e-do-blocks)
8. [Novidades nos scripts 03–06](#8-novidades-nos-scripts-0306)
9. [Tabela de referência rápida de símbolos](#9-tabela-de-referência-rápida-de-símbolos)

---

## 1. O que é Julia e por que a usamos

**Julia** é uma linguagem de programação criada para **computação científica**.
O seu lema é resolver o "problema das duas linguagens": normalmente, protótipos
são escritos em uma linguagem fácil e lenta (Python, MATLAB) e, quando precisam
de desempenho, são reescritos em uma linguagem rápida e difícil (C, Fortran).
Julia tenta ser **fácil de escrever como Python e rápida como C** ao mesmo tempo.

Características que vão aparecer no nosso código:

- **Compilada "na hora" (JIT):** quando você roda uma função pela primeira vez,
  Julia a compila para código de máquina. Por isso a **primeira** execução é lenta
  (a tal "pré-compilação" de ~1–2 min) e as seguintes são rápidas.
- **Despacho múltiplo (multiple dispatch):** a mesma função pode ter várias
  "versões" (métodos) escolhidas pelos **tipos** dos argumentos. É o coração da
  linguagem (seção 4.7).
- **Voltada a matemática:** vetores, matrizes, números complexos e até letras
  gregas (`δ`, `ω`, `π`) são nativos.
- **Indexação começa em 1** (como em MATLAB/Fortran, diferente de Python/C).

Usamos Julia porque o ecossistema **Sienna** (PowerSystems.jl,
PowerSimulationsDynamics.jl etc.) — exigido pelo trabalho — é escrito em Julia.
A convenção `.jl` no fim do nome dos pacotes e arquivos significa "arquivo Julia".

---

## 2. Como rodar código Julia

Há três formas principais:

**(a) REPL (modo interativo).** Digitando `julia` no terminal abre um console onde
você escreve expressões e vê o resultado na hora:

```julia
julia> 2 + 3
5
julia> x = [1, 2, 3]
3-element Vector{Int64}: ...
```

**(b) Rodar um script.** É o que fazemos no projeto:

```bash
julia --project=. scripts/01_load_system.jl
```

- `julia` chama o interpretador.
- `--project=.` diz "use o ambiente da pasta atual" (o `Project.toml` daqui). É o
  passo que garante que os pacotes certos sejam usados (seção 3).
- `scripts/01_load_system.jl` é o arquivo a executar, de cima para baixo.

**(c) Modo pacote (Pkg).** Dentro do REPL, apertar `]` entra no gerenciador de
pacotes, onde se instala/atualiza dependências:

```julia
(meu_ambiente) pkg> add DataFrames    # instala o pacote DataFrames
(meu_ambiente) pkg> instantiate       # instala tudo que o projeto pede
```

> **Por que a 1ª execução demora?** Julia compila as funções na primeira chamada.
> Carregar `PowerSystems` + `PowerSimulationsDynamics` compila muita coisa
> (~1–2 min). Rodar o mesmo script de novo na mesma sessão é quase instantâneo.

---

## 3. Project.toml e Manifest.toml — os ambientes

Um **ambiente** em Julia é uma pasta com dois arquivos que, juntos, definem
exatamente quais pacotes (e versões) o projeto usa. É o equivalente ao
`venv`/`requirements`/`pyproject` do Python, ou ao `package.json`/`lock` do Node.

### `Project.toml` — o que o projeto pede (alto nível)
Lista as dependências **diretas** (as que você de fato usa) e, opcionalmente,
restrições de versão. Exemplo simplificado do nosso:

```toml
[deps]
PowerSystems = "bcd98974-b02a-5e2f-9ee0-a103f5c450dd"
DataFrames   = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
CSV          = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
...
```

- Cada linha é `NomeDoPacote = "UUID"`. O **UUID** é um identificador único
  universal — garante que "DataFrames" seja sempre o mesmo pacote, mesmo que
  existissem dois com o mesmo nome.
- Você raramente edita isso à mão: `pkg> add DataFrames` adiciona a linha sozinho.

### `Manifest.toml` — a "fotografia" exata (baixo nível)
É **gerado automaticamente** e lista **toda** a árvore de dependências — não só o
que você pediu, mas também o que os seus pacotes pedem, com a **versão exata** de
cada um. É o "lockfile": quem tiver o seu `Manifest.toml` reproduz o seu ambiente
bit a bit. Você **não** edita esse arquivo manualmente (é o que está aberto no seu
editor agora — repare que ele é enorme; é normal).

### Como isso se conecta ao "rodar"
1. `--project=.` aponta para a pasta com esses dois arquivos.
2. Na 1ª vez, `pkg> instantiate` lê o `Manifest.toml` e baixa/compila tudo.
3. Daí em diante, `using PowerSystems` encontra exatamente a versão registrada.

> **Resumo:** `Project.toml` = "o que eu quero" (curto, legível). `Manifest.toml`
> = "exatamente o que foi resolvido" (longo, automático, garante reprodutibilidade).

---

## 4. Mini-curso: conceitos essenciais da linguagem

Esta seção dá o vocabulário mínimo para entender os scripts. Cada item tem um
exemplo curtinho.

### 4.1 Comentários
```julia
# isto é um comentário de uma linha
#=
  isto é um comentário de bloco,
  pode ocupar várias linhas
=#
```
Nos scripts, o cabeçalho `#= ... =#` no topo descreve o que o arquivo faz.

### 4.2 Variáveis e tipos
Atribuição é com `=`. Você **não precisa declarar o tipo** — Julia infere:
```julia
n = 14            # Int64  (número inteiro)
base = 100.0      # Float64 (número real, "ponto flutuante")
nome = "BUS 07"   # String (texto)
ok = true         # Bool (verdadeiro/falso)
z = 2 + 3im       # Complex (im é a unidade imaginária √-1)
```
Tipos que aparecem muito no projeto: `Int`, `Float64`, `ComplexF64` (complexo de
dupla precisão), `ComplexF32` (complexo de precisão simples), `String`, `Bool`,
`Symbol` (ver 4.4).

### 4.3 `const` — constantes
```julia
const FAULT_BUS = 7
```
`const` diz que aquele nome não vai mudar de valor/tipo. Além de documentar a
intenção, ajuda o compilador a otimizar. Usamos para parâmetros fixos (barra de
falta, tempos, caminhos de pasta).

### 4.4 Símbolos especiais (visão geral — detalhes na seção 9)
Julia usa alguns símbolos com significado próprio. Os principais:

| Símbolo | Significado curto |
|---------|-------------------|
| `!` (no fim do nome) | a função **modifica** seu argumento (ex.: `push!`, `sort!`) |
| `!` (antes de algo) | "não" lógico (ex.: `!iszero`) |
| `.` | "broadcasting": aplica a cada elemento (ex.: `real.(Y)`); ou acesso a campo (`obj.campo`) |
| `::` | anotação de **tipo** (ex.: `ld::StandardLoad`) |
| `? :` | operador condicional (ternário): `cond ? a : b` |
| `&&`, `\|\|` | "e"/"ou" lógicos com **curto-circuito** (seção 4.9) |
| `=>` | um **par** chave→valor (ex.: `:bus => 7`) |
| `...` | "splat": espalha uma coleção em vários argumentos |
| `@nome` | uma **macro** (ex.: `@printf`) |
| `$` | interpolação em strings (ex.: `"bus_$(b)"`) |
| `:nome` | um **Symbol** (um rótulo leve, ex.: `:bus`, `:δ`) |

### 4.5 Strings e interpolação
```julia
b = 7
"bus_$(b)"        # vira "bus_7"  — o $(...) insere o valor
"linha"^3         # vira "linhalinhalinha"  — ^ repete a string
println("V = ", v, " pu")   # println aceita vários pedaços separados por vírgula
"\n"              # quebra de linha;  "\""  é uma aspa literal
```

### 4.6 Funções
**Forma longa:**
```julia
function dobro(x)
    return 2 * x
end
```
**Forma curta** (uma linha; o `return` é implícito — o valor da última expressão):
```julia
dobro(x) = 2 * x
```
**Função anônima** (sem nome, usada "de passagem"):
```julia
x -> 2 * x          # "dado x, devolve 2x"
```
**Convenção do `!`:** funções que terminam em `!` **alteram** o argumento.
`sort(v)` devolve uma cópia ordenada; `sort!(v)` ordena `v` no lugar.

**Argumentos nomeados (keyword):** vêm depois de `;` na definição e na chamada:
```julia
function curto(sys; fault_bus, z_fault = 0.0)   # z_fault tem valor padrão
    ...
end
curto(sys; fault_bus = 7)        # chamamos nomeando o argumento
```

**`do`-block** (um jeito elegante de passar uma função anônima como 1º argumento):
```julia
with_logger(NullLogger()) do
    build_system(...)            # este bloco é a "função anônima"
end
```
equivale a `with_logger(() -> build_system(...), NullLogger())`. Usamos isso para
silenciar mensagens durante o carregamento do sistema.

### 4.7 Despacho múltiplo (multiple dispatch) — o coração de Julia
Uma mesma função pode ter vários **métodos**, escolhidos pelos **tipos** dos
argumentos. Exemplo real do projeto:
```julia
load_P(ld::StandardLoad) = ...   # método 1: para cargas do tipo StandardLoad
load_P(ld) = get_active_power(ld) # método 2 (genérico): para qualquer outra carga
```
Quando chamamos `load_P(x)`, Julia olha o tipo de `x` e escolhe o método **mais
específico** que combina. Isso substitui o "if tipo == ..." de outras linguagens e
deixa o código extensível. `get_components`, `get_number` etc. dos pacotes Sienna
funcionam assim.

### 4.8 Coleções e indexação
```julia
v = [10, 20, 30]      # Vector (vetor)
v[1]                  # 10  — ATENÇÃO: índice começa em 1
M = [1 2; 3 4]        # Matrix 2x2
M[2, 1]               # 3   — linha 2, coluna 1
t = (7, "BUS 07")     # Tuple (imutável, tipos mistos)
nt = (bus = 7, v = 1.04)   # NamedTuple — acessa por nome: nt.bus
d = Dict("a" => 1, "b" => 2)   # dicionário (chave => valor); d["a"] == 1
1:14                  # um "range" (1,2,...,14); usado em laços e fatias
Int[]                 # vetor vazio cujos elementos serão Int
```

### 4.9 Laços e condicionais
```julia
for b in buses        # itera sobre cada elemento
    println(b)
end

if x > 0
    ...
elseif x == 0
    ...
else
    ...
end

cond ? a : b          # ternário: vale a se cond, senão b
```
**Curto-circuito** (idiomático em Julia):
```julia
get_available(sg) || continue   # se disponível, para aqui; senão, executa `continue`
dyn === nothing && continue     # se dyn é nothing, executa `continue` (pula)
```
`||` ("ou") só avalia o lado direito se o esquerdo for **falso**; `&&` ("e") só
avalia o direito se o esquerdo for **verdadeiro**. Vira um "if" enxuto.

### 4.10 Compreensões (comprehensions)
Forma compacta de construir coleções:
```julia
[2*x for x in 1:3]                 # [2, 4, 6]
["bus_$(b)" for b in bus_order]    # ["bus_1", "bus_2", ...]
Dict(b => i for (i, b) in enumerate(bus_order))   # dicionário por compreensão
ComplexF64[f(b) for b in lista]    # com TIPO na frente: força Vector{ComplexF64}
```
`enumerate(v)` devolve pares `(índice, valor)`.

### 4.11 Broadcasting — o ponto `.`
Adicionar um `.` a uma função/operador faz ele agir **elemento a elemento**:
```julia
real.(Y)        # aplica real() a CADA elemento da matriz Y
a .+ b          # soma elemento a elemento
sqrt.(x.^2)     # raiz de cada x²
```
Sem o ponto, `real(Y)` tentaria agir na matriz inteira (e falharia). Com o ponto,
"varre" todos os elementos. É um dos recursos mais usados no projeto.

### 4.12 Pacotes: `using`, `import` e módulos
```julia
using DataFrames     # traz as funções "exportadas" do pacote para uso direto
import Serialization # traz só o NOME do módulo; usa-se qualificando:
Serialization.serialize(...)   #   ...com o prefixo do módulo
```
- `using X` = "quero usar X e suas funções diretamente" (ex.: `DataFrame(...)`).
- `import X` = "quero X, mas vou chamar com `X.funcao`" (útil quando há nomes
  iguais em pacotes diferentes — foi o caso de `serialize`).
- Um **módulo** é um espaço de nomes próprio. Nós criamos um: `module SCUtils ...
  end` (seção 7). `export` lista o que fica visível para quem usar o módulo.

### 4.13 Macros — o `@`
Uma **macro** é um "comando" que transforma código antes de rodar. Reconhece-se
pelo `@`. As que usamos:
```julia
@printf("%.2f kA\n", 28.94)   # impressão formatada (estilo C): 28.94 kA
@__DIR__                      # caminho da pasta deste arquivo .jl
@warn "mensagem"              # emite um aviso
```

### 4.14 Identificadores Unicode
Julia aceita letras gregas e símbolos matemáticos em nomes de variáveis — ótimo
para engenharia. No projeto aparecem `π` (pi), e estados de máquina como `δ`
(ângulo do rotor) e `ω` (velocidade). No editor, digita-se `\delta` + Tab → `δ`.

---

## 5. Script 01 linha a linha

Arquivo: [julia/scripts/01_load_system.jl](../julia/scripts/01_load_system.jl).
Ele carrega o sistema IEEE 14 barras e lista os componentes. Vamos por partes.

### Cabeçalho e importações
```julia
#==============================================================================
 Script 01 - Carregamento e exploração do sistema IEEE 14 barras
 ...
==============================================================================#

using PowerSystems
using PowerSystemCaseBuilder
using DataFrames
using CSV
```
- O bloco `#= ... =#` é só documentação (não executa).
- As quatro linhas `using` carregam os pacotes: `PowerSystems` (modelos de rede),
  `PowerSystemCaseBuilder` (sistemas prontos), `DataFrames` (tabelas) e `CSV`
  (gravar `.csv`). A partir daqui podemos usar as funções deles diretamente.

### Constantes e pastas
```julia
const PSY = PowerSystems

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULTS_DIR = joinpath(ROOT, "data", "results")
mkpath(RESULTS_DIR)
```
- `const PSY = PowerSystems`: cria um **apelido** para o módulo. Onde fosse
  preciso escrever `PowerSystems.algo`, pode-se escrever `PSY.algo` (mais curto).
- `@__DIR__` é uma macro que devolve a pasta onde o script está
  (`.../julia/scripts`).
- `joinpath(a, b, c)` junta pedaços de caminho com a barra certa do sistema
  operacional. `".."` significa "pasta acima". Então
  `joinpath(@__DIR__, "..", "..")` sobe dois níveis: de `julia/scripts` para a
  raiz do projeto.
- `normpath(...)` "limpa" o caminho (resolve os `..`), deixando-o canônico.
- `RESULTS_DIR` é a pasta `data/results`. `mkpath` cria essa pasta (e as
  intermediárias) se ainda não existir — sem erro se já existir.

### Carregar o sistema
```julia
println("="^70)
println(" Carregando sistema IEEE 14 barras (PSIDSystems / \"14 Bus Base Case\")")
println("="^70)

sys = build_system(PSIDSystems, "14 Bus Base Case")
set_units_base_system!(sys, "SYSTEM_BASE")

println(sys)
```
- `"="^70` cria uma linha de 70 sinais de igual (o `^` repete a string); só
  enfeite no terminal. As `\"` dentro da string são aspas literais.
- `build_system(PSIDSystems, "14 Bus Base Case")` baixa/monta o sistema pronto e
  devolve um objeto que guardamos em `sys`. `PSIDSystems` é uma **categoria** de
  sistemas (um valor fornecido pelo pacote).
- `set_units_base_system!(sys, "SYSTEM_BASE")` — note o `!`: esta função
  **modifica** `sys`, fixando o sistema de unidades em "por unidade na base do
  sistema" (100 MVA). Garante que todos os valores saiam em p.u. coerente.
- `println(sys)` imprime um resumo do sistema.

### Inventário de barras (mostra muitos conceitos juntos)
```julia
buses = sort(collect(get_components(ACBus, sys)); by = get_number)
```
Lendo de dentro para fora:
- `get_components(ACBus, sys)` pede ao sistema **todos os componentes do tipo
  `ACBus`** (as barras). Repare: passamos um **tipo** (`ACBus`) como argumento —
  isso é comum em Julia. Devolve um iterador (algo "percorrível", mas não uma
  lista pronta).
- `collect(...)` transforma esse iterador em um **vetor** de fato.
- `sort(vetor; by = get_number)` ordena o vetor. O argumento nomeado `by` recebe
  uma **função** (`get_number`) — ou seja, "ordene comparando o número de cada
  barra". Aqui vemos funções sendo tratadas como valores.

```julia
df_bus = DataFrame(
    number       = Int[],
    name         = String[],
    bustype      = String[],
    base_voltage = Float64[],   # kV
    vm_pu        = Float64[],   # magnitude de tensão [pu]
    va_rad       = Float64[],   # ângulo [rad]
)
```
- Cria uma **tabela** (DataFrame) vazia com 6 colunas. Cada `Int[]`, `String[]`,
  `Float64[]` é um **vetor vazio** daquele tipo — define o tipo da coluna.

```julia
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
```
- Laço sobre cada barra `b`.
- `push!(df_bus, (...))` — o `!` indica que **acrescenta** uma linha à tabela. O
  que está entre parênteses é uma **tupla** (uma linha): número, nome, tipo,
  tensão base, magnitude e ângulo.
- `get_number(b)`, `get_name(b)` etc. são "getters" do PowerSystems: a forma
  recomendada de ler dados de um componente (em vez de acessar campos direto).
- `string(get_bustype(b))` converte o tipo da barra (um valor especial, ex.
  `ACBusTypes.REF`) em **texto**, para caber na coluna `String`.

```julia
println("\n--- Barras (", nrow(df_bus), ") ---")
show(df_bus, allrows = true); println()
CSV.write(joinpath(RESULTS_DIR, "01_buses.csv"), df_bus)
```
- `"\n"` é uma quebra de linha; `println` aceita vários argumentos separados por
  vírgula e os imprime em sequência. `nrow(df_bus)` é o número de linhas.
- `show(df_bus, allrows = true)` imprime a tabela inteira (sem cortar linhas). O
  `;` permite duas instruções na mesma linha; o `println()` final só pula linha.
- `CSV.write(caminho, df_bus)` grava a tabela em `data/results/01_buses.csv`.

### Inventário de linhas, transformadores, geradores, cargas
O padrão se repete (pegar componentes → laço → `push!` → gravar CSV). Pontos novos:

```julia
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
```
- `get_arc(l)` devolve o "arco" da linha (de onde vai aonde). `get_from`/`get_to`
  dão as barras de origem/destino; `get_number(...)` extrai o número delas.
- `get_b(l).from + get_b(l).to`: `get_b(l)` devolve uma **NamedTuple** com os
  campos `from` e `to` (susceptância shunt de cada extremo). `.from`/`.to`
  acessam esses campos; somamos os dois.

```julia
for T in (Transformer2W, TapTransformer)
    for t in get_components(T, sys)
        ...
        push!(df_tr, ( get_name(t), string(T), ... ))
    end
end
```
- `(Transformer2W, TapTransformer)` é uma **tupla de tipos**. O laço externo
  percorre **tipos** (transformador de 2 enrolamentos e transformador com tap);
  para cada tipo `T`, o laço interno pega os componentes daquele tipo. Em Julia,
  tipos são valores que podem ir em coleções e laços.

```julia
df_dyn = DataFrame(
    name = [get_name(d) for d in dyn],
    type = [string(typeof(d)) for d in dyn],
)
```
- Aqui as colunas são criadas por **compreensão**: `[get_name(d) for d in dyn]`
  gera o vetor de nomes de uma vez. `typeof(d)` devolve o **tipo** do componente
  (ex.: `DynamicGenerator{...}`), convertido em texto por `string`.

### Despacho múltiplo na prática (cargas ZIP)
```julia
load_P(ld::StandardLoad) = get_constant_active_power(ld) +
                           get_current_active_power(ld) +
                           get_impedance_active_power(ld)
load_Q(ld::StandardLoad) = ...
load_P(ld) = get_active_power(ld)
load_Q(ld) = get_reactive_power(ld)
```
- Definimos `load_P` em **forma curta** (uma expressão, `return` implícito).
- `load_P(ld::StandardLoad)` — o `::StandardLoad` restringe este método a cargas
  do tipo `StandardLoad` (modelo ZIP), que não têm uma "potência ativa" única: é
  preciso somar as três parcelas (constante + corrente + impedância).
- `load_P(ld)` (sem tipo) é o método **genérico**, para qualquer outra carga.
- Ao chamar `load_P(x)`, Julia escolhe automaticamente o método certo pelo tipo
  de `x`. Isso é o **despacho múltiplo** resolvendo o "e se a carga for de outro
  tipo?" sem nenhum `if`.

### Resumo final
```julia
println("  Base de potência do sistema : ", get_base_power(sys), " MVA")
...
println("  Cargas                      : ", nrow(df_load))
```
Apenas imprime os totais. `get_base_power(sys)` e `get_frequency(sys)` leem
metadados do sistema; os `nrow(...)` contam linhas das tabelas.

---

## 6. Script 02 linha a linha (novos conceitos)

Arquivo: [julia/scripts/02_ybus.jl](../julia/scripts/02_ybus.jl). Monta a matriz
Ybus. Mostra **matrizes, números complexos, broadcasting e `@printf`**.

```julia
using LinearAlgebra
using SparseArrays
using Printf
```
- Novos pacotes: `LinearAlgebra` (transpor, inverter, etc.), `SparseArrays`
  (matrizes esparsas) e `Printf` (a macro `@printf`).

```julia
ybus = Ybus(sys)
Y = Matrix(ybus.data)            # densa, complexa
bus_order = ybus.axes[1]         # ordem das barras na matriz
n = size(Y, 1)
```
- `Ybus(sys)` constrói o objeto Ybus. Ele guarda a matriz em `ybus.data` (forma
  **esparsa** — só os não-zeros) e os rótulos das barras em `ybus.axes`.
- `Matrix(ybus.data)` converte a matriz esparsa em **densa** (todos os elementos
  explícitos), mais fácil de manipular/exportar. `Y` é uma matriz de números
  **complexos** (admitâncias `G + jB`).
- `ybus.axes[1]` pega o **primeiro** eixo (as barras). Lembre: índice começa em 1.
- `size(Y, 1)` = número de linhas de `Y` (14).

```julia
nnz_count = count(!iszero, Y)
sparsity  = 100 * (1 - nnz_count / (n^2))
is_sym    = isapprox(Y, transpose(Y); atol = 1e-10)
```
- `count(f, Y)` conta quantos elementos satisfazem a função `f`. Aqui `f` é
  `!iszero` — o `!` **na frente de uma função** cria a função "não é zero". Então
  contamos os elementos diferentes de zero.
- `n^2` é `n` ao quadrado (`^` em números é potência). `sparsity` é a % de zeros.
- `isapprox(A, B; atol = 1e-10)` testa se `A` e `B` são iguais **a menos de uma
  tolerância** (necessário com floats, que têm arredondamento). `transpose(Y)` é
  a transposta. O resultado (`true`) confirma que a Ybus é simétrica.

```julia
@printf("  Elementos não-nulos : %d de %d\n", nnz_count, n^2)
@printf("  Esparsidade         : %.1f %%\n", sparsity)
```
- `@printf` imprime com **formato**: `%d` = inteiro, `%.1f` = real com 1 casa,
  `%%` = um sinal de % literal, `\n` = quebra de linha. Os valores vêm depois.

```julia
for i in 1:n, j in 1:n
    y = Y[i, j]
    if !iszero(y)
        push!(df_elem, (
            i, j, bus_order[i], bus_order[j],
            real(y), imag(y), abs(y), rad2deg(angle(y)),
        ))
    end
end
```
- `for i in 1:n, j in 1:n` é um **laço duplo** numa linha: para cada `i` de 1 a
  `n`, e cada `j` de 1 a `n` (varre toda a matriz).
- `Y[i, j]` acessa o elemento da linha `i`, coluna `j`.
- `if !iszero(y)`: só registra elementos não nulos.
- Para um número complexo `y`: `real(y)` e `imag(y)` são as partes real e
  imaginária; `abs(y)` é o módulo; `angle(y)` é o ângulo em radianos;
  `rad2deg(...)` converte para graus.

```julia
col_names = ["bus_$(b)" for b in bus_order]
df_G = DataFrame(real.(Y), col_names); insertcols!(df_G, 1, :bus => bus_order)
```
- `["bus_$(b)" for b in bus_order]`: compreensão + **interpolação** `$(b)`. Gera
  `["bus_1", "bus_2", ...]` para nomear as colunas.
- `real.(Y)` — repare no **ponto**: aplica `real` a **cada** elemento de `Y`,
  devolvendo a matriz só com as partes reais (condutâncias `G`). Sem o ponto não
  funcionaria.
- `DataFrame(matriz, nomes)` cria uma tabela a partir da matriz com aqueles nomes
  de coluna.
- `insertcols!(df_G, 1, :bus => bus_order)` insere, na **posição 1**, uma coluna
  chamada `bus`. `:bus` é um **Symbol** (um rótulo) e `:bus => bus_order` é um
  **par** "nome ⇒ conteúdo". O `!` indica que modifica `df_G`.

```julia
import Serialization
Serialization.serialize(joinpath(RESULTS_DIR, "02_ybus.jls"),
                        (Y = Y, bus_order = collect(bus_order)))
```
- `import Serialization` (em vez de `using`): traz só o nome do módulo; por isso
  chamamos `Serialization.serialize(...)` qualificando. Fizemos assim porque
  `serialize` existe em vários pacotes e `using` geraria ambiguidade.
- O que salvamos é uma **NamedTuple** `(Y = Y, bus_order = ...)` — guarda a matriz
  e a ordem das barras juntas, em formato binário, para outros scripts reusarem.

---

## 7. SCUtils.jl: módulos, despacho múltiplo e do-blocks

Arquivo: [julia/src/SCUtils.jl](../julia/src/SCUtils.jl). É o nosso **módulo**
utilitário, reaproveitado pelos scripts 05 e 06.

```julia
module SCUtils

using PowerSystems
...
export build_14bus, solve_pf!, load_PQ, scale_loads!, take_generator_offline!,
       zbus_short_circuit, base_current_kA
```
- `module SCUtils ... end` cria um **espaço de nomes** próprio. Tudo definido
  dentro pertence a `SCUtils`.
- O `using` dentro do módulo carrega o que ele precisa.
- `export ...` lista as funções que ficam **diretamente acessíveis** para quem
  fizer `using .SCUtils` (o ponto significa "módulo local deste projeto"). Funções
  não exportadas ainda existem, mas exigem o prefixo `SCUtils.`.

```julia
"Carrega o IEEE 14 barras (com dados dinâmicos), suprimindo warnings do caso."
function build_14bus()
    sys = Logging.with_logger(Logging.NullLogger()) do
        build_system(PSIDSystems, "14 Bus Base Case")
    end
    set_units_base_system!(sys, "SYSTEM_BASE")
    return sys
end
```
- A string isolada **antes** da função é uma **docstring** (documentação que
  aparece na ajuda do Julia).
- `function ... end` é a forma longa; `return sys` devolve o resultado.
- `Logging.with_logger(Logging.NullLogger()) do ... end` é um **do-block**: o
  bloco entre `do` e `end` é uma função anônima passada para `with_logger`. Aqui
  ele roda `build_system(...)` com um "logger nulo", **silenciando** os avisos de
  validação do caso. O valor do bloco (o sistema) é atribuído a `sys`.

```julia
function load_PQ(ld::StandardLoad)
    P = get_constant_active_power(ld) + get_current_active_power(ld) +
        get_impedance_active_power(ld)
    Q = ...
    return P, Q
end
load_PQ(ld) = (get_active_power(ld), get_reactive_power(ld))
```
- Mesmo padrão de **despacho múltiplo** do script 01, agora devolvendo **dois
  valores**: `return P, Q` devolve uma tupla `(P, Q)`. Quem chama pode escrever
  `P, Q = load_PQ(x)` para "desempacotar".

```julia
function scale_loads!(sys, factor)
    for ld in get_components(StandardLoad, sys)
        set_constant_active_power!(ld, get_constant_active_power(ld) * factor)
        ...
    end
    return sys
end
```
- Nome com `!`: **modifica** o sistema. Multiplica cada parcela de cada carga por
  `factor` (ex.: 0.6 = 60% da carga). Usa os "setters" `set_..._power!`.

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
- `==` compara igualdade. Se o gerador está na barra pedida, marca-o como
  indisponível (`set_available!(g, false)`).
- `get_bustype(b) == ACBusTypes.PV && set_bustype!(b, ACBusTypes.PQ)`:
  **curto-circuito** com `&&`. Só executa `set_bustype!` (converter a barra de PV
  para PQ) **se** a barra for do tipo PV. É um "if" em uma linha.

```julia
function base_current_kA(sys, bus_num)
    b = first(x for x in get_components(ACBus, sys) if get_number(x) == bus_num)
    return get_base_power(sys) / (sqrt(3) * get_base_voltage(b))
end
```
- `first(x for x in ... if cond)`: uma compreensão **com filtro** (`if`) dentro de
  `first(...)`. Percorre as barras, mantém as que satisfazem `get_number(x) ==
  bus_num` e pega a **primeira**. É um jeito enxuto de "achar a barra de número N".
- A conta é a fórmula da corrente de base: `I_base = S_base / (√3 · V_base)`.

```julia
function zbus_short_circuit(sys; fault_bus, z_fault = 0.0 + 0.0im, include_loads = false)
    ...
    idx_of = Dict(b => i for (i, b) in enumerate(bus_order))
    f = idx_of[fault_bus]
    ...
    V_pf = ComplexF64[get_magnitude(buses[b]) * cis(get_angle(buses[b])) for b in bus_order]
    ...
    for sg in get_components(ThermalStandard, sys)
        get_available(sg) || continue
        dyn = get_dynamic_injector(sg)
        dyn === nothing && continue
        ...
        Y[i, i] += 1 / z_sys
    end
    ...
    Z = inv(Y)
    If = V_pf[f] / (Z[f, f] + z_fault)
    Vpos = [V_pf[i] - (Z[i, f] / (Z[f, f] + z_fault)) * V_pf[f] for i in 1:n]
    ...
    return (; If, Zth = Z[f, f], Vpre = V_pf, Vpos, bus_order, Ibase_kA, scc_mva, idx_of)
end
```
Vários conceitos importantes:
- **Argumentos nomeados com padrão:** depois do `;`, `fault_bus` (obrigatório),
  `z_fault = 0.0 + 0.0im` (complexo, padrão zero → falta franca) e
  `include_loads = false`.
- `Dict(b => i for (i, b) in enumerate(bus_order))`: um **dicionário por
  compreensão** que mapeia "número da barra → posição na matriz". `enumerate` dá
  pares `(i, b)` = (posição, número da barra). Depois `f = idx_of[fault_bus]`
  descobre a posição da barra de falta.
- `ComplexF64[... for b in bus_order]`: compreensão **com tipo na frente**, força
  o resultado a ser `Vector{ComplexF64}`. `cis(θ)` = `cos θ + j·sen θ` = `e^{jθ}`;
  então `|V|·cis(ângulo)` reconstrói a tensão complexa pré-falta.
- `get_available(sg) || continue` e `dyn === nothing && continue`: pulam
  geradores fora de serviço ou sem modelo dinâmico (`===` é igualdade de
  identidade; `nothing` é o "vazio" de Julia).
- `Y[i, i] += 1 / z_sys`: soma `1/z` na **diagonal** (admitância do gerador para a
  terra). `+=` é "incrementa".
- `inv(Y)` inverte a matriz (Zbus = Ybus⁻¹). `Z[f, f]` é o elemento de Thévenin.
- `Vpos = [...]` calcula as tensões pós-falta de todas as barras por compreensão.
- `return (; If, Zth = Z[f, f], ...)`: devolve uma **NamedTuple**. O `(;` no
  início permite o atalho `If` (equivale a `If = If`); para os demais, damos nome
  explícito. Quem chama lê `r.If`, `r.Zth`, etc.

---

## 8. Novidades nos scripts 03–06

Os scripts seguintes reusam o que já vimos. Aqui ficam só os **conceitos novos**.

### Script 03 — [03_shortcircuit_static.jl](../julia/scripts/03_shortcircuit_static.jl)
```julia
@printf("%-16s%-7d%-12.5f%-9.1f%-12.5f\n", get_name(sg), bus_num, Xpp, Sdev, ...)
```
- Formatos de alinhamento: `%-16s` = texto alinhado à esquerda em 16 colunas;
  `%-12.5f` = real com 5 casas em 12 colunas. Serve para tabelas no terminal.

```julia
function short_circuit(Y_fault, V_pf, f, Zf)
    Z = inv(Y_fault)
    If = V_pf[f] / (Z[f, f] + Zf)
    Vpos = [V_pf[i] - (Z[i, f] / (Z[f, f] + Zf)) * V_pf[f] for i in 1:length(V_pf)]
    return (Z = Z, If = If, Vpos = Vpos, Zth = Z[f, f])
end
```
- Uma função **local** que encapsula o cálculo do curto e é chamada para as duas
  variantes (só geradores / geradores+cargas). `length(V_pf)` é o tamanho do vetor.

### Script 04 — [04_dynamic_simulation.jl](../julia/scripts/04_dynamic_simulation.jl)
```julia
Y_pre = SparseMatrixCSC{ComplexF32, Int}(ybus.data)
Y_fault = copy(Y_pre)
Yf_shunt = ComplexF32(1.0 / Z_FAULT)
Y_fault[f, f] += Yf_shunt
```
- `SparseMatrixCSC{ComplexF32, Int}(...)` é um **tipo paramétrico**: matriz esparsa
  cujos elementos são `ComplexF32` (complexo de precisão simples) e índices `Int`.
  Converte a Ybus para esse formato exigido pelo `NetworkSwitch`.
- `copy(Y_pre)` faz uma **cópia independente** (mexer em `Y_fault` não afeta
  `Y_pre`).
- `Y_fault[f, f] += Yf_shunt` insere a admitância de falta na diagonal da barra.

```julia
if_mag = [(T_FAULT <= t[k] < T_CLEAR) ? v7_mag[k] * abs(Yf_shunt) : 0.0
          for k in eachindex(t)]
```
- Compreensão com **ternário** dentro: para cada índice `k` dos tempos, se o
  instante está na janela da falta (`T_FAULT <= t[k] < T_CLEAR` — repare na
  **comparação encadeada**, permitida em Julia), calcula a corrente; senão, `0.0`.
- `eachindex(t)` dá os índices válidos do vetor `t`.

```julia
status = execute!(sim, IDA(); dtmax = 0.005, saveat = 0.005)
```
- `execute!` roda a simulação (o `!` modifica `sim`). `IDA()` cria o solver;
  `dtmax`/`saveat` são argumentos nomeados (passo máximo e intervalo de
  gravação).

```julia
settled = findall(k -> (T_FAULT + 0.03) <= v7_t[k] < T_CLEAR, eachindex(v7_t))
ifault_settled_pu = isempty(settled) ? 0.0 : mean(ifault_mag[settled])
```
- `findall(função, coleção)` devolve os **índices** onde a função é verdadeira. A
  função `k -> ...` é anônima. `mean(...)` (do pacote `Statistics`) tira a média;
  `ifault_mag[settled]` seleciona só os elementos naqueles índices.

```julia
plot!(p1, base.volt[FAULT_BUS]...; label = "sem FV", lw = 2)
```
- O `...` é **splat**: `base.volt[FAULT_BUS]` é a tupla `(tempos, valores)`, e
  `...` a "espalha" como dois argumentos para `plot!` (eixo x e eixo y).

### Script 06 — [06_solar_pv.jl](../julia/scripts/06_solar_pv.jl)
```julia
ActivePowerPI(; Kp_p = 2.0, Ki_p = 30.0, ωz = 0.132 * 2π * 50)
```
- Construção de um objeto por **argumentos nomeados** (`;` seguido de
  `nome = valor`). `2π` é "2 vezes π" — Julia permite escrever um número colado a
  uma constante (coeficiente literal). `ωz` usa a letra grega ω como nome.

```julia
pv_Imag = sqrt.(pv_Ir[2] .^ 2 .+ pv_Ii[2] .^ 2)
```
- **Broadcasting** em cadeia: `.^ 2` eleva cada elemento ao quadrado, `.+` soma
  elemento a elemento e `sqrt.(...)` tira a raiz de cada um. Calcula o módulo da
  corrente ponto a ponto: `√(Ir² + Ii²)`.

```julia
RenewableDispatch(; name = PV_NAME, available = true, bus = bus,
                  active_power = PV_P, ..., base_power = PV_S)
```
- Cria a usina FV preenchendo seus campos por nome. É assim que se constroem os
  componentes do PowerSystems (muitos campos, todos nomeados).

```julia
get_state_series(res, (g, :δ))
```
- `:δ` é um **Symbol** (rótulo do estado "ângulo do rotor"). Pede a série temporal
  daquele estado da máquina `g`. Aqui aparecem as letras gregas `δ` (delta) e `ω`
  (ômega) como nomes de estados — típico de engenharia.

---

## 9. Tabela de referência rápida de símbolos

| Símbolo / forma | Onde aparece | O que faz |
|-----------------|--------------|-----------|
| `# ...` / `#= ... =#` | cabeçalhos | comentário de linha / de bloco |
| `using X` | topo dos scripts | carrega o pacote X e suas funções exportadas |
| `import X` | `import Serialization` | carrega X; usa-se `X.func` (qualificado) |
| `const X = ...` | `const FAULT_BUS = 7` | define um nome que não muda |
| `f(x) = ...` | `load_P(ld) = ...` | função em forma curta (return implícito) |
| `function f(x) ... end` | `build_14bus()` | função em forma longa |
| `x -> ...` | `k -> v7_mag[k]*...` | função anônima |
| `f(...) do ... end` | `with_logger(...) do` | passa um bloco como função (do-block) |
| `nome!` | `push!`, `set_..._!` | função que **modifica** o argumento |
| `!cond` / `!iszero` | `count(!iszero, Y)` | "não" lógico / nega uma função |
| `::Tipo` | `ld::StandardLoad` | restringe o método àquele tipo (despacho) |
| `cond ? a : b` | janela de falta | condicional em uma expressão (ternário) |
| `a && b` / `a \|\| b` | `dyn === nothing && continue` | "e"/"ou" com curto-circuito |
| `===` / `==` | `dyn === nothing` / `== bus_num` | identidade / igualdade de valor |
| `.` (função/op) | `real.(Y)`, `a .+ b` | broadcasting: aplica elemento a elemento |
| `.campo` | `arc.from`, `r.If` | acessa campo de objeto/NamedTuple |
| `[a for x in v]` | nomes de coluna | compreensão (constrói coleção) |
| `Dict(k => v for ...)` | `idx_of` | dicionário por compreensão |
| `k => v` | `:bus => bus_order` | par chave→valor |
| `:nome` | `:bus`, `:δ` | Symbol (rótulo leve) |
| `"...$(x)..."` | `"bus_$(b)"` | interpolação de valor em string |
| `"..."^n` | `"="^70` | repete a string n vezes |
| `1:n` | `for i in 1:n` | intervalo (range) |
| `v[i]`, `M[i,j]` | em toda parte | indexação (começa em **1**) |
| `...` (splat) | `volt[bus]...` | espalha coleção em vários argumentos |
| `@macro` | `@printf`, `@__DIR__` | macro (transforma código) |
| `im`, `2π` | números | unidade imaginária; coeficiente literal |
| `Tipo{P}(...)` | `SparseMatrixCSC{ComplexF32,Int}(...)` | tipo paramétrico |
| `(; a, b = ...)` | retorno de `zbus_short_circuit` | NamedTuple (com atalho) |

---

### Para se aprofundar
- Documentação oficial: <https://docs.julialang.org/>
- "Noteworthy differences from other languages" (se você já conhece Python/MATLAB):
  <https://docs.julialang.org/en/v1/manual/noteworthy-differences/>
- A ajuda no REPL: digite `?` e o nome de uma função (ex.: `?push!`).
