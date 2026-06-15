source("R/01_coleta/lib_coleta.R")

ensure_dirs()

matches_path <- project_path("data/interim/matches/worldcup_matches_2022_onwards.csv")
odds_path <- project_path("data/interim/odds/worldcup_odds_2022_onwards.csv")

matches <- read_existing_csv(matches_path) |>
  dplyr::mutate(date = lubridate::ymd(date))

odds <- read_existing_csv(odds_path) |>
  dplyr::mutate(date = lubridate::ymd(date))

norm_team <- function(x) {
  x |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("&", "and") |>
    stringr::str_replace_all("[^a-z0-9]+", " ") |>
    stringr::str_squish()
}

matches_keys <- matches |>
  dplyr::mutate(team_a_key = norm_team(team_a), team_b_key = norm_team(team_b))

odds_keys <- odds |>
  dplyr::mutate(team_a_key = norm_team(team_a), team_b_key = norm_team(team_b))

audit <- matches_keys |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    n_jogos = dplyr::n(),
    n_jogos_com_placar = sum(!is.na(score_a) & !is.na(score_b)),
    n_jogos_sem_data = sum(is.na(date)),
    n_times_distintos = dplyr::n_distinct(c(team_a, team_b)),
    n_duplicatas = sum(duplicated(paste(date, team_a_key, team_b_key))),
    .groups = "drop"
  )

missing_odds <- matches_keys |>
  dplyr::filter(score_status == "final") |>
  dplyr::anti_join(
    odds_keys,
    by = c("year", "date", "team_a_key", "team_b_key")
  )

odds_invalidas <- odds |>
  dplyr::filter(
    !is.na(odds_team_a) & odds_team_a <= 0 |
      !is.na(odds_draw) & odds_draw <= 0 |
      !is.na(odds_team_b) & odds_team_b <= 0
  )

audit <- audit |>
  dplyr::mutate(
    n_jogos_sem_odds = purrr::map_int(year, \(ano) sum(missing_odds$year == ano)),
    n_odds_invalidas = purrr::map_int(year, \(ano) sum(odds_invalidas$year == ano))
  )

readr::write_csv(audit, project_path("data/raw/metadata/auditoria_coleta_resumo.csv"))

linhas <- c(
  "# Auditoria da Coleta",
  "",
  paste0("Gerado em: ", now_iso()),
  "",
  "## Resumo",
  "",
  paste(capture.output(print(audit)), collapse = "\n"),
  "",
  "## Pendencias",
  ""
)

pendencias <- c()
if (nrow(missing_odds) > 0) {
  pendencias <- c(
    pendencias,
    paste0("- Jogos finalizados sem odds ligadas: ", nrow(missing_odds), ". Ver `data/raw/metadata/jogos_sem_odds.csv`.")
  )
}
if (nrow(odds_invalidas) > 0) {
  pendencias <- c(
    pendencias,
    paste0("- Odds invalidas: ", nrow(odds_invalidas), ". Valores devem ser numericos positivos.")
  )
}
if (length(pendencias) == 0) {
  pendencias <- "- Nenhuma pendencia critica detectada nos checks minimos."
}

readr::write_csv(missing_odds, project_path("data/raw/metadata/jogos_sem_odds.csv"))
readr::write_lines(c(linhas, pendencias), project_path("reports/auditoria_coleta.md"))

