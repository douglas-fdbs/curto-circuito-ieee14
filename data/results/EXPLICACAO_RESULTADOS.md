# Explicação dos resultados — `data/results/`

> **Arquivo temporário** (pode apagar depois). Documenta, arquivo por arquivo e
> coluna por coluna, o que cada CSV da pasta `data/results/` contém e significa.
> Curto trifásico estudado: **barra 7** do IEEE 14 barras. Base do sistema:
> **100 MVA**. Tensões de barra em **pu** (sobre a tensão nominal de cada barra).

Convenção de prefixos (qual script gera cada um):
- `01_*` → [01_load_system.jl](julia/scripts/01_load_system.jl) — inventário do sistema.
- `02_*` → [02_ybus.jl](julia/scripts/02_ybus.jl) — matriz Ybus.
- `03_*` → [03_shortcircuit_static.jl](julia/scripts/03_shortcircuit_static.jl) — curto estático (Zbus).
- `04_*` → [04_dynamic_simulation.jl](julia/scripts/04_dynamic_simulation.jl) — curto dinâmico (PSD.jl).
- `05_*` → [05_scenarios.jl](julia/scripts/05_scenarios.jl) — cenários de carga/geração.
- `06_*` → [06_solar_pv.jl](julia/scripts/06_solar_pv.jl) — impacto de usina fotovoltaica.

---

## 1. Inventário do sistema (`01_*`)

São a "fotografia" do IEEE 14 carregado do PowerSystemCaseBuilder (`"14 Bus Base Case"`).
Servem para confirmar que o caso bate com o IEEE 14 canônico (UW/MATPOWER).

### `01_buses.csv` — as 14 barras

| coluna | significado |
|---|---|
| `number` | número da barra (1–14) |
| `name` | nome ("BUS 01"…) |
| `bustype` | tipo no fluxo de potência: `REF` (slack/referência), `PV` (gerador, controla tensão), `PQ` (carga, P e Q fixos) |
| `base_voltage` | tensão nominal da barra, em **kV** |
| `vm_pu` | módulo da tensão na solução do fluxo, em **pu** |
| `va_rad` | ângulo da tensão, em **radianos** |

Leitura linha a linha (destaques):
- **Barra 1** = `REF`, 69 kV, V = 1,06 pu, ângulo 0 → é a **slack** (referência angular).
- Barras **2, 3, 6, 8** = `PV` → têm gerador controlando tensão (1,04 / 1,01 / 1,06 / 1,08 pu).
- Demais = `PQ` (cargas). **Barra 7** = PQ, 13,8 kV, V=1,04377 pu, ângulo −0,1812 rad (≈ −10,38°). É a barra onde aplicamos o curto.
- Note os **níveis de tensão**: 69 kV (barras 1–5), 13,8 kV (6,7,9–14) e 18 kV (barra 8). Os transformadores fazem a conexão entre eles.
- A barra 7 não tem gerador nem carga própria — é um **nó de transferência** (só conecta transformadores/linha), o que a torna interessante para estudo de curto.

### `01_lines.csv` — as 16 linhas de transmissão

| coluna | significado |
|---|---|
| `name` | nome do ramo (`BUS xx-BUS yy-i_1`) |
| `from_bus` / `to_bus` | barras de origem e destino |
| `r_pu` | resistência série, em pu (base 100 MVA) |
| `x_pu` | reatância série, em pu |
| `b_pu` | susceptância shunt total da linha (modelo π), em pu |
| `rating` | limite de carregamento da linha, em pu (≈ MVA/100) |

Pontos a observar:
- A linha **7–9** tem `r_pu = 0` e `x_pu = 0,11001`: é puramente indutiva. (Na verdade muitos "ramos" 7–x são transformadores; ver arquivo abaixo.)
- `b_pu` não-nulo só nas linhas de 69 kV (efeito capacitivo das linhas longas); nas de 13,8 kV é 0.
- `rating` alto (ex.: 27,4 na linha 4–5) = linha robusta; baixo (3,1 na 13–14) = ramo fraco.

### `01_transformers.csv` — os 4 transformadores

| coluna | significado |
|---|---|
| `name` | nome do ramo |
| `type` | `Transformer2W` (transformador comum) ou `TapTransformer` (com tap/derivação fora do nominal) |
| `from_bus` / `to_bus` | barras conectadas |
| `r_pu` / `x_pu` | resistência e reatância, em pu |

Leitura:
- **8→7** `Transformer2W`, x=0,17615 — liga o gerador da barra 8 (18 kV) à barra de falta 7.
- **4→7**, **4→9**, **5→6** são `TapTransformer` (tap ≠ 1). **Isso é importante para o curto**: os taps fora do nominal causam uma pequena circulação de corrente que faz a soma fasorial das contribuições não fechar exatamente na variante "flat" (ver `03_fault_contributions`).
- Todos têm `r_pu = 0` (transformadores idealizados, só reatância).

### `01_generators.csv` — os 5 geradores

| coluna | significado |
|---|---|
| `name` | identificador (`generator-<barra>-1`) |
| `type` | `ThermalStandard` (modelo estático de máquina) |
| `bus` | barra onde está conectado |
| `P_pu` / `Q_pu` | potência ativa/reativa **despachada** na solução do fluxo, em pu (base 100 MVA) |
| `rating` | capacidade aparente da máquina (≈ 100 → limite operacional usado) |
| `base_power` | **MVA base da própria máquina** (importante para converter X″d!) |

Leitura (essencial para o curto):
- **generator-1-1** (barra 1, slack): P=1,9333 pu = 193,3 MW, base 615 MVA → é o **gerador grande** que fecha o balanço.
- **generator-2-1** (barra 2): base 60 MVA; **3-1** base 60; **6-1** base 25; **8-1** base 25.
- O `base_power` é o que liga estes dados aos X″d que você inseriu no ANAFAS: o X″d é dado na base da máquina e depois convertido para 100 MVA. Ex.: g1 X″d=0,23 @615 MVA → 0,0374 @100 MVA.

### `01_loads.csv` — as 11 cargas

| coluna | significado |
|---|---|
| `name` | identificador da carga |
| `type` | `StandardLoad` (modelo ZIP: parcela P constante, I constante, Z constante) |
| `bus` | barra da carga |
| `P_pu` / `Q_pu` | potência ativa/reativa consumida, em pu |

Leitura:
- Maior carga: **barra 3** (load31) = 0,942 pu = **94,2 MW**.
- Soma de todas: **≈ 259 MW** — confere com o IEEE 14 canônico (UW/UTFPR). É o que valida que estamos no caso certo.
- Para o **curto clássico** essas cargas são desprezadas (ou viram impedância constante); por isso temos as duas variantes "sem carga" e "com carga Z".

### `01_dynamic_injectors.csv` — modelos dinâmicos das máquinas

| coluna | significado |
|---|---|
| `name` | gerador correspondente |
| `type` | a "pilha" de modelos dinâmicos acoplada (usada só no script 04) |

Leitura do tipo `DynamicGenerator{RoundRotorQuadratic, SingleMass, ESAC1A, TGFixed, PSSFixed}`:
- `RoundRotorQuadratic` = modelo de **máquina** de rotor liso (com saturação quadrática) — é daqui que sai o X″d usado no transitório.
- `SingleMass` = modelo de **eixo** (uma massa: inércia H).
- `ESAC1A` = **regulador de tensão (AVR)** — controla a excitação.
- `TGFixed`/`GasTG` = **regulador de velocidade/turbina** (g1 tem turbina a gás `GasTG`).
- `PSSFixed` = **estabilizador (PSS)** fixo/desativado.
- Esses modelos só atuam no script 04 (dinâmico); no estático (03) usamos só o X″d.

---

## 2. Matriz de admitâncias (`02_*`)

### `02_ybus_elements.csv` — Ybus em lista (formato esparso)

A Ybus é a matriz 14×14 que relaciona injeções de corrente e tensões nodais
(**I = Y·V**). Aqui ela vem como **lista de elementos não-nulos** (cada linha = uma posição (i,j)).

| coluna | significado |
|---|---|
| `i`, `j` | índices da posição na matriz (linha, coluna) |
| `bus_i`, `bus_j` | barras correspondentes |
| `G` | parte real (condutância), em pu |
| `B` | parte imaginária (susceptância), em pu |
| `mag` | módulo do elemento complexo, `√(G²+B²)` |
| `ang_deg` | ângulo do elemento, em graus |

Como interpretar:
- **Elementos da diagonal (i=j)**: soma de todas as admitâncias que chegam à barra. Ex.: `2,2` → G=9,738, B=−30,398. (Esta é a Ybus *do sistema*, **com** as cargas como impedância constante — por isso G[2,2] não é zero.)
- **Elementos fora da diagonal (i≠j)**: o **negativo** da admitância do ramo entre as barras i e j. Ex.: `1,2` → −4,999 + j15,263 = −(admitância da linha 1–2).
- **Posição vazia** (par i,j ausente) = não há ramo direto entre as barras → na matriz visual aparece como `.` (zero).
- Os ramos que são **transformadores idealizados** têm G=0 e ângulo ±90° (puramente reativos). Ex.: `4,7` → 0 + j4,8895, ang=90°.
- B é **negativo na diagonal** e **positivo fora** (convenção de matriz de admitância nodal indutiva).

> A versão "visual" (matriz 14×14 desenhada) está em
> [data/headquarters/txt/ybus_G.txt](data/headquarters/txt/ybus_G.txt),
> [ybus_B.txt](data/headquarters/txt/ybus_B.txt) e
> [ybus_modulo.txt](data/headquarters/txt/ybus_modulo.txt).
> (Há também `02_ybus.jls` — a matriz serializada em binário Julia, para reuso pelos scripts.)

---

## 3. Curto-circuito estático — método Zbus (`03_*`)

Método clássico de superposição: monta-se a Ybus **de rede** (sem cargas) + reatâncias
subtransitórias dos geradores, inverte-se para obter a Zbus (**Z = Y⁻¹**), e o curto
trifásico franco na barra 7 dá **If = V_pré(7) / Z₇₇** (Thévenin).

### `03_summary.csv` — resumo do curto (duas variantes A e B)

Formato "chave-valor" (`grandeza`, `valor`). Sufixos **_A** e **_B**:
- **A** = só geradores (modelo clássico, cargas desprezadas).
- **B** = geradores + cargas como impedância constante.

| grandeza | significado |
|---|---|
| `If_pu_A` = 6,601 | corrente de falta na barra 7, em pu (base do nó) — variante A |
| `If_kA_A` = 27,62 | a mesma corrente em **kA** (base 13,8 kV → Ibase≈4,184 kA) |
| `Zth_abs_A` = 0,1581 | módulo da impedância de Thévenin vista da barra 7 (Z₇₇) |
| `SCC_MVA_A` = 689,0 | potência de curto-circuito (Short-Circuit Capacity) = √3·V·If |
| `..._B` = 6,902 / 28,87 / 0,1512 / 720,4 | idem, variante com cargas |

Leitura: incluir as cargas (B) **aumenta** a corrente de curto (Zth menor, mais
caminhos de corrente). A diferença A→B é ~4,5%.

### `03_fault_contributions.csv` — de onde vem a corrente de curto

Quais ramos alimentam a falta na barra 7 (KCL: a soma deve dar If).

| coluna | significado |
|---|---|
| `from_bus` | barra de onde a contribuição flui para a 7 |
| `I_pu` | corrente da contribuição, em pu |
| `I_kA` | a mesma em kA |

Leitura:
- **Barra 4 → 7**: 3,009 pu (12,59 kA) — maior contribuinte (vem dos geradores 1, 2, 3 via rede de 69 kV).
- **Barra 8 → 7**: 1,798 pu (7,52 kA) — gerador 8 direto pelo transformador.
- **Barra 9 → 7**: 1,800 pu (7,53 kA).
- Soma ≈ If (validação por KCL). *Nota:* na variante "flat" os taps causam ~1–2% de não-fechamento (discutido na memória/COMPARACAO).

### `03_fault_voltages.csv` — tensões antes e durante o curto

| coluna | significado |
|---|---|
| `bus` | barra |
| `Vpre_pu` | tensão **pré-falta** (antes do curto), em pu |
| `VA_pu` | tensão **durante o curto**, variante A (sem cargas), em pu |
| `VB_pu` | tensão durante o curto, variante B (com cargas), em pu |
| `VA_ang` / `VB_ang` | ângulos correspondentes, em graus |

Leitura:
- **Barra 7** (a faltosa): `VA_pu ≈ 0` → tensão colapsa a zero no curto franco. ✔
- Barras vizinhas afundam muito: barra 9 cai para 0,198 pu, barra 8 para 0,317 pu.
- Barras elétricas distantes (1, 2) seguram melhor a tensão (0,97 / 0,86 pu).
- O afundamento é o "raio de influência" do curto — útil para coordenação de proteção.

> (`03_results.jls` é o objeto completo serializado, para reuso pelos scripts.)

---

## 4. Curto-circuito dinâmico — PowerSimulationsDynamics.jl (`04_*`)

Aqui o curto é **simulado no tempo** (resolvendo as EDOs das máquinas), não por
superposição. Dois casos foram simulados:
- **Caso A**: falta franca (Z=0,001) **permanente**.
- **Caso B**: falta severa (Z=0,05) **eliminada** após 100 ms.

### `04_summary.csv` — resumo dos dois casos

| coluna | significado |
|---|---|
| `caso` | "A (franca, permanente)" ou "B (severa, eliminada)" |
| `z_fault_pu` | impedância da falta aplicada |
| `V7_min_pu` | tensão mínima atingida na barra 7 |
| `If_pu` / `If_kA` | corrente de falta (regime dinâmico) |
| `status` | `SIMULATION_FINALIZED` = convergiu |

Leitura:
- Caso A: V7 → 0,005 pu (quase zero), If ≈ **23,65 kA**.
- Caso B: V7 → 0,269 pu (falta menos severa), If ≈ 23,33 kA.
- **Por que ~23,6 kA < 27,6 kA do estático?** O valor dinâmico é a corrente já
  com a resposta das máquinas/AVR (não o pico subtransitório instantâneo). A
  diferença é **física e esperada**, não erro — deve ser discutida no artigo.

### `04A_tensoes_durante_falta.csv` — perfil de tensão no Caso A

| coluna | significado |
|---|---|
| `bus` | barra |
| `V_durante_pu` | tensão durante a falta permanente, em pu |

É o "retrato" do afundamento (análogo a `VA_pu` do estático). Barra 7 = 0,0057 pu.
Compare com `03_fault_voltages.csv` — os perfis batem bem (valida estático × dinâmico).

### `04B_dynamic_voltages.csv` — tensões ao longo do tempo (Caso B)

Série temporal: ~1500 linhas (de 0 a ~15 s, passo ~0,01 s).

| coluna | significado |
|---|---|
| `time` | tempo, em segundos |
| `V_bus1` … `V_bus14` | tensão de cada barra naquele instante, em pu |

Leitura:
- Linhas iniciais (t<momento da falta) = regime permanente (valores ~ pré-falta).
- No instante da falta as tensões caem; após a eliminação (100 ms) elas se
  recuperam e oscilam até reestabilizar. É a curva para **gráficos de afundamento/recuperação**.

### `04B_dynamic_machine_states.csv` — estados das máquinas no tempo

| coluna | significado |
|---|---|
| `time` | tempo, em s |
| `delta_generator-X` | ângulo do rotor δ da máquina X (rad) — posição angular |
| `omega_generator-X` | velocidade angular ω da máquina X (pu; 1,0 = síncrona) |

Leitura:
- `omega` perto de 1,0 = máquina em sincronismo. Desvios durante a falta mostram
  aceleração/desaceleração dos rotores → base para análise de **estabilidade transitória**.
- `delta` crescente sem retorno indicaria perda de sincronismo (não é o caso aqui).

---

## 5. Cenários de carga e geração (`05_*`)

### `05_scenarios_summary.csv` — curto na barra 7 em 4 cenários

| coluna | significado |
|---|---|
| `cenario` | Base / Carga leve (60%) / Carga pesada (140%) / Gerador b2 fora |
| `carga_total_MW` | carga total do sistema no cenário |
| `V7_pre_pu` | tensão pré-falta na barra 7 |
| `Zth_abs_pu` | impedância de Thévenin (só geradores) |
| `If_pu` / `If_kA` | corrente de curto — modelo só geradores |
| `SCC_MVA` | potência de curto-circuito |
| `If_cargas_pu` / `If_cargas_kA` | corrente de curto — modelo com cargas Z |

Leitura (insights):
- Nos 3 cenários de carga, **Zth é idêntico** (0,1581): a rede e os geradores não
  mudam, só a tensão pré-falta. If varia só por causa de V7_pré → carga leve dá
  V7 maior → If um pouco maior (27,87 kA) que carga pesada (27,27 kA).
- **Gerador da barra 2 fora**: Zth **sobe** (0,1626) → If **cai** para 26,77 kA.
  Tirar uma fonte de curto reduz a corrente de falta. ✔
- No modelo *com cargas*, a tendência se inverte (mais carga → mais caminhos → If maior).

---

## 6. Impacto da usina fotovoltaica (`06_*`)

Estuda o efeito de uma usina FV (inversor *grid-following*, 60 MW) na barra 4
sobre o curto na barra 7.

### `06_summary.csv` — corrente de curto com e sem FV

| coluna | significado |
|---|---|
| `caso` | "sem FV" / "com FV" |
| `If_pu` / `If_kA` | corrente de curto na barra 7 |

Leitura: If passa de 21,51 → 21,92 kA (**+1,9% apenas**). A FV quase não
contribui para o curto — insight central do trabalho.

### `06_pv_response.csv` — resposta do inversor durante a falta

Série temporal (~400 linhas, 0–2 s).

| coluna | significado |
|---|---|
| `time` | tempo, em s |
| `P_pu` | potência ativa injetada pela FV, em pu |
| `Q_pu` | potência reativa injetada (≈0 aqui) |
| `I_mag_pu` | **módulo da corrente** injetada pela FV, em pu |

Leitura (o ponto-chave): `I_mag_pu ≈ 0,59 pu` e a corrente fica **limitada a ~1,1 pu**
mesmo na falta. Uma máquina síncrona de mesmo porte daria ~5 pu. → **Inversores (IBR)
limitam a corrente de curto por controle**, reduzindo drasticamente a contribuição
de falta e a inércia do sistema.

### `06_pv_comparison.csv` — tensões com/sem FV no tempo

| coluna | significado |
|---|---|
| `time` | tempo, em s |
| `V7_sem_fv` / `V7_com_fv` | tensão na barra 7 sem/com FV, em pu |
| `V9_sem_fv` / `V9_com_fv` | tensão na barra 9 sem/com FV, em pu |
| `w_ref_sem_fv` / `w_ref_com_fv` | velocidade da máquina de referência (ω, pu) |

Leitura: a FV eleva ligeiramente as tensões pré-falta (mais geração local), mas
o efeito sobre a corrente de curto é pequeno (ver `06_summary`).

---

## Resumo de "o que olhar" para o artigo

| Pergunta | Arquivo |
|---|---|
| Os dados do sistema batem com o IEEE 14? | `01_*` (carga total 259 MW, 14 barras) |
| Como é a Ybus? | `02_ybus_elements.csv` + `data/headquarters/txt/ybus_*.txt` |
| Qual a corrente de curto na barra 7 (clássico)? | `03_summary.csv` → 27,62 kA (A) |
| De onde vem a corrente? | `03_fault_contributions.csv` |
| Quanto cada barra afunda? | `03_fault_voltages.csv` |
| E no domínio do tempo? | `04_*` |
| Como muda com carga/geração? | `05_scenarios_summary.csv` |
| Qual o efeito da fotovoltaica? | `06_*` |

> Comparação com o ANAFAS já consolidada em
> [data/headquarters/txt/](data/headquarters/txt/) (tabelas com erro %) e
> [COMPARACAO_ANAFAS.md](COMPARACAO_ANAFAS.md).
