# Analise Atualizada de Modelagem de Placares

Gerado em: 2026-06-15

## Resumo executivo

Os novos dados melhoram bastante a viabilidade de modelos de placar para a Copa 2026. A principal mudanca e a inclusao de rankings FIFA atuais e ratings externos do World Football Elo, consolidados por selecao em `data/interim/teams/team_overall_external_consolidated.csv`.

Com isso, o projeto agora tem:

- odds 1x2 para 64 jogos da Copa 2022;
- odds 1x2 para 68 dos 72 jogos da fase de grupos da Copa 2026;
- placares finais dos 64 jogos da Copa 2022;
- 4 placares finais da Copa 2026 ate a coleta atual;
- historico amplo de 8.180 jogos internacionais desde 2018;
- Elo historico pre-jogo para 4.640 jogos desde 2022;
- ranking FIFA atual para 211 selecoes;
- rating externo consolidado para 258 selecoes;
- cobertura de ratings para 48/48 selecoes da fase de grupos de 2026 e 32/32 selecoes de 2022.

## Cobertura dos dados

### Jogos

Arquivo: `data/interim/matches/worldcup_matches_2022_onwards.csv`

- 2022: 64 jogos, todos com placar final.
- 2026: 104 jogos no calendario, sendo 72 de grupos e 32 de mata-mata.
- 2026: 4 jogos marcados como finalizados e 100 como agendados.
- Os jogos de mata-mata ainda contem placeholders de classificacao, entao a primeira modelagem deve focar a fase de grupos.

### Odds

Arquivo: `data/interim/odds/worldcup_odds_2022_onwards.csv`

- 706 linhas de odds 1x2.
- 2022: 192 linhas vindas de `football-data.co.uk`, cobrindo 64 jogos.
- 2026: 514 linhas vindas do OddsChecker, cobrindo 68 jogos de grupos.
- Mercado disponivel: apenas `1x2`.
- Ainda nao ha mercados de placar exato, over/under, ambas marcam ou handicap.

Arquivo: `data/interim/odds/oddschecker_worldcup_2026_group_stage_odds.csv`

- 514 linhas.
- 68 jogos.
- 8 casas.
- 60 linhas com `odds_team_b` ausente.
- Overround das linhas completas: mediana proxima de 1,06.

Recomendacao: agregar odds por jogo usando apenas linhas completas e uma estatistica robusta, preferencialmente mediana por casa.

### Rankings e ratings externos

Arquivos:

- `data/interim/rankings/fifa_rankings_2022_onwards.csv`
- `data/interim/teams/team_external_ratings_long.csv`
- `data/interim/teams/team_overall_external_consolidated.csv`

Principais achados:

- Ranking FIFA atual cobre 211 selecoes.
- Consolidado FIFA + Elo externo cobre 258 selecoes.
- 48/48 selecoes da fase de grupos de 2026 tem rating consolidado.
- 32/32 selecoes da Copa 2022 tem rating consolidado.
- FIFA e Elo externo sao bastante consistentes entre si: correlacao aproximada de 0,96 nos pontos brutos e 0,98 nos overalls normalizados.

Importante: esses ratings sao atuais de junho de 2026. Eles sao otimos para prever jogos futuros de 2026, mas nao devem ser usados para backtest limpo de 2022, pois isso introduziria vazamento temporal. Para validar em 2022, usar odds de 2022 e Elo historico pre-jogo.

## Benchmarks ja observados

### Mercado 1x2 em 2022

Usando `Market average` de `football-data.co.uk`:

- jogos avaliados: 64;
- acuracia 1x2: 53,1%;
- log loss: 0,998;
- Brier score multiclasse: 0,584;
- empates reais: 15;
- empates previstos como classe mais provavel: 0.

Isso confirma que o mercado e um benchmark forte para probabilidades de resultado, mas nao resolve diretamente placares e tende a nunca escolher empate como resultado modal.

### Mercado 1x2 em 2026

Agregando odds completas do OddsChecker por mediana:

- jogos com odds agregadas: 68;
- previsao modal: 42 vitorias do time A e 26 vitorias do time B;
- nenhum empate como resultado mais provavel;
- maior probabilidade modal observada: acima de 0,91 em jogos muito desbalanceados.

## Modelos recomendados agora

### 1. Baseline de mercado 1x2

Converter odds em probabilidades implicitas sem margem.

Uso:

- benchmark obrigatorio;
- avaliacao de calibracao;
- insumo para modelos de placar.

Nao produz placar diretamente.

### 2. Poisson implicito pelas odds

Estimar `lambda_a` e `lambda_b` de modo que a matriz de placares reproduza as probabilidades de vitoria, empate e derrota dadas pelo mercado 1x2.

Uso:

- primeira versao real de previsao de placar;
- simples, auditavel e diretamente ligada as odds;
- gera distribuicao completa de placares.

Limitacao:

- com apenas odds 1x2, ha pouca informacao sobre total de gols. Sera necessario impor uma hipotese ou prior para o total esperado de gols.

### 3. Poisson com forca externa das selecoes

Usar diferencial de rating entre selecoes como variavel explicativa para `lambda_a` e `lambda_b`.

Features candidatas:

- diferencial do `external_overall_consensus_40_99`;
- diferencial de pontos FIFA;
- diferencial de Elo externo atual;
- indicador de campo neutro;
- confederacao, se necessario;
- forma recente baseada em jogos internacionais desde 2018.

Uso:

- previsao para 2026;
- ajuste de placares onde odds estao ausentes ou incompletas;
- suporte para simulacao de cenarios.

Cuidados:

- ratings atuais nao devem ser usados como se fossem historicos em backtest 2022;
- para validacao historica, preferir Elo pre-jogo do arquivo `data/interim/elo/world_football_elo_2022_onwards.csv`.

### 4. Modelo hibrido odds + ratings

Recomendacao principal para V1.

Estrutura sugerida:

- odds 1x2 definem o nivel de favoritismo observado pelo mercado;
- ratings FIFA/Elo ajudam a estabilizar jogos com odds ruidosas, ausentes ou incompletas;
- historico internacional ajuda a calibrar total de gols e dispersao;
- Poisson bivariado ou Dixon-Coles gera placares.

Esse e o melhor equilibrio atual entre robustez, interpretabilidade e dados disponiveis.

## Modelos ainda nao indicados

- Placar exato via odds de correct score: esse mercado ainda nao existe na base.
- Modelos com over/under ou ambas marcam: esses mercados ainda nao existem na base.
- Machine learning pesado para placar: a base de Copa com odds e resultado ainda e pequena.
- Ranking FIFA como unica fonte: agora existe, mas deve ser combinado com Elo e odds.

## Proxima etapa recomendada

Construir `data/processed/match_modeling_base.csv` com uma linha por jogo e:

- identificadores do jogo;
- times;
- placar quando existir;
- status do placar;
- odds agregadas 1x2;
- probabilidades sem margem;
- rating FIFA/Elo/overall do time A;
- rating FIFA/Elo/overall do time B;
- diferenciais de rating;
- Elo historico pre-jogo quando disponivel;
- features simples de forma recente.

Depois disso, implementar tres modelos em ordem:

1. baseline de mercado 1x2;
2. Poisson implicito pelas odds;
3. Poisson/Dixon-Coles hibrido com odds, Elo historico e rating externo atual.
