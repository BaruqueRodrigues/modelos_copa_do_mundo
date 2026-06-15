# Plano de Coleta de Dados

Ultima revisao: 2026-06-13

## Como Usar Este Arquivo

Este arquivo e um backlog operacional da etapa de coleta de dados. Em chamadas futuras, podemos continuar por ID, por exemplo: "execute o COL-03" ou "revise os bloqueios da coleta".

Status possiveis:

- `[ ]` nao iniciado
- `[~]` em andamento
- `[x]` concluido
- `[!]` bloqueado ou precisa de decisao

Regra de trabalho:

- Cada item deve gerar um artefato verificavel.
- Dados brutos devem ir para `data/raw/`.
- Transformacoes leves ou padronizacoes devem ir para `data/interim/`.
- Dados prontos para modelagem devem ficar fora desta etapa e entrar em preparacao de dados.

## Escopo V1

Recorte temporal:

- Copa do Mundo FIFA masculina de 2022 em diante.
- Incluir 2022 como base historica completa.
- Incluir 2026 como base de calendario, resultados parciais ou previsoes, conforme disponibilidade no momento da coleta.

Objetivo da coleta:

- Montar uma base reproduzivel para testar modelos que preveem resultado de jogos da Copa do Mundo.
- Priorizar dados que existem de forma aberta, estruturada e facil de atualizar.
- Incluir odds de casas de apostas como insumo mandatorio dos modelos.

Fora da V1:

- Copas anteriores a 2022.
- Estatisticas avancadas se nao houver fonte aberta e simples.
- Dados de elenco como dependencia obrigatoria.

## Fontes Prioritarias

| Fonte | Uso | Status | Observacao |
|---|---|---|---|
| `openfootball/worldcup` | Tabela de jogos, grupos, fases, estadios e resultados | Fonte primaria | Repositorio aberto em Football.TXT, inclui 2022 e 2026. |
| `martj42/international_results` | Historico de partidas internacionais recentes | Fonte auxiliar | CSV amplo desde 1872; usar apenas jogos antes de cada partida para features de forma recente. |
| StatsBomb Open Data | Eventos e estatisticas avancadas de 2022 | Fonte opcional | Cobre FIFA World Cup 2022 com eventos e 360; usar somente se a V1 precisar de estatisticas avancadas. |
| FIFA Ranking | Ranking pre-torneio ou pre-jogo | Fonte auxiliar | Ranking existe para 2022 e 2026; exige decidir a data correta de referencia. |
| World Football Elo Ratings | Forca das selecoes antes do jogo | Fonte auxiliar | Candidato forte; precisa validar download/parse reproduzivel. |
| OddsPortal | Odds historicas e atuais dos jogos da Copa | Fonte obrigatoria candidata | Lista World Cup 2022 como resultados, placares e odds historicas; tambem tem secao 2026. Exige validar termos de uso e estrategia de coleta. |
| football-data.co.uk | Odds historicas e planilhas de Copa | Fonte obrigatoria candidata | Site informa dados de odds e tem recurso "World Cup XLSX"; precisa confirmar conteudo e cobertura dos jogos da Copa. |
| The Odds API ou API similar | Odds atuais e historicas via API | Fonte obrigatoria candidata | Pode exigir chave e/ou plano pago; usar como fallback reproduzivel se scraping nao for adequado. |
| Wikipedia/FIFA/RSSSF | Validacao cruzada | Fonte de auditoria | Usar para checar totais, datas, sedes e divergencias. |

Links de referencia:

- https://github.com/openfootball/worldcup
- https://github.com/martj42/international_results
- https://github.com/statsbomb/open-data
- https://www.fifa.com/fifa-world-ranking/men
- https://www.eloratings.net/
- https://www.oddsportal.com/football/world/world-cup-2022/results/
- https://www.football-data.co.uk/data.php
- https://www.the-odds-api.com/

## Estrutura de Pastas Desejada

```text
data/
  raw/
    matches/
    rankings/
    elo/
    odds/
    statsbomb/
    metadata/
  interim/
    matches/
    rankings/
    elo/
    odds/
  processed/
R/
  01_coleta/
reports/
```

## Padroes Tecnicos Obrigatorios

Todos os scripts em `R/01_coleta/` devem seguir estes padroes:

- Usar R com `tidyverse` como base de manipulacao de dados.
- Preferir programacao funcional com `purrr` para iterar sobre fontes, anos, URLs, arquivos e listas.
- Chamar funcoes com namespace explicito no formato `pacote::funcao`.
- Evitar `library()` e `require()` dentro dos scripts de coleta.
- Separar download, leitura, parsing, validacao e escrita em funcoes pequenas.
- Evitar repeticao manual quando uma funcao + `purrr::map()` resolver o fluxo.
- Usar caminhos relativos ao projeto, preferencialmente com `here::here()` se o pacote estiver disponivel.
- Escrever arquivos tabulares com `readr::write_csv()`.
- Ler CSVs com `readr::read_csv()`.
- Ler JSONs com `jsonlite::fromJSON()` ou funcao equivalente explicitamente namespaced.
- Padronizar nomes de colunas com `janitor::clean_names()`.
- Trabalhar datas com `lubridate::ymd()` ou outra funcao `lubridate::*` apropriada.
- Quando usar requisicoes HTTP, preferir `httr2::*`.
- Scripts devem poder ser executados novamente sem quebrar a coleta.

Exemplo de estilo esperado:

```r
baixar_arquivo <- function(url, destino) {
  resposta <- httr2::request(url) |>
    httr2::req_perform()

  conteudo <- httr2::resp_body_string(resposta)
  readr::write_lines(conteudo, destino)
}

purrr::walk2(urls, destinos, baixar_arquivo)
```

## Backlog

### COL-01: Criar Estrutura de Pastas

- [ ] Criar `data/raw/matches/`
- [ ] Criar `data/raw/rankings/`
- [ ] Criar `data/raw/elo/`
- [ ] Criar `data/raw/odds/`
- [ ] Criar `data/raw/statsbomb/`
- [ ] Criar `data/raw/metadata/`
- [ ] Criar `data/interim/matches/`
- [ ] Criar `data/interim/rankings/`
- [ ] Criar `data/interim/elo/`
- [ ] Criar `data/interim/odds/`
- [ ] Criar `R/01_coleta/`
- [ ] Criar `reports/`

Artefato esperado:

- Pastas criadas no repositorio.

Pronto quando:

- `fs::dir_exists()` retorna `TRUE` para todas as pastas.

### COL-02: Registrar Inventario de Fontes

- [ ] Criar `data/raw/metadata/fontes_dados.csv`.
- [ ] Registrar nome da fonte.
- [ ] Registrar URL.
- [ ] Registrar tipo de dado.
- [ ] Registrar formato.
- [ ] Registrar cobertura temporal.
- [ ] Registrar licenca ou observacao de uso.
- [ ] Registrar status: `primaria`, `auxiliar`, `opcional`, `descartada`.

Artefato esperado:

- `data/raw/metadata/fontes_dados.csv`

Colunas sugeridas:

```text
fonte,url,tipo_dado,formato,cobertura_temporal,licenca,status,observacoes
```

Pronto quando:

- O arquivo existe.
- Todas as fontes prioritarias estao cadastradas.

### COL-03: Coletar Jogos da Copa 2022

- [ ] Criar script `R/01_coleta/01_baixar_openfootball_2022.R`.
- [ ] Baixar arquivos brutos da Copa 2022 do `openfootball/worldcup`.
- [ ] Salvar o arquivo original em `data/raw/matches/openfootball_worldcup_2022.txt`.
- [ ] Registrar data de acesso em `data/raw/metadata/data_access_log.csv`.
- [ ] Nao editar manualmente o arquivo bruto.

Artefato esperado:

- `data/raw/matches/openfootball_worldcup_2022.txt`
- `data/raw/metadata/data_access_log.csv`

Pronto quando:

- O arquivo bruto de 2022 existe.
- O log contem URL, data de acesso e caminho local.

### COL-04: Coletar Jogos/Calendario da Copa 2026

- [ ] Criar script `R/01_coleta/02_baixar_openfootball_2026.R`.
- [ ] Baixar arquivo da Copa 2026 do `openfootball/worldcup`.
- [ ] Salvar em `data/raw/matches/openfootball_worldcup_2026.txt`.
- [ ] Registrar se os jogos sao calendario, resultados parciais ou resultados completos.
- [ ] Registrar data de acesso em `data/raw/metadata/data_access_log.csv`.

Artefato esperado:

- `data/raw/matches/openfootball_worldcup_2026.txt`

Pronto quando:

- O arquivo bruto de 2026 existe.
- O status da cobertura esta registrado: `calendario`, `parcial` ou `completo`.

### COL-05: Parsear Jogos 2022-2026

- [ ] Criar script `R/01_coleta/03_parsear_openfootball.R`.
- [ ] Ler arquivos brutos de 2022 e 2026.
- [ ] Transformar os jogos em tabela retangular.
- [ ] Padronizar nomes de colunas com `janitor::clean_names()`.
- [ ] Salvar resultado em `data/interim/matches/worldcup_matches_2022_onwards.csv`.

Campos minimos:

```text
competition
year
match_id
date
time
stage
group
team_a
team_b
score_a
score_b
score_status
stadium
city
country
source
source_file
```

Pronto quando:

- A tabela tem uma linha por jogo.
- Jogos de 2022 estao completos.
- Jogos de 2026 aparecem como calendario ou resultados, conforme disponibilidade.

### COL-06: Coletar Historico Internacional Recente

- [ ] Criar script `R/01_coleta/04_baixar_international_results.R`.
- [ ] Baixar `results.csv` de `martj42/international_results`.
- [ ] Salvar em `data/raw/matches/international_results.csv`.
- [ ] Filtrar, em arquivo interim, partidas desde 2018-01-01.
- [ ] Salvar em `data/interim/matches/international_results_since_2018.csv`.

Motivo:

- Usar somente historico recente para gerar features pre-jogo de forma, gols marcados, gols sofridos e forca de agenda.

Pronto quando:

- O CSV bruto existe.
- O CSV filtrado desde 2018 existe.
- O filtro de data foi aplicado por script.

### COL-07: Coletar Ranking FIFA

- [ ] Escolher fonte reproduzivel para ranking FIFA masculino.
- [ ] Criar script `R/01_coleta/05_baixar_fifa_ranking.R`.
- [ ] Coletar rankings relevantes antes da Copa 2022.
- [ ] Coletar rankings relevantes antes e durante a Copa 2026, se necessario.
- [ ] Salvar bruto em `data/raw/rankings/fifa_rankings.csv`.
- [ ] Salvar recorte usado em `data/interim/rankings/fifa_rankings_2022_onwards.csv`.

Decisao pendente:

- Usar ranking imediatamente anterior ao torneio ou ranking imediatamente anterior a cada jogo?

Pronto quando:

- A fonte esta documentada em `fontes_dados.csv`.
- A data de referencia do ranking esta documentada.
- Cada selecao de 2022 tem ranking antes do torneio.

### COL-08: Coletar Elo Ratings

- [ ] Validar se `eloratings.net` permite coleta reproduzivel dos ratings historicos.
- [ ] Criar script `R/01_coleta/06_baixar_elo_ratings.R`.
- [ ] Coletar rating antes de cada jogo, se possivel.
- [ ] Caso nao seja possivel, coletar rating antes do torneio.
- [ ] Salvar bruto em `data/raw/elo/world_football_elo.csv`.
- [ ] Salvar recorte em `data/interim/elo/world_football_elo_2022_onwards.csv`.

Decisao pendente:

- Usar Elo externo pronto ou calcular Elo proprio a partir de `international_results.csv`.

Pronto quando:

- Cada partida de 2022 tem Elo para os dois times antes do jogo ou antes do torneio.
- A regra temporal esta documentada para evitar vazamento.

### COL-09: Avaliar StatsBomb 2022

- [ ] Confirmar cobertura da Copa 2022 no StatsBomb Open Data.
- [ ] Criar script opcional `R/01_coleta/07_baixar_statsbomb_2022.R`.
- [ ] Baixar competicoes, partidas, eventos e lineups da Copa 2022.
- [ ] Salvar JSONs em `data/raw/statsbomb/`.
- [ ] Criar tabela resumida opcional em `data/interim/matches/statsbomb_match_stats_2022.csv`.

Status da V1:

- Opcional. Nao bloquear o primeiro modelo se este item demorar.

Pronto quando:

- O projeto consegue rodar sem StatsBomb.
- Se coletado, cada estatistica tem origem e granularidade documentadas.

### COL-10: Decidir Sobre Elencos

- [ ] Decidir se elencos entram na V1 ou ficam para V2.
- [ ] Se entrarem, escolher fonte: FIFA, Wikipedia ou StatsBomb lineups.
- [ ] Definir granularidade: elenco convocado, titulares por jogo ou jogadores utilizados.
- [ ] Registrar decisao em `data/raw/metadata/decisoes_coleta.md`.

Recomendacao atual:

- Nao incluir elencos na V1 minima.
- Usar somente lineups se vierem automaticamente do StatsBomb ou openfootball.more.

Pronto quando:

- A decisao esta registrada.
- A coleta principal nao depende de elencos.

### COL-11: Coletar Odds dos Jogos

- [ ] Escolher fonte primaria de odds para Copa 2022 e 2026.
- [ ] Validar termos de uso, necessidade de chave/API e limites de coleta.
- [ ] Criar script `R/01_coleta/07_baixar_odds.R`.
- [ ] Coletar odds 1X2: vitoria time A, empate, vitoria time B.
- [ ] Quando disponivel, coletar odds de abertura e fechamento.
- [ ] Quando disponivel, coletar odds medias e maximas do mercado.
- [ ] Salvar dados brutos em `data/raw/odds/`.
- [ ] Salvar tabela padronizada em `data/interim/odds/worldcup_odds_2022_onwards.csv`.
- [ ] Registrar data/hora de coleta, fonte e bookmaker/agregador.
- [ ] Criar chave de ligacao com jogos: `year`, `date`, `team_a`, `team_b`.

Fontes candidatas:

- OddsPortal: historico de odds para Copa 2022 e secao 2026.
- football-data.co.uk: verificar recurso "World Cup XLSX" e cobertura de odds.
- The Odds API ou API similar: usar se precisarmos de coleta reproduzivel via API.

Campos minimos:

```text
year
match_id
date
team_a
team_b
bookmaker
market
odds_team_a
odds_draw
odds_team_b
odds_type
collected_at
source
source_url
```

Valores esperados para `market`:

```text
1x2
```

Valores esperados para `odds_type`:

```text
opening
closing
average
maximum
snapshot
unknown
```

Regra anti-vazamento:

- Para prever jogos futuros, usar apenas odds disponiveis antes do inicio da partida.
- Para modelos historicos, preferir odds de fechamento se o objetivo for avaliar previsao de mercado imediatamente pre-jogo.
- Nunca usar odds coletadas depois do jogo sem documentar que representam odds historicas fechadas.

Pronto quando:

- Todos os jogos encerrados de 2022 tem pelo menos uma linha de odds 1X2.
- Jogos de 2026 tem odds 1X2 quando ja disponiveis na fonte escolhida.
- Jogos sem odds disponiveis estao listados em `reports/auditoria_coleta.md`.
- A tabela de odds consegue ser ligada a tabela de jogos sem ambiguidades.

### COL-12: Criar Auditoria da Coleta

- [ ] Criar script `R/01_coleta/08_auditar_coleta.R`.
- [ ] Conferir numero de jogos por ano.
- [ ] Conferir times ausentes.
- [ ] Conferir datas ausentes.
- [ ] Conferir placares ausentes quando o jogo ja ocorreu.
- [ ] Conferir odds ausentes para jogos encerrados.
- [ ] Conferir jogos com odds duplicadas sem identificacao de bookmaker/tipo.
- [ ] Conferir se odds tem valores numericos positivos.
- [ ] Conferir duplicatas.
- [ ] Conferir nomes inconsistentes de selecoes.
- [ ] Salvar relatorio em `reports/auditoria_coleta.md`.

Checks minimos:

```text
ano
n_jogos
n_jogos_com_placar
n_jogos_sem_data
n_times_distintos
n_duplicatas
n_jogos_sem_odds
n_odds_invalidas
```

Pronto quando:

- O relatorio existe.
- Problemas criticos estao listados em uma secao "Pendencias".

### COL-13: Congelar Base Bruta

- [ ] Criar manifesto `data/raw/metadata/raw_data_manifest.csv`.
- [ ] Registrar caminho local de cada arquivo bruto.
- [ ] Registrar URL original.
- [ ] Registrar data de acesso.
- [ ] Registrar tamanho do arquivo.
- [ ] Registrar hash/checksum, se viavel.

Artefato esperado:

- `data/raw/metadata/raw_data_manifest.csv`

Pronto quando:

- Todos os arquivos em `data/raw/` aparecem no manifesto.

## Ordem Recomendada de Execucao

1. COL-01: Criar estrutura de pastas.
2. COL-02: Registrar inventario de fontes.
3. COL-03: Coletar jogos da Copa 2022.
4. COL-04: Coletar jogos/calendario da Copa 2026.
5. COL-05: Parsear jogos 2022-2026.
6. COL-06: Coletar historico internacional recente.
7. COL-07: Coletar ranking FIFA.
8. COL-08: Coletar Elo ratings.
9. COL-11: Coletar odds dos jogos.
10. COL-12: Criar auditoria da coleta.
11. COL-13: Congelar base bruta.

Itens opcionais:

- COL-09: StatsBomb 2022.
- COL-10: Elencos.

## Decisoes Pendentes

- [!] DEC-01: Ranking FIFA sera pre-torneio ou pre-jogo?
- [!] DEC-02: Elo sera coletado externo ou calculado internamente?
- [!] DEC-03: 2026 entra como calendario para previsao ou apenas jogos ja encerrados?
- [!] DEC-04: StatsBomb entra na V1 ou fica para experimento separado?
- [!] DEC-05: O primeiro modelo preverá resultado em tres classes ou gols de cada time?
- [!] DEC-06: Odds usadas no modelo serao de abertura, fechamento, media de mercado ou snapshot pre-jogo?
- [!] DEC-07: A fonte primaria de odds sera OddsPortal, football-data.co.uk ou API paga/gratuita?

## Criterio de Pronto da Etapa de Coleta

- [ ] Existe uma tabela de jogos 2022 em diante em `data/interim/matches/worldcup_matches_2022_onwards.csv`.
- [ ] Existe uma tabela de odds em `data/interim/odds/worldcup_odds_2022_onwards.csv`.
- [ ] Cada jogo encerrado de 2022 tem odds 1X2 ou uma justificativa registrada para ausencia.
- [ ] Existe historico internacional recente em `data/interim/matches/international_results_since_2018.csv`.
- [ ] Fontes e datas de acesso estao registradas.
- [ ] O relatorio de auditoria foi gerado.
- [ ] Arquivos brutos nao foram editados manualmente.
- [ ] Decisoes pendentes que bloqueiam modelagem foram resolvidas ou explicitamente adiadas.
