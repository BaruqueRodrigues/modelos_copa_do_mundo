source("R/01_coleta/lib_coleta.R")

ensure_dirs()

resultados_path <- project_path("data/raw/matches/international_results.csv")
if (!fs::file_exists(resultados_path)) {
  stop("Arquivo international_results.csv nao encontrado. Execute R/01_coleta/04_baixar_international_results.R antes.")
}

expected_score <- function(rating_a, rating_b) {
  1 / (1 + 10 ^ ((rating_b - rating_a) / 400))
}

actual_score <- function(score_a, score_b) {
  dplyr::case_when(
    score_a > score_b ~ 1,
    score_a == score_b ~ 0.5,
    score_a < score_b ~ 0
  )
}

update_elo_one_match <- function(state, match, k = 20) {
  home <- match$home_team
  away <- match$away_team
  rating_home <- state[[home]] %||% 1500
  rating_away <- state[[away]] %||% 1500
  exp_home <- expected_score(rating_home, rating_away)
  act_home <- actual_score(match$home_score, match$away_score)

  state[[home]] <- rating_home + k * (act_home - exp_home)
  state[[away]] <- rating_away + k * ((1 - act_home) - (1 - exp_home))
  state
}

build_pre_match_elo <- function(matches, k = 20) {
  state <- list()
  rows <- vector("list", nrow(matches))

  for (i in seq_len(nrow(matches))) {
    match <- matches[i, ]
    home <- match$home_team
    away <- match$away_team
    rating_home <- state[[home]] %||% 1500
    rating_away <- state[[away]] %||% 1500

    rows[[i]] <- tibble::tibble(
      date = match$date,
      home_team = home,
      away_team = away,
      home_elo_pre = rating_home,
      away_elo_pre = rating_away,
      elo_k = k,
      source = "calculated_from_international_results",
      source_file = "data/raw/matches/international_results.csv"
    )

    if (!is.na(match$home_score) && !is.na(match$away_score)) {
      state <- update_elo_one_match(state, match, k = k)
    }
  }

  dplyr::bind_rows(rows)
}

resultados <- readr::read_csv(resultados_path, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(date = lubridate::ymd(date)) |>
  dplyr::arrange(date, home_team, away_team)

elo <- build_pre_match_elo(resultados)
elo_recorte <- elo |>
  dplyr::filter(date >= lubridate::ymd("2022-01-01"))

readr::write_csv(elo, project_path("data/raw/elo/world_football_elo.csv"))
readr::write_csv(elo_recorte, project_path("data/interim/elo/world_football_elo_2022_onwards.csv"))

