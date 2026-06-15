# Decisoes de Coleta

Ultima revisao: 2026-06-15

## DEC-01: Ranking FIFA

Status: resolvido para V1.

Usar a API publica da pagina oficial `https://inside.fifa.com/fifa-world-ranking/men` como fonte primaria de rating externo agnostico. O pipeline coleta o release oficial mais recente em `data/raw/rankings/fifa_rankings_current.json` e salva os pontos oficiais em `data/interim/rankings/fifa_rankings_2022_onwards.csv`.

## DEC-02: Elo

Status: resolvido para V1.

Manter Elo calculado internamente apenas como insumo auxiliar/debug. Para o overall agnostico, usar tambem o rating publicado por terceiro em `https://www.eloratings.net/World.tsv`, consolidado por `R/01_coleta/10_consolidar_overall_terceiros.R`.

## DEC-03: Copa 2026

Status: incluir como calendario, resultados parciais ou completo conforme `data/raw/metadata/openfootball_coverage_status.csv` gerado no parse.

## DEC-04: StatsBomb

Status: adiado para experimento separado. Nao bloqueia V1 minima.

## DEC-06 e DEC-07: Odds

Status: usar apenas fontes abertas e reproduziveis sem compra de API key.

Para a V1, `football-data.co.uk` fica como fonte primaria aberta para odds historicas quando o arquivo World Cup XLSX estiver disponivel. The Odds API foi descartada para a V1 porque exige API key e pode exigir plano pago. OddsChecker foi adicionado como coleta aberta por scraping auditavel em `R/01_coleta/07b_baixar_odds_oddschecker.R`.
