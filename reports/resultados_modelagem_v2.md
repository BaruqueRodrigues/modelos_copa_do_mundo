# Resultados da Modelagem V2

Gerado em: 2026-06-15

## Objetivo

A V2 substitui a cauda heuristica da primeira versao experimental por uma cauda Negative Binomial. A ideia e preservar a media esperada de gols estimada pelo modelo, mas permitir maior variancia nos gols do favorito quando ha grande mismatch entre selecoes.

## Scripts

- `R/02_modelagem/03_estimar_modelos_placares_v2.R`
- `R/02_modelagem/99_executar_modelagem_v2.R`

## Artefatos

- `data/processed/model_poisson_hybrid_v2_predictions.csv`
- `data/processed/model_evaluation_summary_v2.csv`
- `data/processed/model_evaluation_summary_all.csv`
- `data/processed/rating_model_v2_info.csv`

## Componentes da V2

### 1. Modelo de total de gols sensivel a mismatch

A V2 usa uma versao ampliada do modelo de total de gols:

- `abs_elo_diff_scaled`;
- excesso de mismatch acima de 300 pontos Elo;
- indicador de campo neutro;
- ajuste por forma recente ofensiva/defensiva.

### 2. Peso dinamico do mercado

O peso das odds varia por jogo:

- aumenta quando ha mais casas e overround menor;
- diminui levemente em mismatches muito fortes;
- zera quando nao ha odds.

### 3. Dixon-Coles para placares baixos

A V2 aplica correcao Dixon-Coles em:

- `0-0`;
- `1-0`;
- `0-1`;
- `1-1`.

A correcao e mais forte em jogos equilibrados.

### 4. Negative Binomial para cauda

Quando ha favorito claro e grande diferenca de forca, a distribuicao de gols do favorito passa de Poisson para Negative Binomial.

Parametros atuais:

- `tail_strength = 0,30` usa `negative_binomial_size = 5,0`;
- `tail_strength = 0,55` usa `negative_binomial_size = 3,2`;
- `tail_strength = 0,85` usaria `negative_binomial_size = 2,2`.

Quanto menor o `size`, maior a variancia para a mesma media. No corte atual, a cauda NB foi ativada em 5 jogos de 2022 e 14 jogos de 2026.

## Cobertura

A V2 cobre os mesmos jogos do hibrido V1:

- 64 jogos de 2022;
- 72 jogos da fase de grupos de 2026;
- 12 jogos finalizados de 2026 avaliaveis no corte atual.

## Avaliacao comparada

Resumo em `data/processed/model_evaluation_summary_all.csv`:

| modelo | ano | jogos avaliados | acuracia resultado | log loss resultado | Brier resultado | log loss placar | MAE gols A | MAE gols B | MAE total gols |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline mercado 1x2 | 2022 | 64 | 0,531 | 0,998 | 0,584 | NA | NA | NA | NA |
| Poisson hibrido V1 | 2022 | 64 | 0,531 | 0,997 | 0,582 | 2,943 | 1,047 | 0,837 | 1,453 |
| Poisson hibrido V2 NB | 2022 | 64 | 0,531 | 0,997 | 0,583 | 2,926 | 1,044 | 0,844 | 1,468 |
| Poisson odds | 2022 | 64 | 0,531 | 1,005 | 0,585 | 2,959 | 1,055 | 0,838 | 1,424 |
| baseline mercado 1x2 | 2026 | 8 | 0,375 | 1,212 | 0,739 | NA | NA | NA | NA |
| Poisson hibrido V1 | 2026 | 12 | 0,500 | 1,035 | 0,640 | 3,168 | 1,308 | 0,696 | 1,595 |
| Poisson hibrido V2 NB | 2026 | 12 | 0,500 | 1,042 | 0,643 | 3,103 | 1,271 | 0,685 | 1,538 |
| Poisson odds | 2026 | 8 | 0,375 | 1,194 | 0,738 | 3,656 | 1,504 | 0,944 | 1,820 |

## Leitura dos resultados

A troca para Negative Binomial melhora o objetivo de placar:

- em 2022, `score_log_loss` melhora de 2,943 para 2,926;
- em 2026, `score_log_loss` melhora de 3,168 para 3,103;
- em 2026, MAE do time A melhora de 1,308 para 1,271;
- em 2026, MAE do time B melhora de 0,696 para 0,685;
- em 2026, MAE de total de gols melhora de 1,595 para 1,538.

O custo aparece nas probabilidades 1x2 de 2026:

- acuracia fica igual a V1: 0,500;
- log loss de resultado piora de 1,035 para 1,042;
- Brier piora de 0,640 para 0,643.

Isso confirma que a NB ajuda a distribuicao de placares, mas ainda precisa de calibracao para nao deslocar demais as probabilidades agregadas de resultado.

## Jogos finalizados de 2026

| jogo | placar real | placar V1 | placar V2 NB | observacao |
|---|---:|---:|---:|---|
| Mexico x South Africa | 2-0 | 1-0 | 2-0 | V2 acertou o placar modal. |
| South Korea x Czech Republic | 2-1 | 1-0 | 1-1 | Dixon-Coles aproximou de empate baixo, mas errou o vencedor. |
| Canada x Bosnia & Herzegovina | 1-1 | 1-0 | 1-0 | Resultado segue superestimando Canada. |
| USA x Paraguay | 4-1 | 1-0 | 1-1 | V2 aumentou gols esperados, mas a cauda NB nao foi ativada. |
| Qatar x Switzerland | 1-1 | 0-2 | 0-2 | Mercado/ratings superestimaram Switzerland. |
| Brazil x Morocco | 1-1 | 1-0 | 1-0 | Modelo manteve favoritismo do Brazil. |
| Haiti x Scotland | 0-1 | 0-1 | 0-1 | V1 e V2 acertaram placar modal. |
| Australia x Turkey | 2-0 | 0-1 | 1-1 | V2 aproximou jogo equilibrado, mas ainda errou. |
| Germany x Curacao | 7-1 | 3-0 | 2-0 | NB aumentou probabilidade do placar observado, mas o modo ficou menos extremo. |
| Ivory Coast x Ecuador | 1-0 | 0-1 | 1-1 | V2 aproximou empate/baixo placar, mas errou vencedor. |
| Netherlands x Japan | 2-2 | 1-0 | 1-1 | Dixon-Coles aproximou do empate. |
| Sweden x Tunisia | 5-1 | 1-0 | 1-1 | Ainda falta gatilho de cauda para favoritos moderados. |

## Decisao tecnica

Manter a V2 NB como modelo experimental de placar:

- V1 continua sendo o modelo principal mais estavel para 1x2;
- V2 NB e melhor candidata para score probabilities e simulacao de placares;
- a promocao da V2 para modelo principal deve depender de mais jogos finalizados de 2026.

## Proximas melhorias

Prioridades para V2.1:

1. calibrar o `negative_binomial_size` por validacao historica;
2. ativar NB tambem por sinal de odds, nao apenas por Elo/mismatch;
3. criar um gatilho explicito de probabilidade de goleada;
4. preservar exatamente as probabilidades 1x2-alvo ao ajustar a distribuicao de placares;
5. integrar odds de over/under quando disponiveis.
