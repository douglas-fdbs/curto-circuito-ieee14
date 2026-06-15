# Desenvolvimento do Trabalho — Estudo de Curto-Circuito no IEEE 14 Barras

**Disciplina:** Estudos Especiais em Engenharia Elétrica I — UFC
**Professores:** Lucas Silveira e Raimundo Furtado
**Tema:** Estudo de curto-circuito trifásico na barra 7 do sistema IEEE 14 barras
usando múltiplas abordagens computacionais.

Este documento descreve, passo a passo, como o trabalho está sendo desenvolvido:
ferramentas, ambiente, metodologia de cada etapa, resultados obtidos e o que
ainda falta.

---

## 1. O que a atividade pede × o que já temos

| # | Item solicitado no enunciado | Ferramenta | Status | Onde |
|---|------------------------------|-----------|--------|------|
| 1 | Montar a matriz de admitâncias nodal (Ybus) do IEEE 14 barras | PowerSystems.jl + PowerSystemCaseBuilder.jl | ✅ **Feito** | [02_ybus.jl](julia/scripts/02_ybus.jl) |
| 2 | Calcular correntes de curto e tensões para curto trifásico **franco na barra 7** via Ybus | Método Zbus (Julia) | ✅ **Feito** | [03_shortcircuit_static.jl](julia/scripts/03_shortcircuit_static.jl) |
| 3 | Modelar/simular no **ANAFAS** e comparar com a Ybus | ANAFAS | ⏳ **À parte** — os resultados da Ybus já estão prontos para a comparação | — |
| 4 | Simular curto na barra 7 com **PowerSimulationsDynamics.jl** (correntes, tensões em barras próximas, resposta transitória) | PSD.jl | ✅ **Feito** | [04_dynamic_simulation.jl](julia/scripts/04_dynamic_simulation.jl) |
| 5 | Comparar as **três abordagens** e discutir diferenças/causas | — | ⏳ **Parcial** — comparação Ybus × PSD.jl pronta; falta integrar o ANAFAS e consolidar numa seção única | seção 7 deste doc |
| 6 | Explorar **cenários de carga/geração** e conectar **geração solar FV** considerável, analisando o impacto no curto | PowerSystemCaseBuilder.jl / PSD.jl | ✅ **Feito** | [05_scenarios.jl](julia/scripts/05_scenarios.jl), [06_solar_pv.jl](julia/scripts/06_solar_pv.jl) |
| 7 | Relatório em **formato de artigo científico** + todos os códigos/arquivos | — | ⏳ Códigos e dados ✅ / **artigo a redigir** | `article/` |

**Resumo:** todo o núcleo computacional em Julia está concluído e validado
(itens 1, 2, 4, 6). Falta: (a) o ANAFAS — que será feito a parte —, (b) consolidar
a comparação das três abordagens (item 5) e (c) redigir o artigo (item 7).

---

## 2. Decisão de ferramentas: por que Julia

O enunciado sugere explicitamente o ecossistema **Sienna** (Julia):
`PowerSystems.jl`, `PowerSystemCaseBuilder.jl` e `PowerSimulationsDynamics.jl`.
Esses pacotes são nativos em Julia e **não têm equivalente em Python** para a
simulação dinâmica transitória. Por isso, todo o trabalho computacional foi feito
em **Julia**.

---

## 3. Ambiente e reprodutibilidade

| Componente | Versão | Observação |
|-----------|--------|-----------|
| Julia | 1.12.6 | instalado via `juliaup` |
| PowerSystems.jl | 5.10.0 | estruturas de dados |
| PowerSystemCaseBuilder.jl | 2.2.1 | carrega o IEEE 14 barras |
| PowerSimulationsDynamics.jl | 0.16.0 | simulação dinâmica (DAE) |
| PowerNetworkMatrices.jl | 0.20.0 | Ybus |
| PowerFlows.jl | 0.16.4 | fluxo de potência (cenários) |
| Sundials | 6.2.1 | solver IDA |

O ambiente Julia é **isolado** no projeto (`julia/Project.toml` + `Manifest.toml`),
equivalente a um ambiente virtual. Para reproduzir:

```bash
export PATH="$HOME/.juliaup/bin:$PATH"
cd julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'   # 1ª vez: instala tudo
julia --project=. scripts/01_load_system.jl            # roda um script
```

O primeiro carregamento dos pacotes leva ~1–2 min (pré-compilação).

---

## 4. Estrutura de pastas

```
TRABALHO_FINAL/
├── README.md                          ← este documento (o quê e por quê)
├── COMPARACAO_ANAFAS.md               ← metodologia da comparação Ybus×PSD×ANAFAS
├── julia/
│   ├── Project.toml / Manifest.toml   ← ambiente isolado
│   ├── src/SCUtils.jl                 ← módulo utilitário (Zbus, fluxo, cenários)
│   └── scripts/
│       ├── 01_load_system.jl          ← carrega e inventaria o sistema
│       ├── 02_ybus.jl                 ← matriz de admitâncias nodal
│       ├── 03_shortcircuit_static.jl  ← curto franco via Zbus
│       ├── 04_dynamic_simulation.jl   ← curto dinâmico (PSD.jl)
│       ├── 05_scenarios.jl            ← cenários de carga/geração
│       ├── 06_solar_pv.jl             ← impacto da geração solar FV
│       └── 07_export_latex.jl         ← exporta matrizes/tabelas LaTeX p/ o artigo
├── data/
│   ├── results/                       ← CSVs com todos os resultados
│   ├── figures/                       ← figuras (PNG)
│   └── headquarters/                  ← artefatos formatados p/ o artigo
│       ├── latex/                     ← matrizes e tabelas em LaTeX (\input no Overleaf)
│       └── txt/                       ← mesmas matrizes em ASCII (visual)
├── others/
│   └── GUIA_JULIA.md                  ← tutorial didático da linguagem Julia
│                                         (para quem nunca usou Julia)
└── article/                           ← artigo científico (a redigir)
```

> 📘 **Quem não conhece Julia** deve ler antes o
> [others/GUIA_JULIA.md](others/GUIA_JULIA.md): um tutorial da linguagem do zero,
> explicando os scripts deste projeto linha a linha.
>
> 🔬 **Comparação com o ANAFAS** (itens 3 e 5): a metodologia, as premissas e os
> artefatos LaTeX estão em [COMPARACAO_ANAFAS.md](COMPARACAO_ANAFAS.md).

---

## 5. O sistema IEEE 14 barras (dados usados)

Carregado via `build_system(PSIDSystems, "14 Bus Base Case")`:

- **Base:** 100 MVA, 60 Hz.
- **14 barras** — tensões base: 69 kV (barras 1–5), 13,8 kV (6, 7, 9–14), 18 kV (8).
- **5 geradores síncronos** (modelo `RoundRotorQuadratic` + AVR `ESAC1A`) nas barras
  **1, 2, 3, 6, 8**. Reatâncias subtransitórias X″d (na base do sistema):
  gen1≈0,037 · gen2≈0,217 · gen3≈0,217 · gen6≈0,48 · gen8≈0,48.
- **11 cargas** (modelo ZIP `StandardLoad`), totalizando ~259 MW.
- **16 linhas** e **4 transformadores** (1 de 2 enrolamentos + 3 com tap).
- **Barra 7:** barra de transferência (sem carga e sem geração), conectada às
  barras 4 e 8 (transformadores) e 9 (linha). É o ponto de curto do estudo.

---

## 6. Passo a passo de cada etapa

### Etapa 1 — Carregamento e inventário do sistema · [01_load_system.jl](julia/scripts/01_load_system.jl)
**O que faz:** carrega o sistema e lista todos os componentes (barras, linhas,
transformadores, geradores estáticos e dinâmicos, cargas), exportando cada
inventário para CSV.
**Saídas:** `data/results/01_*.csv` (barras, linhas, transformadores, geradores,
injetores dinâmicos, cargas).
**Para que serve:** documentar os dados de entrada e confirmar a topologia.

### Etapa 2 — Matriz de admitâncias nodal · [02_ybus.jl](julia/scripts/02_ybus.jl)
**O que faz:** monta a Ybus com `PowerNetworkMatrices.jl` (`Ybus(sys)`), analisa
suas propriedades e exporta a matriz completa.
**Método:** Ybus = combinação das admitâncias série e shunt de linhas e
transformadores, indexada pela numeração das barras.
**Resultados:** matriz **14×14**, **72,4 % esparsa**, **simétrica**, 54 elementos
não-nulos.
**Saídas:** `02_ybus_G_real.csv` (condutâncias), `02_ybus_B_imag.csv`
(susceptâncias), `02_ybus_elements.csv` (lista de não-nulos), `02_ybus.jls`.
**Atende:** item 1 do enunciado.

### Etapa 3 — Curto-circuito franco na barra 7 (método Zbus) · [03_shortcircuit_static.jl](julia/scripts/03_shortcircuit_static.jl)
**O que faz:** calcula a corrente de curto e as tensões em todas as barras para
uma falta trifásica **franca** na barra 7, pelo método da matriz de impedâncias
(Zbus) e superposição.
**Método:**
1. Acrescenta-se à Ybus da rede a **reatância subtransitória X″d** de cada gerador
   como admitância shunt para a terra (modelo clássico de curto).
2. Inverte-se a matriz: **Z = Y⁻¹**.
3. Falta franca na barra *f*=7: `I_falta = V_pré[f] / Z[f,f]` e
   `V_pós[i] = V_pré[i] − (Z[i,f]/Z[f,f])·V_pré[f]`.
4. Tensões pré-falta = solução do fluxo de potência do caso base.

Foram calculadas **duas variantes**: (A) **só geradores** (clássica) e (B)
**geradores + cargas** como impedância constante.

**Resultados (barra 7):**

| Variante | Z_thévenin (pu) | I_falta | SCC |
|----------|-----------------|---------|-----|
| A — só geradores (clássico) | 0,0127 + j0,1576 (\|Z\|=0,158) | **6,601 pu = 27,62 kA** | 689 MVA |
| B — geradores + cargas | \|Z\|=0,151 | 6,902 pu = 28,87 kA | 720 MVA |

**Contribuições de corrente para a falta** (variante A): barra 4 → 12,59 kA,
barra 8 → 7,52 kA, barra 9 → 7,53 kA. **A soma confere com a corrente total**
(validação do método).

**Tensões durante a falta (variante A, módulo em pu):** barra 7 = 0 (franco);
vizinhas afundam — barra 9 ≈ 0,20; barra 8 ≈ 0,32; barra 4 ≈ 0,62.

**Saídas:** `03_fault_voltages.csv`, `03_fault_contributions.csv`, `03_summary.csv`.
**Atende:** item 2 do enunciado (e fornece os dados para a comparação com o ANAFAS, item 3).

> **Nota metodológica importante:** a Ybus para o curto é montada com
> `include_constant_impedance_loads = false`, para que o modelo "só geradores"
> não inclua implicitamente a parcela de impedância das cargas ZIP. As cargas
> entram apenas, e explicitamente, na variante B.

### Etapa 4 — Curto-circuito dinâmico · [04_dynamic_simulation.jl](julia/scripts/04_dynamic_simulation.jl)
**O que faz:** simula a resposta transitória do sistema ao curto na barra 7 com
`PowerSimulationsDynamics.jl`, modelando a falta pela perturbação `NetworkSwitch`
(insere uma admitância shunt elevada na barra 7 na Ybus).
**Dois casos** (por uma limitação numérica do solver — ver nota):

- **Caso A — falta quase franca (Z=10⁻³ pu), permanente, janela curta (0–1,6 s):**
  captura a corrente de falta e os afundamentos, comparáveis ao método estático.
  Resultado: V7 → 0,005 pu; **I_falta ≈ 23,65 kA**.
- **Caso B — falta severa (Z=5×10⁻² pu) eliminada em 100 ms:** mostra a resposta
  transitória completa (ângulos e velocidades dos rotores, recuperação das tensões).
  Resultado: V7 → 0,27 pu; **I_falta ≈ 23,33 kA**.

**Saídas:** figuras [04a_corrente_falta](data/figures/04a_corrente_falta.png),
[04b_tensoes](data/figures/04b_tensoes.png),
[04b_angulos_rotor](data/figures/04b_angulos_rotor.png),
[04b_velocidades](data/figures/04b_velocidades.png); séries `04A_*`, `04B_*` e `04_summary.csv`.
**Atende:** item 4 do enunciado.

> **Nota numérica:** o solver DAE (IDA) não converge na **eliminação brusca** de
> uma falta quase franca, porque a tensão da barra 7 (barra de transferência)
> precisa saltar ~18× instantaneamente. Por isso a falta franca é analisada de
> forma permanente (Caso A) e a recuperação transitória usa uma falta severa
> porém eliminável (Caso B). Ambas são curtos trifásicos na barra 7.

### Etapa 5 — Cenários de carga e geração · [05_scenarios.jl](julia/scripts/05_scenarios.jl)
**O que faz:** avalia como variações de carga e geração afetam o curto na barra 7.
Para cada cenário, ajusta carga/geração, **resolve o fluxo de potência**
(`PowerFlows.jl`) e recalcula o curto pelo método Zbus.

**Resultados (modelo clássico, só geradores):**

| Cenário | Carga | I_falta | Z_thévenin |
|---------|-------|---------|-----------|
| Base | 259 MW | 27,58 kA | 0,1581 |
| Carga leve (60 %) | 155 MW | 27,87 kA | 0,1581 |
| Carga pesada (140 %) | 363 MW | 27,27 kA | 0,1581 |
| Gerador da barra 2 fora | 259 MW | 26,77 kA | 0,1626 |

**Interpretação:** no modelo clássico, o Zth é **fixo** entre os cenários de carga
(a rede e os geradores não mudam); a corrente varia apenas pela **tensão
pré-falta** (carga leve → tensão maior → corrente maior). Já no modelo com cargas
a tendência se inverte (mais carga → mais caminhos → menor Zth → maior corrente).
**Retirar um gerador** eleva o Zth e **reduz** claramente a corrente de curto.

**Saídas:** `05_scenarios_summary.csv`, figuras
[05_corrente_por_cenario](data/figures/05_corrente_por_cenario.png) e
[05_perfil_tensoes_cenarios](data/figures/05_perfil_tensoes_cenarios.png).
**Atende:** primeira parte do item 6.

### Etapa 6 — Impacto da geração solar fotovoltaica · [06_solar_pv.jl](julia/scripts/06_solar_pv.jl)
**O que faz:** conecta uma usina solar FV de **60 MW** (inversor dinâmico
*grid-following*: conversor médio + controles PI de P/Q + controle de corrente +
PLL + filtro LCL) na **barra 4** e compara a resposta ao curto na barra 7, **com e
sem** a FV.

**Resultados:**

| Caso | I_falta na barra 7 |
|------|--------------------|
| Sem FV | 21,51 kA |
| Com FV | 21,92 kA (**+1,9 %**) |

**Insight principal:** a corrente injetada pela **própria FV** durante a falta é de
apenas **≈ 1,1 pu** da sua nominal — o inversor é **limitado em corrente**. Uma
máquina síncrona de mesmo porte injetaria várias vezes a nominal (corrente
subtransitória). Por isso a FV pouco eleva o nível de curto e **não fornece
inércia** — exatamente a preocupação central da integração de fontes baseadas em
inversor (IBR).

**Saídas:** figuras [06_tensao_bus7](data/figures/06_tensao_bus7.png),
[06_tensao_pv](data/figures/06_tensao_pv.png),
[06_velocidade_ref](data/figures/06_velocidade_ref.png),
[06_resposta_fv](data/figures/06_resposta_fv.png); séries `06_*.csv`.
**Atende:** segunda parte do item 6.

> **Nota numérica:** o inversor *grid-following* não tolera a eliminação brusca da
> falta nem afundamentos muito profundos (o PLL perde sincronismo). Por isso a
> comparação usa uma falta **permanente** em janela curta e a FV foi conectada na
> barra 4 (69 kV, afundamento menos severo). Isso captura justamente o
> comportamento "durante o curto", que é o pedido no enunciado.

---

## 7. Comparação consolidada das abordagens (item 5)

Corrente de curto-circuito trifásico na barra 7. O cálculo estático é apresentado
em **quatro variantes** (tensão pré-falta *flat* 1,0 pu × do fluxo; com × sem
cargas), para casar com qualquer configuração do ANAFAS — ver
[COMPARACAO_ANAFAS.md](COMPARACAO_ANAFAS.md).

| Abordagem | Corrente de falta | \(\varepsilon\) vs ANAFAS | Observação |
|-----------|-------------------|---------------------------|-----------|
| **ANAFAS** (referência) | **26,88 kA** (6,426 pu) | — | ANAFAS 8.1, curto trifásico na barra 7 |
| Zbus — *flat*, sem carga | 26,46 kA (6,324 pu) | **−1,6 %** | **melhor concordância** (ANAFAS clássico) |
| Zbus — *flat*, carga Z | 27,73 kA | +3,1 % | cargas como impedância constante |
| Zbus — fluxo, sem carga | 27,58 kA | +2,6 % | tensão pré-falta do fluxo de potência |
| Zbus — fluxo, carga Z | 28,84 kA | +7,3 % | mais realista |
| Dinâmico PSD.jl — falta ~franca | 23,65 kA | −12,0 % | corrente já amortecida (não é o pico) |
| Dinâmico PSD.jl — falta severa eliminável | 23,33 kA | — | — |

**Validação (ANAFAS × Zbus *flat/sem carga*):** corrente **−1,6 %**, tensões nas
barras **0–4 %** (médio 2,1 %), contribuições dos ramos **≤ 4,1 %**, e SCC
praticamente idêntico (632,3 vs 632,4 MVA). A soma fasorial das contribuições fecha
com \(I_f\) (KCL) em ambas as ferramentas. Tabelas prontas em
[data/headquarters/latex/](data/headquarters/latex/) (`tab_corrente_falta`,
`tab_tensoes_falta`, `tab_contribuicoes`), com erros calculados.

Em todas as variantes a impedância de Thévenin sem carga é a mesma (\|Z₇₇\|=0,158),
pois **independe** da tensão pré-falta; a corrente muda só pela tensão no ponto. As
pequenas diferenças residuais vêm das premissas do ANAFAS (tensão pré-falta do
`.pwf` ≈ 0,984 e inclusão de cargas/shunts), que quase se cancelam.

**Por que o dinâmico (PSD.jl) fica abaixo?** O método Zbus e o ANAFAS dão o **pico
subtransitório** (superposição com \(X''_d\)); o PSD.jl integra o modelo dinâmico
completo (com AVR), e a corrente "estabilizada" durante a falta já é amortecida —
por isso **menor** (−12 %). É uma diferença **física esperada**, não erro: A ≈ C
(mesma família) e B < A, com B fornecendo em troca a resposta no tempo.

---

## 8. Decisões e notas técnicas relevantes (registro)

- **Linguagem:** Julia puro. A camada Python (cogitada no início) foi **removida**
  por não ser utilizada — os pacotes obrigatórios são todos Julia.
- **Ybus para curto:** sempre `include_constant_impedance_loads = false`, para
  separar claramente o efeito de geradores e cargas.
- **`NetworkSwitch` exige a Ybus em `ComplexF32`** e na mesma convenção interna do
  PSD.jl (cargas de impedância constante tratadas como injeção).
- **Cargas convertidas para impedância constante** antes das simulações dinâmicas
  (evita corrente infinita de carga de potência constante sob tensão baixa).
- **Limite numérico do IDA** na eliminação de faltas muito profundas → estratégia
  de dois casos (permanente + eliminável), documentada nas etapas 4 e 6.

---

## 9. O que falta para concluir o trabalho

1. **ANAFAS (item 3):** modelar o IEEE 14 barras e obter a corrente/tensões de
   curto na barra 7 *(você fará à parte)*.
2. **Comparação final das três abordagens (item 5):** consolidar Ybus × PSD.jl ×
   ANAFAS em tabela/figura única e discutir as causas das diferenças.
3. **Artigo científico (item 7):** redigir em `article/` no formato de paper
   (introdução, metodologia, resultados, discussão, conclusão), reaproveitando as
   figuras e tabelas já geradas.

Todos os códigos e arquivos de simulação já constituem o "produto" exigido pelo
enunciado e estão organizados em `julia/` e `data/`.
