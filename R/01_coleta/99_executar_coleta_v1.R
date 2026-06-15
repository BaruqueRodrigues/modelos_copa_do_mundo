scripts <- c(
  "R/01_coleta/00_criar_estrutura_e_fontes.R",
  "R/01_coleta/01_baixar_openfootball_2022.R",
  "R/01_coleta/02_baixar_openfootball_2026.R",
  "R/01_coleta/03_parsear_openfootball.R",
  "R/01_coleta/04_baixar_international_results.R",
  "R/01_coleta/05_baixar_fifa_ranking.R",
  "R/01_coleta/06_baixar_elo_ratings.R",
  "R/01_coleta/07_baixar_odds.R",
  "R/01_coleta/07b_baixar_odds_oddschecker.R",
  "R/01_coleta/10_consolidar_overall_terceiros.R",
  "R/01_coleta/08_auditar_coleta.R",
  "R/01_coleta/09_criar_manifesto_raw.R"
)

purrr::walk(scripts, source)
