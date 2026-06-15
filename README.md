# Modelos da Copa do Mundo

Este repositorio organiza um pipeline analitico para coletar dados, construir bases de modelagem e estimar probabilidades de resultado e placar para jogos da Copa do Mundo masculina da FIFA.

O escopo atual usa a Copa de 2022 como base historica completa e a Copa de 2026 como calendario, previsao e avaliacao parcial conforme os resultados ficam disponiveis.

## Pergunta Analitica

Como combinar calendario e resultados oficiais, odds de mercado, ratings externos e historico recente de selecoes para gerar probabilidades 1x2 e distribuicoes de placar para jogos da Copa do Mundo?

A resposta do projeto nao e um unico modelo. O repositorio compara uma linha de base de mercado, modelos de placar derivados das odds e modelos hibridos que usam odds, ratings e forma recente.

## Arquitetura do Projeto

```text
fontes externas
  -> data/raw/
  -> data/interim/
  -> data/processed/
  -> R/02_modelagem/
  -> reports/
```

As camadas seguem a seguinte logica:

- `data/raw/`: arquivos brutos, baixados ou registrados com minima intervencao.
- `data/interim/`: dados parseados, normalizados e consolidados.
- `data/processed/`: base final de modelagem, previsoes e metricas.
- `R/01_coleta/`: scripts de coleta, parsing, consolidacao e auditoria.
- `R/02_modelagem/`: scripts de preparacao da base e estimacao dos modelos.
- `reports/`: auditorias, resultados e decisoes analiticas.

## Data Pipeline

### 1. Coleta bruta

O pipeline coleta dados de fontes abertas e auditaveis:

| Fonte | Uso no projeto | Saida principal |
|---|---|---|
| OpenFootball | jogos, grupos, fases, datas e placares de Copa | `data/raw/matches/` |
| international_results | historico amplo de jogos internacionais | `data/raw/matches/international_results.csv` |
| FIFA Ranking | ranking oficial e pontos atuais das selecoes | `data/raw/rankings/fifa_rankings_current.json` |
| World Football Elo | rating externo de forca das selecoes | `data/raw/elo/` |
| football-data.co.uk | odds historicas da Copa 2022 | `data/raw/odds/football_data_worldcup.xlsx` |
| OddsChecker | odds 1x2 da fase de grupos de 2026 quando disponiveis | `data/raw/odds/oddschecker/` |

A decisao metodologica central e trabalhar com fontes abertas e reproduziveis, sem dependencia obrigatoria de API paga. Quando uma fonte bloqueia ou nao entrega dados, o pipeline registra o status em metadados em vez de inventar valores.

### 2. Padronizacao intermediaria

Depois da coleta, os scripts transformam os arquivos brutos em tabelas analiticas:

- jogos da Copa em `data/interim/matches/worldcup_matches_2022_onwards.csv`;
- historico internacional filtrado desde 2018 em `data/interim/matches/international_results_since_2018.csv`;
- odds consolidadas em `data/interim/odds/worldcup_odds_2022_onwards.csv`;
- rankings e ratings em `data/interim/rankings/` e `data/interim/elo/`;
- rating externo consolidado por selecao em `data/interim/teams/team_overall_external_consolidated.csv`.

Nessa etapa, nomes de selecoes sao normalizados, odds sao agregadas por jogo, rankings e Elo sao colocados em formatos comparaveis e os dados ficam prontos para a construcao da base final.

### 3. Auditoria

A coleta gera arquivos de controle em `data/raw/metadata/` e relatorios em `reports/`.

Os principais controles sao:

- inventario de fontes;
- log de acesso aos dados;
- manifesto dos arquivos brutos;
- status de cobertura do OpenFootball;
- status da coleta de odds;
- lista de jogos sem odds ligadas;
- resumo de auditoria por ano.

No corte atual da auditoria, a base tem 64 jogos de 2022 com placar final e 104 jogos de 2026 no calendario, com 12 resultados finalizados registrados.

### 4. Base final de modelagem

A base `data/processed/match_modeling_base.csv` e o ponto de encontro entre o data pipeline e o model pipeline.

Ela contem uma linha por jogo e agrega:

- identificadores do jogo;
- ano, fase e status;
- selecoes;
- placar observado quando disponivel;
- odds 1x2 agregadas;
- probabilidades implicitas sem margem;
- ratings externos das duas selecoes;
- diferenciais de rating;
- Elo historico pre-jogo quando disponivel;
- features simples de forma recente.

## Model Pipeline

### 1. Baseline de mercado 1x2

O primeiro benchmark converte odds em probabilidades implicitas de vitoria do time A, empate e vitoria do time B.

Esse modelo e importante porque o mercado costuma ser uma referencia forte para probabilidades 1x2. A limitacao e que ele nao produz uma distribuicao de placares e tende a raramente escolher empate como classe modal, mesmo quando a probabilidade de empate e relevante.

Artefato:

- `data/processed/model_baseline_market_1x2.csv`

### 2. Poisson implicito pelas odds

O modelo Poisson implicito estima `lambda_a` e `lambda_b` de forma que a matriz de placares reproduza, o melhor possivel, as probabilidades 1x2 vindas do mercado.

Esse modelo transforma odds de resultado em uma distribuicao completa de placares. Como as odds disponiveis sao apenas 1x2, o total esperado de gols precisa de um prior.

Artefato:

- `data/processed/model_poisson_odds_implicit_predictions.csv`

### 3. Modelo hibrido V1

O hibrido V1 combina:

- odds 1x2 quando existem;
- ratings externos das selecoes;
- Elo historico pre-jogo;
- forma recente ofensiva e defensiva;
- estrutura Poisson para gerar placares.

Ele e o modelo principal da V1 porque cobre mais jogos de 2026 do que os modelos dependentes exclusivamente de odds e preserva o sinal do mercado quando as odds estao disponiveis.

Artefatos:

- `data/processed/model_poisson_hybrid_predictions.csv`
- `data/processed/rating_model_info.csv`
- `data/processed/model_evaluation_summary.csv`

### 4. Modelo hibrido V2

A V2 adiciona ajustes voltados a placares:

- total esperado de gols sensivel a mismatch;
- peso dinamico do mercado;
- correcao Dixon-Coles para placares baixos;
- cauda Negative Binomial para favoritos em jogos muito desbalanceados.

A V2 melhora a distribuicao de placares em alguns cortes, especialmente em `score_log_loss`, mas ainda e tratada como experimental para probabilidades 1x2 porque pode deslocar a calibracao agregada de resultado.

Artefatos:

- `data/processed/model_poisson_hybrid_v2_predictions.csv`
- `data/processed/model_evaluation_summary_v2.csv`
- `data/processed/model_evaluation_summary_all.csv`
- `data/processed/rating_model_v2_info.csv`

## Avaliacao

As metricas se dividem em dois grupos.

Metricas de resultado:

- acuracia 1x2;
- log loss de resultado;
- Brier score multiclasse.

Metricas de placar:

- log loss do placar observado;
- MAE de gols do time A;
- MAE de gols do time B;
- MAE do total de gols.

Resumo comparativo atual em `data/processed/model_evaluation_summary_all.csv`:

| modelo | ano | jogos avaliados | acuracia resultado | log loss resultado | Brier resultado | log loss placar |
|---|---:|---:|---:|---:|---:|---:|
| baseline mercado 1x2 | 2022 | 64 | 0,531 | 0,998 | 0,584 | NA |
| Poisson hibrido V1 | 2022 | 64 | 0,531 | 0,997 | 0,582 | 2,943 |
| Poisson hibrido V2 NB | 2022 | 64 | 0,531 | 0,997 | 0,583 | 2,926 |
| baseline mercado 1x2 | 2026 | 8 | 0,375 | 1,212 | 0,739 | NA |
| Poisson hibrido V1 | 2026 | 12 | 0,500 | 1,035 | 0,640 | 3,168 |
| Poisson hibrido V2 NB | 2026 | 12 | 0,500 | 1,042 | 0,643 | 3,103 |

A avaliacao de 2026 ainda deve ser lida como monitoramento parcial, nao como conclusao definitiva de performance.

## Principais Achados

- O mercado 1x2 e um benchmark forte para probabilidades de resultado.
- Odds 1x2 nao resolvem diretamente o problema de placar; e necessario impor estrutura probabilistica.
- Ratings FIFA/Elo aumentam cobertura e ajudam jogos sem odds ou com odds incompletas.
- O hibrido V1 e mais estavel para probabilidades 1x2.
- A V2 com Negative Binomial melhora a modelagem de placares, mas ainda precisa de calibracao para preservar melhor as probabilidades agregadas.
- Empates sao um ponto metodologico importante: podem ter probabilidade relevante, mas raramente aparecem como resultado modal nos modelos baseados em mercado.

## Limitacoes Metodologicas

- A base historica de Copas com odds e placares e pequena.
- As odds disponiveis no pipeline atual sao apenas do mercado 1x2.
- Ratings atuais sao adequados para previsao de 2026, mas nao devem ser usados como se fossem historicos em backtests de 2022.
- O scraping de odds depende da disponibilidade das paginas e pode sofrer bloqueios.
- A fase de mata-mata de 2026 ainda contem placeholders antes da definicao dos classificados.
- A avaliacao de 2026 tem poucos jogos finalizados no corte atual.

## Reprodutibilidade

O pipeline principal pode ser executado com:

```bash
Rscript R/01_coleta/99_executar_coleta_v1.R
Rscript R/02_modelagem/99_executar_modelagem_v2.R
```

Dependencias R usadas ao longo dos scripts incluem:

```text
chromote, digest, dplyr, fs, here, httr2, janitor, jsonlite,
lubridate, purrr, readr, readxl, rvest, stringi, stringr,
tibble, tidyr, xml2
```

O uso de `chromote` e opcional e aparece principalmente no fluxo assistido de coleta do OddsChecker.

## Percorrendo o Codigo

### Coleta: `R/01_coleta/`

Esta pasta contem o pipeline que baixa, parseia, padroniza e audita os dados.

| Script | Papel |
|---|---|
| `lib_coleta.R` | Funcoes compartilhadas de caminhos, diretorios, download e log de acesso. |
| `00_criar_estrutura_e_fontes.R` | Cria a estrutura de pastas e registra o inventario inicial de fontes. |
| `01_baixar_openfootball_2022.R` | Baixa os arquivos brutos da Copa de 2022 via OpenFootball. |
| `02_baixar_openfootball_2026.R` | Baixa calendario/resultados da Copa de 2026 via OpenFootball. |
| `03_parsear_openfootball.R` | Transforma arquivos Football.TXT em tabelas retangulares. |
| `04_baixar_international_results.R` | Coleta e filtra o historico internacional recente. |
| `05_baixar_fifa_ranking.R` | Coleta o ranking FIFA masculino atual. |
| `06_baixar_elo_ratings.R` | Coleta dados do World Football Elo. |
| `07_baixar_odds.R` | Coleta odds em fonte tabular, especialmente football-data.co.uk. |
| `07b_baixar_odds_oddschecker.R` | Coleta odds 2026 do OddsChecker, com auditoria de bloqueios e falhas. |
| `08_auditar_coleta.R` | Valida cobertura, duplicatas, odds ausentes e qualidade geral da coleta. |
| `09_criar_manifesto_raw.R` | Gera manifesto dos arquivos brutos, incluindo metadados e hashes. |
| `10_consolidar_overall_terceiros.R` | Consolida FIFA e Elo em um rating externo comparavel entre selecoes. |
| `99_executar_coleta_v1.R` | Orquestra a execucao completa da coleta V1. |

### Modelagem: `R/02_modelagem/`

Esta pasta transforma os dados consolidados em previsoes, metricas e relatorios.

| Script | Papel |
|---|---|
| `lib_modelagem.R` | Funcoes compartilhadas de normalizacao de times, probabilidades, Poisson, Dixon-Coles, distribuicoes de placar e metricas. |
| `01_preparar_base_modelagem.R` | Une jogos, odds, ratings, Elo e forma recente em `match_modeling_base.csv`. |
| `02_estimar_modelos_placares.R` | Estima o baseline de mercado, o Poisson implicito por odds e o hibrido V1. |
| `03_estimar_modelos_placares_v2.R` | Estima a V2 com peso dinamico de mercado, Dixon-Coles e cauda Negative Binomial. |
| `99_executar_modelagem_v1.R` | Executa a preparacao da base e os modelos V1. |
| `99_executar_modelagem_v2.R` | Executa a preparacao da base, os modelos V1 e a V2 experimental. |

### Dados Gerados

Principais arquivos intermediarios:

- `data/interim/matches/worldcup_matches_2022_onwards.csv`;
- `data/interim/odds/worldcup_odds_2022_onwards.csv`;
- `data/interim/teams/team_external_ratings_long.csv`;
- `data/interim/teams/team_overall_external_consolidated.csv`;
- `data/interim/elo/world_football_elo_2022_onwards.csv`.

Principais arquivos processados:

- `data/processed/match_modeling_base.csv`;
- `data/processed/model_baseline_market_1x2.csv`;
- `data/processed/model_poisson_odds_implicit_predictions.csv`;
- `data/processed/model_poisson_hybrid_predictions.csv`;
- `data/processed/model_poisson_hybrid_v2_predictions.csv`;
- `data/processed/model_evaluation_summary_all.csv`.

### Relatorios

Os relatorios explicam o estado do pipeline e as decisoes tecnicas:

| Relatorio | Conteudo |
|---|---|
| `reports/auditoria_coleta.md` | Cobertura, pendencias e qualidade da coleta. |
| `reports/analise_modelagem_placares.md` | Diagnostico dos dados disponiveis e desenho dos modelos. |
| `reports/resultados_modelagem_v1.md` | Resultados, cobertura e decisao tecnica da V1. |
| `reports/resultados_modelagem_v2.md` | Comparacao da V2 com a V1 e leitura dos ganhos/perdas. |
| `reports/fontes_odds_abertas_2026.md` | Analise das alternativas abertas para odds da Copa 2026. |

## Roadmap Analitico

- Calibrar o tamanho da Negative Binomial por validacao historica.
- Ativar cauda de placar tambem por sinal de odds, nao apenas por mismatch de rating.
- Integrar mercados de over/under quando houver fonte aberta confiavel.
- Preservar probabilidades 1x2 alvo ao ajustar a distribuicao de placares.
- Criar simulacao completa do torneio a partir das probabilidades por jogo.
- Automatizar monitoramento incremental da Copa 2026 conforme novos resultados entram.

