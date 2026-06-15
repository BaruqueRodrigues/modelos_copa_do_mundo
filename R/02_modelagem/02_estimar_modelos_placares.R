source("R/02_modelagem/lib_modelagem.R")

ensure_modeling_dirs()

base_path <- project_path("data/processed/match_modeling_base.csv")
international_results_path <- project_path("data/interim/matches/international_results_since_2018.csv")
elo_path <- project_path("data/interim/elo/world_football_elo_2022_onwards.csv")

market_output_path <- project_path("data/processed/model_baseline_market_1x2.csv")
poisson_odds_output_path <- project_path("data/processed/model_poisson_odds_implicit_predictions.csv")
hybrid_output_path <- project_path("data/processed/model_poisson_hybrid_predictions.csv")
evaluation_output_path <- project_path("data/processed/model_evaluation_summary.csv")
rating_model_info_path <- project_path("data/processed/rating_model_info.csv")

modeling_base <- readr::read_csv(base_path, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(date = lubridate::ymd(date))

international_results <- readr::read_csv(international_results_path, show_col_types = FALSE) |>
  janitor::clean_names()

elo_history <- readr::read_csv(elo_path, show_col_types = FALSE) |>
  janitor::clean_names()

rating_models <- fit_rating_models(international_results, elo_history)

readr::write_csv(
  tibble::tibble(
    train_rows = rating_models$train_rows,
    fallback_draw_rate = rating_models$fallback_draw_rate,
    fallback_total_goals = rating_models$fallback_total_goals
  ),
  rating_model_info_path
)

market_predictions <- modeling_base |>
  dplyr::filter(!is.na(market_p_a), !is.na(market_p_d), !is.na(market_p_b)) |>
  dplyr::transmute(
    model = "baseline_market_1x2",
    year, match_id, date, stage, group, team_a, team_b,
    score_a, score_b, score_status, actual_result,
    pred_p_a = market_p_a,
    pred_p_d = market_p_d,
    pred_p_b = market_p_b,
    pred_result = market_pred_result,
    lambda_a = NA_real_,
    lambda_b = NA_real_,
    pred_score_a = NA_integer_,
    pred_score_b = NA_integer_,
    pred_score = NA_character_,
    pred_score_probability = NA_real_,
    observed_score_probability = NA_real_,
    odds_aggregate_method,
    n_bookmakers
  )

readr::write_csv(market_predictions, market_output_path)

worldcup_2022_total_prior <- modeling_base |>
  dplyr::filter(year == 2022, score_status == "final") |>
  dplyr::summarise(total_prior = mean(score_a + score_b, na.rm = TRUE)) |>
  dplyr::pull(total_prior)

poisson_odds_predictions <- modeling_base |>
  dplyr::filter(!is.na(market_p_a), !is.na(market_p_d), !is.na(market_p_b)) |>
  dplyr::mutate(total_goals_prior = worldcup_2022_total_prior) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    poisson_fit = list(fit_poisson_to_result_probs(
      market_p_a, market_p_d, market_p_b,
      total_goals_prior = total_goals_prior,
      total_penalty = 0.02
    )),
    top_score = list(top_score_from_lambdas(
      poisson_fit$lambda_a, poisson_fit$lambda_b
    )),
    observed_score_probability = observed_score_probability(
      poisson_fit$lambda_a, poisson_fit$lambda_b, score_a, score_b
    )
  ) |>
  tidyr::unnest_wider(poisson_fit) |>
  tidyr::unnest_wider(top_score) |>
  dplyr::ungroup() |>
  dplyr::transmute(
    model = "poisson_odds_implicit",
    year, match_id, date, stage, group, team_a, team_b,
    score_a, score_b, score_status, actual_result,
    pred_p_a = fitted_p_a,
    pred_p_d = fitted_p_d,
    pred_p_b = fitted_p_b,
    pred_result = c("A", "D", "B")[
      max.col(cbind(fitted_p_a, fitted_p_d, fitted_p_b), ties.method = "first")
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
    poisson_fit_sse,
    total_goals_prior
  )

readr::write_csv(poisson_odds_predictions, poisson_odds_output_path)

hybrid_predictions <- modeling_base |>
  dplyr::filter(!is_knockout_placeholder) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    rating_probs = list(predict_rating_result_probs(model_elo_diff, neutral, rating_models)),
    total_goals_prior = predict_total_goals(model_elo_diff, neutral, rating_models)
  ) |>
  tidyr::unnest_wider(rating_probs) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    blended_probs = list(blend_result_probs(
      market_p_a, market_p_d, market_p_b,
      rating_p_a, rating_p_d, rating_p_b,
      market_weight = 0.80
    ))
  ) |>
  tidyr::unnest_wider(blended_probs) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    poisson_fit = list(fit_poisson_to_result_probs(
      hybrid_p_a, hybrid_p_d, hybrid_p_b,
      total_goals_prior = total_goals_prior,
      total_penalty = 0.05
    )),
    top_score = list(top_score_from_lambdas(
      poisson_fit$lambda_a, poisson_fit$lambda_b
    )),
    observed_score_probability = observed_score_probability(
      poisson_fit$lambda_a, poisson_fit$lambda_b, score_a, score_b
    )
  ) |>
  tidyr::unnest_wider(poisson_fit) |>
  tidyr::unnest_wider(top_score) |>
  dplyr::ungroup() |>
  dplyr::transmute(
    model = "poisson_hybrid_odds_ratings",
    year, match_id, date, stage, group, team_a, team_b,
    score_a, score_b, score_status, actual_result,
    pred_p_a = fitted_p_a,
    pred_p_d = fitted_p_d,
    pred_p_b = fitted_p_b,
    pred_result = c("A", "D", "B")[
      max.col(cbind(fitted_p_a, fitted_p_d, fitted_p_b), ties.method = "first")
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
    model_elo_diff,
    total_goals_prior,
    poisson_fit_sse
  )

readr::write_csv(hybrid_predictions, hybrid_output_path)

evaluation <- dplyr::bind_rows(
  market_predictions,
  poisson_odds_predictions,
  hybrid_predictions
) |>
  evaluate_predictions()

readr::write_csv(evaluation, evaluation_output_path)

message("Previsoes de mercado escritas em: ", market_output_path)
message("Previsoes Poisson odds escritas em: ", poisson_odds_output_path)
message("Previsoes hibridas escritas em: ", hybrid_output_path)
message("Resumo de avaliacao escrito em: ", evaluation_output_path)
