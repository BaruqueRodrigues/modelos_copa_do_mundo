source("R/02_modelagem/lib_modelagem.R")

ensure_modeling_dirs()

base_path <- project_path("data/processed/match_modeling_base.csv")
international_results_path <- project_path("data/interim/matches/international_results_since_2018.csv")
elo_path <- project_path("data/interim/elo/world_football_elo_2022_onwards.csv")

v2_output_path <- project_path("data/processed/model_poisson_hybrid_v2_predictions.csv")
v2_evaluation_output_path <- project_path("data/processed/model_evaluation_summary_v2.csv")
combined_evaluation_output_path <- project_path("data/processed/model_evaluation_summary_all.csv")
v2_model_info_path <- project_path("data/processed/rating_model_v2_info.csv")

modeling_base <- readr::read_csv(base_path, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(date = lubridate::ymd(date))

international_results <- readr::read_csv(international_results_path, show_col_types = FALSE) |>
  janitor::clean_names()

elo_history <- readr::read_csv(elo_path, show_col_types = FALSE) |>
  janitor::clean_names()

rating_models_v2 <- fit_rating_models_v2(international_results, elo_history)

readr::write_csv(
  tibble::tibble(
    train_rows = rating_models_v2$train_rows,
    fallback_draw_rate = rating_models_v2$fallback_draw_rate,
    fallback_total_goals = rating_models_v2$fallback_total_goals
  ),
  v2_model_info_path
)

hybrid_v2_predictions <- modeling_base |>
  dplyr::filter(!is_knockout_placeholder) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    has_market = !any(is.na(c(market_p_a, market_p_d, market_p_b))),
    market_weight = dynamic_market_weight(
      has_market,
      n_bookmakers,
      odds_overround,
      abs(model_elo_diff)
    ),
    rating_probs = list(predict_rating_result_probs(model_elo_diff, neutral, rating_models_v2)),
    total_goals_prior = predict_total_goals_v2(
      model_elo_diff,
      neutral,
      recent_goals_for_a,
      recent_goals_for_b,
      recent_goals_against_a,
      recent_goals_against_b,
      rating_models_v2
    )
  ) |>
  tidyr::unnest_wider(rating_probs) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    blended_probs = list(blend_result_probs(
      market_p_a, market_p_d, market_p_b,
      rating_p_a, rating_p_d, rating_p_b,
      market_weight = market_weight
    ))
  ) |>
  tidyr::unnest_wider(blended_probs) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    poisson_fit = list(fit_poisson_to_result_probs(
      hybrid_p_a, hybrid_p_d, hybrid_p_b,
      total_goals_prior = total_goals_prior,
      total_penalty = 0.09,
      max_goals = 12
    ))
  ) |>
  tidyr::unnest_wider(poisson_fit) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    adjustment_params = list(v2_adjustment_parameters(
      model_elo_diff,
      fitted_p_a,
      fitted_p_d,
      fitted_p_b
    ))
  ) |>
  tidyr::unnest_wider(adjustment_params) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    score_dist = list(adjusted_score_distribution(
      lambda_a,
      lambda_b,
      rho = dixon_coles_rho,
      tail_strength = tail_strength,
      favorite_side = favorite_side,
      negative_binomial_size = negative_binomial_size,
      max_goals = 12
    )),
    adjusted_result_probs = list(result_probs_from_distribution(score_dist)),
    top_score = list(top_score_from_distribution(score_dist)),
    observed_score_probability = observed_score_probability_from_distribution(
      score_dist,
      score_a,
      score_b
    )
  ) |>
  tidyr::unnest_wider(adjusted_result_probs, names_sep = "_") |>
  tidyr::unnest_wider(top_score) |>
  dplyr::ungroup() |>
  dplyr::transmute(
    model = "poisson_hybrid_v2_total_dc_tail",
    year, match_id, date, stage, group, team_a, team_b,
    score_a, score_b, score_status, actual_result,
    pred_p_a = fitted_p_a,
    pred_p_d = fitted_p_d,
    pred_p_b = fitted_p_b,
    pred_result = c("A", "D", "B")[
      max.col(
        cbind(
          fitted_p_a,
          fitted_p_d,
          fitted_p_b
        ),
        ties.method = "first"
      )
    ],
    lambda_a,
    lambda_b,
    pred_score_a,
    pred_score_b,
    pred_score,
    pred_score_probability,
    observed_score_probability,
    odds_aggregate_method,
    n_bookmakers,
    rating_p_a,
    rating_p_d,
    rating_p_b,
    hybrid_p_a,
    hybrid_p_d,
    hybrid_p_b,
    adjusted_score_p_a = adjusted_result_probs_p_a,
    adjusted_score_p_d = adjusted_result_probs_p_d,
    adjusted_score_p_b = adjusted_result_probs_p_b,
    model_elo_diff,
    total_goals_prior,
    market_weight,
    dixon_coles_rho,
    tail_strength,
    negative_binomial_size,
    favorite_side,
    poisson_fit_sse
  )

readr::write_csv(hybrid_v2_predictions, v2_output_path)

v2_evaluation <- hybrid_v2_predictions |>
  evaluate_predictions()

readr::write_csv(v2_evaluation, v2_evaluation_output_path)

v1_evaluation_path <- project_path("data/processed/model_evaluation_summary.csv")
if (fs::file_exists(v1_evaluation_path)) {
  combined_evaluation <- dplyr::bind_rows(
    readr::read_csv(v1_evaluation_path, show_col_types = FALSE),
    v2_evaluation
  ) |>
    dplyr::arrange(year, model)

  readr::write_csv(combined_evaluation, combined_evaluation_output_path)
}

message("Previsoes V2 escritas em: ", v2_output_path)
message("Resumo V2 escrito em: ", v2_evaluation_output_path)
message("Resumo combinado escrito em: ", combined_evaluation_output_path)
