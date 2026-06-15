source("R/02_modelagem/lib_modelagem.R")

ensure_modeling_dirs()

matches_path <- project_path("data/interim/matches/worldcup_matches_2022_onwards.csv")
odds_path <- project_path("data/interim/odds/worldcup_odds_2022_onwards.csv")
ratings_path <- project_path("data/interim/teams/team_overall_external_consolidated.csv")
elo_path <- project_path("data/interim/elo/world_football_elo_2022_onwards.csv")
international_results_path <- project_path("data/interim/matches/international_results_since_2018.csv")
output_path <- project_path("data/processed/match_modeling_base.csv")

matches <- readr::read_csv(matches_path, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(
    date = lubridate::ymd(date),
    team_a_key = normalize_team(team_a),
    team_b_key = normalize_team(team_b),
    actual_result = result_from_score(score_a, score_b),
    is_group_stage = stringr::str_detect(stage, "^Group"),
    is_knockout_placeholder = !is_group_stage & (
      stringr::str_detect(team_a, "^\\(|^[WL][0-9]+$|^[123][A-L]($|/)") |
        stringr::str_detect(team_b, "^\\(|^[WL][0-9]+$|^[123][A-L]($|/)")
    )
  )

odds <- readr::read_csv(odds_path, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(
    date = lubridate::ymd(date),
    team_a_key = normalize_team(team_a),
    team_b_key = normalize_team(team_b)
  )

odds_agg <- aggregate_odds(odds) |>
  dplyr::mutate(
    date = lubridate::ymd(date),
    team_a_key = normalize_team(team_a),
    team_b_key = normalize_team(team_b)
  ) |>
  dplyr::select(
    year, odds_match_id = match_id, date, team_a_key, team_b_key,
    odds_source = source,
    odds_aggregate_method, n_bookmakers,
    odds_team_a, odds_draw, odds_team_b, odds_overround,
    market_p_a, market_p_d, market_p_b, market_pred_result
  )

ratings <- readr::read_csv(ratings_path, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(team_key = normalize_team(team_key))

ratings_a <- ratings |>
  dplyr::select(
    team_a_key = team_key,
    external_overall_a = external_overall_consensus_40_99,
    fifa_rank_a = fifa_rank,
    fifa_points_a = fifa_points,
    fifa_overall_a = fifa_overall_40_99,
    elo_external_rank_a = elo_external_rank,
    elo_external_rating_a = elo_external_rating,
    elo_external_overall_a = elo_external_overall_40_99
  )

ratings_b <- ratings |>
  dplyr::select(
    team_b_key = team_key,
    external_overall_b = external_overall_consensus_40_99,
    fifa_rank_b = fifa_rank,
    fifa_points_b = fifa_points,
    fifa_overall_b = fifa_overall_40_99,
    elo_external_rank_b = elo_external_rank,
    elo_external_rating_b = elo_external_rating,
    elo_external_overall_b = elo_external_overall_40_99
  )

elo <- readr::read_csv(elo_path, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(
    date = lubridate::ymd(date),
    home_key = normalize_team(home_team),
    away_key = normalize_team(away_team)
  ) |>
  dplyr::select(date, home_key, away_key, home_elo_pre, away_elo_pre)

elo_direct <- elo |>
  dplyr::transmute(
    date,
    team_a_key = home_key,
    team_b_key = away_key,
    elo_pre_a_direct = home_elo_pre,
    elo_pre_b_direct = away_elo_pre
  )

elo_reversed <- elo |>
  dplyr::transmute(
    date,
    team_a_key = away_key,
    team_b_key = home_key,
    elo_pre_a_reversed = away_elo_pre,
    elo_pre_b_reversed = home_elo_pre
  )

international_results <- readr::read_csv(international_results_path, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(
    date = lubridate::ymd(date),
    home_team_key = normalize_team(home_team),
    away_team_key = normalize_team(away_team)
  )

base_without_form <- matches |>
  dplyr::left_join(
    odds_agg,
    by = c("year", "date", "team_a_key", "team_b_key")
  ) |>
  dplyr::left_join(ratings_a, by = "team_a_key") |>
  dplyr::left_join(ratings_b, by = "team_b_key") |>
  dplyr::left_join(elo_direct, by = c("date", "team_a_key", "team_b_key")) |>
  dplyr::left_join(elo_reversed, by = c("date", "team_a_key", "team_b_key")) |>
  dplyr::mutate(
    elo_pre_a = dplyr::coalesce(elo_pre_a_direct, elo_pre_a_reversed),
    elo_pre_b = dplyr::coalesce(elo_pre_b_direct, elo_pre_b_reversed),
    elo_join_direction = dplyr::case_when(
      !is.na(elo_pre_a_direct) ~ "direct",
      !is.na(elo_pre_a_reversed) ~ "reversed",
      TRUE ~ NA_character_
    ),
    external_overall_diff = external_overall_a - external_overall_b,
    fifa_rank_diff = fifa_rank_a - fifa_rank_b,
    fifa_points_diff = fifa_points_a - fifa_points_b,
    elo_external_rating_diff = elo_external_rating_a - elo_external_rating_b,
    elo_pre_diff = elo_pre_a - elo_pre_b,
    model_elo_diff = dplyr::coalesce(
      elo_pre_diff,
      elo_external_rating_diff,
      external_overall_diff * 25
    ),
    neutral = TRUE
  ) |>
  dplyr::select(-elo_pre_a_direct, -elo_pre_b_direct, -elo_pre_a_reversed, -elo_pre_b_reversed)

form_rows <- purrr::pmap_dfr(
  list(base_without_form$team_a_key, base_without_form$team_b_key, base_without_form$date),
  function(team_a_key, team_b_key, date) {
    form_a <- team_recent_form(team_a_key, date, international_results, n_recent = 10)
    form_b <- team_recent_form(team_b_key, date, international_results, n_recent = 10)

    tibble::tibble(
      recent_matches_a = form_a$recent_matches,
      recent_points_per_match_a = form_a$recent_points_per_match,
      recent_goals_for_a = form_a$recent_goals_for,
      recent_goals_against_a = form_a$recent_goals_against,
      recent_matches_b = form_b$recent_matches,
      recent_points_per_match_b = form_b$recent_points_per_match,
      recent_goals_for_b = form_b$recent_goals_for,
      recent_goals_against_b = form_b$recent_goals_against
    )
  }
)

modeling_base <- dplyr::bind_cols(base_without_form, form_rows) |>
  dplyr::mutate(
    recent_points_per_match_diff = recent_points_per_match_a - recent_points_per_match_b,
    recent_goals_for_diff = recent_goals_for_a - recent_goals_for_b,
    recent_goals_against_diff = recent_goals_against_a - recent_goals_against_b
  ) |>
  dplyr::arrange(year, date, match_id)

readr::write_csv(modeling_base, output_path)

message("Base de modelagem escrita em: ", output_path)
message("Linhas: ", nrow(modeling_base))
message("Jogos com odds agregadas: ", sum(!is.na(modeling_base$market_p_a)))
message("Jogos com rating externo A/B: ", sum(!is.na(modeling_base$external_overall_a) & !is.na(modeling_base$external_overall_b)))
