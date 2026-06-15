# Resultados da Modelagem V1

Gerado em: 2026-06-15

## Scripts

- `R/02_modelagem/01_preparar_base_modelagem.R`
- `R/02_modelagem/02_estimar_modelos_placares.R`
- `R/02_modelagem/99_executar_modelagem_v1.R`

## Artefatos gerados

- `data/processed/match_modeling_base.csv`
- `data/processed/model_baseline_market_1x2.csv`
- `data/processed/model_poisson_odds_implicit_predictions.csv`
- `data/processed/model_poisson_hybrid_predictions.csv`
- `data/processed/model_evaluation_summary.csv`
- `data/processed/rating_model_info.csv`

## Cobertura atual

Base de modelagem:

- 168 jogos.
- 64 jogos de 2022 com placar final.
- 104 jogos de 2026, sendo 12 finalizados e 92 agendados.
- 72 jogos de grupos em 2026, sendo 12 finalizados e 60 agendados.
- 132 jogos com odds agregadas.
- 136 jogos com rating externo para os dois times.

Cobertura por modelo:

- Baseline mercado 1x2: 64 jogos de 2022 e 68 jogos de 2026.
- Poisson implicito por odds: 64 jogos de 2022 e 68 jogos de 2026.
- Poisson hibrido odds + ratings: 64 jogos de 2022 e 72 jogos de grupos de 2026.

Em 2026, o baseline de mercado e o Poisson implicito por odds avaliam 8 jogos finalizados, pois dependem de odds. O modelo hibrido avalia os 12 jogos finalizados da fase de grupos, usando ratings quando as odds estao ausentes.

## Modelo de ratings

O componente de ratings foi calibrado com jogos internacionais que tambem tinham Elo pre-jogo disponivel:

- linhas de treino: 4.572;
- taxa historica de empate usada como fallback: 22,9%;
- media historica de gols usada como fallback: 2,72.

## Avaliacao atual

Resumo em `data/processed/model_evaluation_summary.csv`:

| modelo | ano | jogos avaliados | acuracia resultado | log loss resultado | Brier resultado | log loss placar | MAE gols A | MAE gols B | MAE total gols |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline mercado 1x2 | 2022 | 64 | 0,531 | 0,998 | 0,584 | NA | NA | NA | NA |
| baseline mercado 1x2 | 2026 | 8 | 0,375 | 1,212 | 0,739 | NA | NA | NA | NA |
| Poisson implicito por odds | 2022 | 64 | 0,531 | 1,005 | 0,585 | 2,959 | 1,055 | 0,838 | 1,424 |
| Poisson implicito por odds | 2026 | 8 | 0,375 | 1,194 | 0,738 | 3,656 | 1,504 | 0,944 | 1,820 |
| Poisson hibrido odds + ratings | 2022 | 64 | 0,531 | 0,997 | 0,582 | 2,943 | 1,047 | 0,837 | 1,453 |
| Poisson hibrido odds + ratings | 2026 | 12 | 0,500 | 1,035 | 0,640 | 3,168 | 1,308 | 0,696 | 1,595 |

Observacao: a avaliacao de 2026 ainda tem amostra pequena, agora com 12 jogos no modelo hibrido e 8 jogos nos modelos dependentes de odds. Os resultados de 2026 devem ser tratados como monitoramento inicial, nao como evidencia definitiva de performance.

## Jogos finalizados de 2026 avaliados pelo hibrido

| data | jogo | placar real | resultado previsto | placar modal previsto |
|---|---|---:|---|---:|
| 2026-06-11 | Mexico x South Africa | 2-0 | Mexico | 1-0 |
| 2026-06-11 | South Korea x Czech Republic | 2-1 | South Korea | 1-0 |
| 2026-06-12 | Canada x Bosnia & Herzegovina | 1-1 | Canada | 1-0 |
| 2026-06-12 | USA x Paraguay | 4-1 | USA | 1-0 |
| 2026-06-13 | Qatar x Switzerland | 1-1 | Switzerland | 0-2 |
| 2026-06-13 | Brazil x Morocco | 1-1 | Brazil | 1-0 |
| 2026-06-13 | Haiti x Scotland | 0-1 | Scotland | 0-1 |
| 2026-06-13 | Australia x Turkey | 2-0 | Turkey | 0-1 |
| 2026-06-14 | Germany x Curacao | 7-1 | Germany | 3-0 |
| 2026-06-14 | Ivory Coast x Ecuador | 1-0 | Ecuador | 0-1 |
| 2026-06-14 | Netherlands x Japan | 2-2 | Netherlands | 1-0 |
| 2026-06-14 | Sweden x Tunisia | 5-1 | Sweden | 1-0 |

## Leitura dos resultados

O modelo hibrido continua sendo a previsao principal da V1:

- cobre todos os jogos de grupos de 2026, inclusive jogos sem odds;
- preserva o sinal de mercado quando odds existem;
- gera probabilidades de resultado e placares via distribuicao de Poisson;
- foi ligeiramente melhor que o baseline de mercado em 2022 em log loss e Brier;
- em 2026, na amostra parcial atual, superou o baseline e o Poisson puramente por odds em acuracia, log loss e Brier.

O desempenho de placar em 2026 piorou em relacao ao primeiro corte porque alguns jogos tiveram placares extremos ou menos provaveis pelo modelo, especialmente `Germany 7-1 Curacao`, `Sweden 5-1 Tunisia` e `USA 4-1 Paraguay`. Isso e esperado em uma janela curta e reforca que a avaliacao deve acompanhar probabilidades, nao apenas o placar modal.

## Decisao tecnica

Manter os tres modelos no pipeline:

1. baseline mercado 1x2 como benchmark;
2. Poisson implicito por odds como benchmark de placar baseado so no mercado;
3. Poisson hibrido odds + ratings como modelo principal da V1.

Proxima melhoria recomendada: adicionar um relatorio automatico de monitoramento incremental para 2026, atualizando metricas por rodada/dia conforme novos placares entrarem.
