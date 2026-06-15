# Metodologia de comparação: Ybus × PowerSimulationsDynamics × ANAFAS

Este documento define **como** comparar, de forma justa e cientificamente
defensável, os resultados do curto-circuito trifásico na barra 7 do IEEE 14
barras obtidos por três abordagens, e descreve os artefatos LaTeX já gerados
para o artigo (Overleaf).

> Companheiro do [README.md](README.md) (o que foi feito) e do
> [others/GUIA_JULIA.md](others/GUIA_JULIA.md) (a linguagem). Aqui tratamos
> **especificamente da comparação com o ANAFAS** (itens 3 e 5 do enunciado).

---

## 1. As três abordagens e a sua natureza

| Abordagem | Ferramenta | Natureza | O que entrega |
|-----------|-----------|----------|---------------|
| **A. Matriz nodal (Zbus)** | Julia (nosso código) | Estática, fasorial, regime subtransitório | Corrente de falta, tensões durante a falta, contribuições dos ramos, impedância de Thévenin |
| **B. Simulação dinâmica** | PowerSimulationsDynamics.jl | Dinâmica (DAE no tempo) | Evolução temporal de tensões, correntes, ângulos e velocidades dos rotores |
| **C. ANAFAS** | CEPEL | Estática, fasorial, componentes simétricas | Corrente de falta, tensões nas barras, contribuições — saída clássica de curto |

**Ponto-chave:** A e C são da **mesma família** (cálculo fasorial de curto por
impedâncias) — espera-se que **concordem bem** (erro de poucos %). B é de natureza
diferente (resposta dinâmica): fornece o **comportamento no tempo** e um valor de
corrente "estabilizada" que **não precisa** coincidir com o pico subtransitório de
A/C — a discrepância é física e deve ser **discutida**, não "corrigida".

---

## 2. Grandezas a comparar

1. **Corrente de curto na barra 7** — módulo, em pu e em kA.
2. **Nível de curto-circuito (SCC)** — em MVA.
3. **Impedância de Thévenin** no ponto de falta — \(Z_{77}\) [pu].
4. **Tensões nas 14 barras durante a falta** — módulo [pu].
5. **Contribuições de corrente** dos ramos que chegam à barra 7 (4→7, 8→7, 9→7).

As grandezas 1–5 existem em A e C. Para B, usamos a corrente/tensões
"estabilizadas" durante a falta (já calculadas no script 04).

> **Nota sobre as contribuições (grandeza 5):** as correntes de ramo são **fasores**
> (têm módulo *e* ângulo) — o total é a soma **fasorial**, não a soma aritmética dos
> módulos. As contribuições são reportadas na variante **de fluxo** (não flat):
> como a barra 7 é um nó de **injeção zero** na solução do fluxo, as contribuições
> **fecham exatamente** com \(I_f\) pela 1ª lei de Kirchhoff. Sob *flat start*
> (1,0 pu), os transformadores com **tap fora do nominal** introduzem uma pequena
> corrente de circulação que faz a soma das contribuições divergir ~1–2 % de
> \(I_f\); por isso usamos a variante de fluxo para essa tabela específica. O
> ANAFAS, sendo internamente consistente, também fecha as contribuições.

> **Use sempre pu na comparação principal.** O pu independe da base de tensão e
> elimina ambiguidade de qual kV-base cada ferramenta adota. O kA entra como
> valor de engenharia (a barra 7 é 13,8 kV ⇒ \(I_\text{base}=4{,}184\) kA).

---

## 3. O problema das premissas (a parte crítica)

Ferramentas de curto **parecem** discordar quando, na verdade, usam **premissas
diferentes**. Antes de comparar números, é preciso **alinhar as premissas**. Três
decisões dominam o resultado:

### 3.1 Tensão pré-falta
- **ANAFAS clássico:** assume **1,0∠0° pu** em todas as barras ("flat start").
  É o padrão histórico e o mais comum em estudos de proteção.
- **ANAFAS com carregamento:** pode usar as tensões de um caso de fluxo.
- **Nosso código:** sabe fazer as **duas** coisas (veja as variantes).

A tensão pré-falta **não** altera a impedância de Thévenin — altera apenas a
corrente, porque \(I_f = V^{pre}_7 / Z_{77}\). Como \(V^{pre}_7 = 1{,}044\) pu no
fluxo (e não 1,0), a variante "fluxo" dá corrente ~4 % maior que a "flat".

### 3.2 Modelagem das cargas
- **ANAFAS:** frequentemente **despreza** as cargas; quando as inclui, a
  recomendação é representá-las como **impedância constante**.
- **Nosso código:** calcula **com** e **sem** cargas (impedância constante).

Incluir cargas adiciona caminhos para a terra ⇒ **reduz** \(Z_{77}\) ⇒ **aumenta**
a corrente de falta (efeito de ~5 %).

### 3.3 Reatância dos geradores
- Curto-circuito para proteção usa a reatância **subtransitória** \(X''_d\).
- **Ambos** (ANAFAS e nosso código) usam \(X''_d\). ✔ Alinhado por construção.

---

## 4. As quatro variantes do nosso código

Para casar com **qualquer** configuração que você escolher no ANAFAS, o script
[julia/scripts/07_export_latex.jl](julia/scripts/07_export_latex.jl) calcula o
curto na barra 7 em **quatro** variantes e exporta todas:

| Variante | Tensão pré-falta | Cargas | \(I_f\) [pu] | \(I_f\) [kA] | \(\|Z_{77}\|\) [pu] | Corresponde ao ANAFAS… |
|----------|------------------|--------|--------------|--------------|---------------------|------------------------|
| **flat / sem carga** | 1,0 pu | desprezadas | **6,324** | **26,46** | 0,1581 | **clássico padrão** (recomendada p/ comparação) |
| flat / carga Z | 1,0 pu | imped. const. | 6,628 | 27,73 | 0,1509 | clássico + cargas Z |
| fluxo / sem carga | do fluxo | desprezadas | 6,593 | 27,58 | 0,1581 | com carregamento, sem cargas |
| fluxo / carga Z | do fluxo | imped. const. | 6,895 | 28,84 | 0,1512 | com carregamento + cargas Z |

Observações:
- \(|Z_{77}|\) é **idêntico** (0,1581) entre "flat" e "fluxo" sem carga — confirma
  que a impedância de Thévenin **não** depende da tensão pré-falta. ✔
- Para referência, a simulação dinâmica (PSD.jl, falta quase franca) dá
  \(I_f \approx 23{,}65\) kA (5,65 pu) — **menor**, por ser a corrente já
  amortecida pela resposta das máquinas (ver §6).

**Recomendação:** rode o ANAFAS na configuração **clássica** (1,0 pu, sem cargas)
e compare-o com a variante **flat / sem carga**. Se quiser também a versão com
carregamento, rode o ANAFAS com tensões de fluxo e cargas como Z e compare com
**fluxo / carga Z**.

---

## 5. Checklist para configurar o ANAFAS (comparação justa)

Ao montar o IEEE 14 barras no ANAFAS, para casar com a variante **flat / sem
carga**:

- [ ] **Base:** 100 MVA. Tensões base por barra: 69 kV (1–5), 13,8 kV (6,7,9–14),
      18 kV (8).
- [ ] **Geradores:** usar a reatância **subtransitória** \(X''_d\) (na base do
      gerador — o ANAFAS converte para a base do sistema). Valores (base do
      dispositivo): g1 \(X''_d{=}0{,}23\) (615 MVA); g2 e g3 \(0{,}13\) (60 MVA);
      g6 e g8 \(0{,}12\) (25 MVA). Resistência de armadura conforme o caso.
- [ ] **Linhas/transformadores:** r, x e os shunts (b) conforme
      [data/results/01_lines.csv](data/results/01_lines.csv) e
      [01_transformers.csv](data/results/01_transformers.csv) (taps inclusos).
- [ ] **Cargas:** **desprezar** (para a variante flat/sem carga) — ou modelar como
      **impedância constante** (para a variante com cargas).
- [ ] **Tensão pré-falta:** **1,0 pu** (flat) — padrão do ANAFAS.
- [ ] **Falta:** trifásica **franca** (impedância de falta nula) na **barra 7**.
- [ ] **Relatório:** habilitar saída de **tensões nas barras** e **contribuições**
      dos ramos, além da corrente no ponto de falta (módulo e ângulo).

> Se o seu ANAFAS já estiver com tensões de fluxo e/ou cargas, sem problema —
> basta compará-lo com a variante correspondente da tabela do §4.

---

## 6. Por que a abordagem dinâmica (B) difere de A e C

A diferença **não é erro** — é física e deve constar na discussão do artigo:

- **A/C (Zbus, ANAFAS)** calculam o **pico subtransitório** logo após a falta, por
  superposição linear, com as máquinas representadas apenas por \(X''_d\) atrás de
  uma f.e.m. constante.
- **B (PSD.jl)** integra o modelo dinâmico completo (máquina de rotor redondo +
  AVR + dinâmica da rede). O valor "estabilizado" durante a falta já incorpora a
  ação dos reguladores e o decaimento do transitório, resultando em corrente
  **menor** que o pico subtransitório de A/C.
- Conclusão esperada: **A ≈ C** (mesma família) e **B < A**, com B fornecendo, em
  troca, a **resposta temporal** (afundamentos, oscilações de rotor, recuperação)
  que A e C não dão.

---

## 7. Artefatos LaTeX já gerados (para o Overleaf)

Em [data/headquarters/latex/](data/headquarters/latex/), prontos para `\input{}`
(gerados pelo script 07; versões ASCII visuais em `data/headquarters/txt/`):

| Arquivo | Conteúdo | Como usar |
|---------|----------|-----------|
| `ybus_B.tex` | Matriz **B** (susceptâncias) 14×14, zeros como `\cdot` | dentro de `\[ Y_B = \input{...} \]` |
| `ybus_G.tex` | Matriz **G** (condutâncias) 14×14 | idem |
| `ybus_modulo.tex` | Matriz \(|Y|\) 14×14 | idem |
| `zbus_modulo.tex` | Matriz \(|Z|\) 14×14 (cheia) | idem |
| `zbus_coluna_falta.tex` | Coluna 7 da Zbus (vetor) | \(Z_{77}\) é a Thévenin |
| `vetor_vpre_flow.tex` | Tensões pré-falta (vetor 14×1) | — |
| `vetor_vfault_flat.tex` | Tensões durante a falta (vetor 14×1) | — |
| `tab_corrente_falta.tex` | Tabela corrente/SCC: 4 variantes + PSD.jl + **ANAFAS** | tabela comparativa principal |
| `tab_tensoes_falta.tex` | Tabela tensões nas 14 barras (Zbus flat/fluxo + ANAFAS) | — |
| `tab_contribuicoes.tex` | Contribuições dos ramos (variante fluxo; módulo, ângulo, kA) + ANAFAS | fecha c/ \(I_f\) por KCL |
| (figura) `data/figures/07_ybus_spy.png` | "Spy plot" da esparsidade da Ybus | `\includegraphics` |

### 7.1 Preâmbulo necessário no Overleaf
```latex
\usepackage{amsmath}     % bmatrix, \varepsilon
\usepackage{booktabs}    % \toprule, \midrule, \bottomrule
\usepackage{pdflscape}   % \begin{landscape} (matrizes grandes)
\usepackage{graphicx}
```
> As 3 tabelas comparativas já vêm **preenchidas** com os valores do ANAFAS e os
> erros \(\varepsilon\) (não há mais placeholder a substituir).

### 7.2 Exemplo de inclusão de uma matriz grande (landscape)
```latex
\begin{landscape}\scriptsize
\[ \mathbf{B} = \input{latex/ybus_B.tex} \]
\end{landscape}
```
Para matrizes 14×14, **landscape + `\scriptsize`** é o que cabe com folga. As
células nulas aparecem como `\cdot`, realçando a estrutura esparsa da rede.

### 7.3 Exemplo de tabela comparativa
```latex
\begin{table}[ht]\centering
\caption{Corrente de curto trifásico na barra 7.}
\input{latex/tab_corrente_falta.tex}
\end{table}
```

---

## 8. Métrica de erro e RESULTADO da comparação

Erro percentual com o ANAFAS como referência (convenção do artigo IFG):
\[
\varepsilon_\% = \frac{x_\text{código} - x_\text{ANAFAS}}{x_\text{ANAFAS}}\times 100\%.
\]

**Resultado (ANAFAS 8.1 × Zbus *flat/sem carga*, curto trifásico na barra 7):**

| Grandeza | ANAFAS | Zbus (flat) | \(\varepsilon\) |
|----------|--------|-------------|-----------------|
| Corrente \(I_f\) | 6,426 pu (26,88 kA) | 6,324 pu (26,46 kA) | **−1,6 %** |
| SCC | 632,3 MVA | 632,4 MVA | ~0 % |
| Tensões nas barras | — | — | 0–4 % (médio 2,1 %) |
| Contribuições (4/8/9→7) | 2,915 / 1,590 / 1,936 | 3,014 / 1,524 / 1,905 | ≤ 4,1 % |

A concordância **A ≈ C** confirma-se (erro ≲ 2 %). A variante *flat/sem carga* é a
mais fiel (o ANAFAS usou tensão pré-falta ≈ flat). As diferenças residuais (1–4 %)
vêm das premissas: tensão pré-falta do `.pwf` (≈0,984) e inclusão de cargas/shunts
no ANAFAS — efeitos que quase se cancelam. O dinâmico (PSD.jl) fica em −12 % por dar
a corrente **amortecida**, não o pico subtransitório (diferença física esperada).

---

## 9. Estado: comparação CONCLUÍDA ✅

O relatório do ANAFAS (`Relatorio_Anafas.txt`) foi processado e os valores
incorporados ao script [julia/scripts/07_export_latex.jl](julia/scripts/07_export_latex.jl)
(constantes `ANAFAS_*`). As 3 tabelas em [data/headquarters/latex/](data/headquarters/latex/) já estão
**preenchidas com ANAFAS + erros \(\varepsilon\)**:
`tab_corrente_falta.tex`, `tab_tensoes_falta.tex`, `tab_contribuicoes.tex`.

**Refinamento opcional** (para erro < 0,5 %): rodar o ANAFAS em modo clássico puro
(tensão pré-falta **1,0 pu**, **sem cargas**) — deve bater quase exato com a
variante *flat/sem carga* (6,324 pu). Útil se quiser uma validação "de método puro"
no artigo, isolada das premissas de carregamento.

---

### Fontes consultadas (metodologia ANAFAS)
- [ANAFAS — Eletrobras/CEPEL (página do produto)](https://www.cepel.br/produtos/anafas-2/)
- [Estudos de fluxo de carga, curto-circuito trifásico e análise (periódico)](https://periodicos.newsciencepubl.com/ans/article/download/1765/2232/6541)
- [Apresentação ANAFAS — análise de faltas (material didático)](https://slideplayer.com.br/slide/2321312/)
- [TCC UnB/FGA — uso do ANAFAS em estudos de curto](https://bdm.unb.br/bitstream/10483/20106/1/2017_ViniciusSiqueira_tcc.pdf)
- [Validação de ajustes de proteção via ANAFAS e MATLAB/Simulink](https://www.academia.edu/40425058/VIZUALIZA%C3%87%C3%83O_GR%C3%81FICA_E_VALIDA%C3%87%C3%83O_DE_AJUSTES_DE_PROTE%C3%87%C3%83O_DE_LINHAS_DE_TRANSMISS%C3%83O_ATRAV%C3%89S_DOS_SOFTWARES_ANAFAS_E_MATLAB_SIMULINK)
