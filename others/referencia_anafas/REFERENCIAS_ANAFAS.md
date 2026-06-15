# Referências para modelar o IEEE 14 barras no ANAFAS

Resultado da busca por casos/arquivos/manuais que modelam o IEEE 14 barras (ou
sistema análogo) no ANAFAS, para apoiar a nossa modelagem e a comparação com o
código Julia. Atualizado em 2026-06-08.

---

## 1. Resumo da busca (o que existe)

| Recurso | O que é | Utilidade p/ nós |
|---------|---------|------------------|
| **Artigo IFG (Borges & Magalhães)** | "Estudos de fluxo de carga, curto-circuito trifásico e análise dinâmica em SEP" — modela **IEEE 9 barras** em ANAREDE→ANAFAS→PSP-UFU e compara | ⭐ **Template metodológico quase idêntico** ao nosso (mesma tríade: fluxo, curto trifásico, dinâmica + comparação de softwares) |
| **Arquivo IEEE 14 ANAREDE (UTFPR)** | Caso `.pwf` do IEEE 14 em formato ANAREDE (salvo aqui: `IEEE14_anarede.pwf`, ASCII/CRLF — ver §3.1) | ⭐ **Dados batem com o nosso "14 Bus Base Case"** — ponto de partida para exportar ao ANAFAS |
| **IEEE 14 nos exemplos do ANAREDE** | O CEPEL distribui o IEEE 14 (e IEEE 30) junto com o ANAREDE | Alternativa: abrir o caso pronto no ANAREDE e exportar p/ ANAFAS |
| **Tutorial ANAFAS — UFBA (G-SEPi)** | Tutorial passo a passo (montagem do circuito + simulação de falta), Prof. Daniel Barbosa | Manual de uso do ANAFAS |
| **Tutorial/TCC ANAFAS — UnB (V. Siqueira, 2017)** | "Tutorial sobre o software de Análise de Faltas" | Manual de uso do ANAFAS |
| **TCC UFCG (A. C. Mariano, 2017)** | "Aplicação do Software ANAFAS para Cálculo de Curto-circuito" | Exemplos de uso |

**Conclusão honesta:** **não** encontrei um caso do **IEEE 14** já modelado e
disponibilizado **diretamente em ANAFAS** (`.ANA`). Porém, o caminho prático está
claro e bem suportado: **partir do IEEE 14 em formato ANAREDE (que já temos e que
bate com os nossos dados) e exportá-lo para o ANAFAS** — exatamente o que o artigo
do IFG faz com o IEEE 9.

> ⚠️ O artigo do IFG usa **IEEE 9**, não 14. Mas a metodologia (ANAREDE→ANAFAS,
> curto trifásico, comparação por erro %) é diretamente transponível. Vale citá-lo
> como referência metodológica no nosso artigo.

---

## 2. Workflow recomendado (ANAREDE → ANAFAS)

Validado pelo artigo do IFG e pela documentação do CEPEL:

1. **Carregar o IEEE 14 no ANAREDE** — use `IEEE14_anarede.pwf` (nesta pasta)
   ou o caso IEEE 14 que já vem nos exemplos do ANAREDE.
2. **Exportar para o ANAFAS** — a conversão gera os arquivos `.ANA` (dados) e
   `.lst` (lista); o programa de conversão (ANAANA) produz o caso já modelado para
   curto-circuito.
3. **Inserir os dados de curto dos geradores** (reatâncias — ver §4): o `.pwf` de
   fluxo **não** traz as reatâncias de sequência; elas são adicionadas no ANAFAS.
4. **Aplicar a falta trifásica franca na barra 7** e gerar os relatórios de
   **corrente de falta**, **tensões nas barras** e **contribuições dos ramos**.

> ⚠️ O `REL14BARRAS_CONT.TXT` que o ANAREDE gera é o **relatório de saída do
> fluxo** (RLIN/RBAR) — **não** serve para a conversão. A conversão é feita pelo
> utilitário **ANAANA** sobre o arquivo `.pwf` (ver §2.1).

### 2.1 Passo a passo da conversão com o ANAANA

Fonte: tutorial UnB (V. Siqueira, 2017), seção 4.4. O **ANAANA** é instalado no
**mesmo diretório do ANAFAS** (utilitário de conversão Anarede/Anatem → Anafas).

1. **Execute o ANAANA** (no diretório de instalação do ANAFAS). Abre uma janela
   de console.
2. **Arquivo Anarede:** ele pede o nome do arquivo no formato Anarede. Tecle `-`
   (hífen) e **Enter** para abrir o navegador de arquivos; selecione
   **`IEEE14_anarede.pwf`**.
3. **Arquivo Anatem:** ele pede o arquivo do ANATEM (que traria os dados dos
   geradores). **Não temos** → apenas pressione **Enter** para pular.
4. **Salvar:** abre a janela para salvar o arquivo convertido (extensão **`.ANA`**).
   Dê um nome, ex.: `ieee14.ANA`.
5. **Tipo de modelagem:** escolha **`Anafas`** (não "Peco"). O tipo *Anafas* inclui
   carregamento e **tensão pré-falta**; o *Peco* não.
6. **Motores de indução e shunts de linha:** responda conforme o estudo. Para o
   nosso curto trifásico, pode escolher **incluir os shunts de linha**; motores de
   indução **não** há.
7. **Precisão estendida:** pressione **Enter**.
8. Pronto — o `.ANA` está gerado e abre direto no **ANAFAS**.

**Dois ajustes manuais obrigatórios após a conversão** (limitações conhecidas do
ANAANA):

- **Reatâncias dos geradores (ESSENCIAL para nós):** como não passamos o arquivo
  ANATEM, os geradores vêm **sem** as reatâncias corretas. Insira manualmente, nos
  5 geradores (barras 1, 2, 3, 6, 8), os \(X''_d\) da tabela da §4. Para curto
  **trifásico** basta a **sequência positiva** \(X_1 = X''_d\).
- **Sequência zero:** o ANAANA copia a sequência zero igual à positiva (valor
  errado). **Irrelevante para nós** — o curto **trifásico** usa só a sequência
  positiva. (Só corrija se for fazer falta monofásica/à terra.)

> Sobre a tensão pré-falta: o tipo *Anafas* leva as tensões do `.pwf`. Para casar
> com a nossa variante **flat** (referência ANAFAS clássico), configure no ANAFAS a
> tensão pré-falta **1,0 pu** (ou rode sem carregamento). Para a variante **fluxo**,
> salve o `.pwf` no ANAREDE **após convergir** o fluxo (com as tensões resolvidas).

### 2.2 Preenchimento dos geradores no `.ANA` (feito em 2026-06-08)

O ANAANA gera os 5 circuitos-gerador (barras 1, 2, 3, 6, 8) com **X1 = 999998**
(infinito). No `ieee14.ANA` (bloco `DCIR`, circuitos tipo `G`), o campo **X1** ocupa
as **colunas 24-29** (% na base 100 MVA). Já preenchidos com os \(X''_d\) do nosso
modelo (backup em `ieee14_convertido_original.ANA`):

| Barra | X1 (cols 24-29) |
|-------|-----------------|
| 1 | ` 3.740` |
| 2 | `21.667` |
| 3 | `21.667` |
| 6 | `48.000` |
| 8 | `48.000` |

R1 fica em branco (R≈0). O X0 (cols 36-41) segue `999998` — **irrelevante p/ falta
trifásica** (só usaria seq. zero em falta monofásica/à terra). Pela interface, o
mesmo se faz em **Dados → Circuitos** (tipo Gerador) ou clicando na barra.

### 2.3 Aplicar a falta trifásica na barra 7 (estudo individual)

Fonte: tutorial UnB, seção 4.5.2.

1. Menu **Análise → Estudo individual**.
2. Selecione **defeito shunt em barra** e marque **orientação a ponto de falta**.
3. Na janela seguinte, informe **barra 7** e **tipo de defeito: trifásico**; clique
   **Adicionar** (fecha) e depois **Executar**.
4. Abre o **relatório detalhado** (corrente de falta, tensões nas barras,
   contribuições) + a interface gráfica.

**Sanity check:** a corrente deve dar **≈ 26 kA** (≈ 6,3 pu). Se vier *infinita* ou
*zero*, os geradores não foram lidos — reabra o `.ANA` já com os X1 preenchidos.

---

## 3. Confirmação: o arquivo ANAREDE bate com o nosso sistema ✔

Comparei `IEEE14_anarede_utfpr.pwf` com os dados do nosso "14 Bus Base Case"
(`data/results/01_lines.csv`, `01_transformers.csv`, `01_loads.csv`):

- **Linhas** (R%, X%, Bc): idênticas. Ex.: 1–2 → R=1,938 %, X=5,917 %, Bc=5,28;
  4–5 → R=1,335 %, X=4,211 %; 6–11 → R=9,498 %, X=19,89 %. ✔
- **Transformadores com tap**: idênticos. 4–7 → X=20,912 %, tap=0,978;
  4–9 → X=55,618 %, tap=0,969; 5–6 → X=25,202 %, tap=0,932; 7–8 → X=17,615 %. ✔
- **Cargas**: idênticas. Barra 2 → 21,7+12,7j; barra 3 → 94,2+19j;
  barra 9 → 29,5+16,6j MVA. ✔

Ou seja, é **o mesmo IEEE 14 clássico**. A topologia e as impedâncias da rede
estão garantidas — a comparação será justa na parte de rede.

> Observação: o `.pwf` traz tensões de geração ≈1,0 pu (perfil quase *flat*); isso
> é irrelevante para o ANAFAS clássico, que assume tensão pré-falta 1,0 pu de
> qualquer modo (ver [../../COMPARACAO_ANAFAS.md](../../COMPARACAO_ANAFAS.md)).

### 3.1 Verificação técnica do arquivo (feita em 2026-06-08)

O arquivo `IEEE14_anarede.pwf` foi inspecionado para carregar no ANAREDE sem ajustes:

| Item | Resultado |
|------|-----------|
| Estrutura (TITU, DCTE, DBAR, DLIN, DGLT, EXLF, FIM + terminadores `99999`) | ✅ completa |
| Formato posicional dos cartões (colunas fixas) DBAR e DLIN | ✅ campos alinhados ao cabeçalho |
| Contagem | ✅ 14 barras, 20 circuitos (16 linhas + 4 trafos; 3 com tap: 4-7, 4-9, 5-6) |
| Carga ativa total | ✅ **259,0 MW** = igual ao nosso "14 Bus Base Case" |
| Quebras de linha | ✅ CRLF (Windows) |
| Codificação | ✅ convertida para **ASCII puro** (acentos do título/comentários removidos) |

> ⚠️ **Encoding:** a versão original baixada estava em UTF-8 com acentos; o ANAREDE
> é um programa legado que espera Latin1/ASCII. Por isso o arquivo aqui já está em
> **ASCII** (ex.: o título virou "analise de contingencias"). Use **este** arquivo.

**Duas ressalvas (não impedem o uso, mas registre):**
1. **Despacho de geração ativa difere do nosso caso** (`.pwf`: Pg₁≈234, Pg₂≈40,
   Pg₃=Pg₆=Pg₈=0 MW; nosso: 193/30/20/15/10 MW). Isso muda só o **fluxo de
   potência** (tensões pré-falta) — **não** afeta o curto *flat* do ANAFAS, que
   ignora a geração ativa e usa apenas as reatâncias. Para a comparação com a
   variante *flat / sem carga* (a recomendada), é irrelevante.
2. **Faltam os dados de curto** (reatâncias de sequência dos geradores) — esperado
   num arquivo de fluxo; são inseridos no ANAFAS conforme a §4.

---

## 4. Dados de curto a inserir no ANAFAS (reatâncias dos geradores)

Estes valores **não** estão no `.pwf` e são essenciais para o curto. Use os
**mesmos** do nosso código (senão a comparação não fecha). Reatância
**subtransitória** \(X''_d\); resistência de armadura ≈ 0 (como no artigo do IFG).
Para curto **trifásico** basta a sequência **positiva** \(X_1 = X''_d\).

| Gerador | Barra | \(X''_d\) (base do gerador) | Base [MVA] | \(X''_d\) convertido p/ 100 MVA |
|---------|-------|------------------------------|------------|--------------------------------|
| g1 | 1 | 0,23 | 615 | **0,0374** |
| g2 | 2 | 0,13 | 60 | **0,2167** |
| g3 | 3 | 0,13 | 60 | **0,2167** |
| g6 | 6 | 0,12 | 25 | **0,4800** |
| g8 | 8 | 0,12 | 25 | **0,4800** |

No ANAFAS você pode informar \(X''_d\) na **base do próprio gerador** (com a
potência-base) — o programa converte para a base do sistema (100 MVA). O resultado
deve reproduzir a impedância de Thévenin na barra 7 que calculamos:
\(|Z_{77}| = 0{,}158\) pu, e a corrente de falta da variante *flat / sem carga*
≈ **6,32 pu = 26,46 kA** (ver COMPARACAO_ANAFAS.md).

---

## 5. O que esperar do relatório do ANAFAS (formato de saída)

Extraído do artigo do IFG (mesmo formato que você verá):

- **Corrente de falta na barra**: por fase (A, B, C), com **módulo (pu)** e
  **ângulo**. No trifásico simétrico, os três módulos são iguais e os ângulos
  defasados de 120°. (No artigo: barra de falta → 9,018 pu nas três fases.)
- **Tensões pós-falta**: por fase, módulo e ângulo. A **barra de falta → 0**; as
  vizinhas afundam. ⚠️ O ANAFAS **não lista** as barras ligadas diretamente à
  barra de referência (slack) no relatório de tensões.
- **Contribuições dos ramos**: o ANAFAS **não mostra todas no diagrama** — é
  preciso **gerar o relatório de contribuições** explicitamente.
- **Corrente em ampères** no diagrama (símbolo de raio vermelho na barra de falta)
  e ângulo de sequência positiva.

> 💡 **Dica de comparação (do artigo):** compare os **módulos** de corrente/tensão
> — eles convergem bem entre ferramentas (erro < 1 %). Os **ângulos absolutos**
> divergem muito, porque o ANAFAS adota referência 0° (flat) e o nosso código/​PSD
> usa os ângulos do fluxo. Isso é esperado e deve ser **explicado**, não corrigido.

---

## 6. Como citar no artigo

- O artigo do **IFG** é a melhor referência metodológica (ANAREDE/ANAFAS + curto
  trifásico + comparação por erro %). Embora use IEEE 9, sustenta nossa abordagem.
- A confirmação de que **ANAFAS não considera fluxo de carga** (usa regime de falta
  com pré-falta 1,0 pu) aparece tanto no artigo do IFG quanto na documentação do
  CEPEL — base para a escolha da variante *flat* como referência de comparação.

---

### Fontes
- Artigo IFG — Borges & Magalhães, *Estudos de fluxo de carga, curto-circuito trifásico e análise dinâmica em SEP* (I Congresso Internacional Multidisciplinar). PDF: <https://periodicos.newsciencepubl.com/ans/article/download/1765/2232/6541>
- Arquivo IEEE 14 ANAREDE — UTFPR (Prof. Raphael Benedito): <http://paginapessoal.utfpr.edu.br/raphaelbenedito/>
- Tutorial ANAFAS — UFBA/G-SEPi: <https://www.gsepi.eng.ufba.br/lancamento-do-tutorial-de-anafas/>
- Tutorial/TCC ANAFAS — UnB (V. Siqueira, 2017): <https://bdm.unb.br/handle/10483/20106>
- TCC UFCG (A. C. Mariano, 2017): <https://dspace.sti.ufcg.edu.br/handle/riufcg/18730>
- ANAFAS — Eletrobras/CEPEL: <https://www.cepel.br/produtos/anafas-2/>
