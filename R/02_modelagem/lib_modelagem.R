source("R/01_coleta/lib_coleta.R")

modeling_dirs <- function() {
  c("R/02_modelagem", "data/processed", "reports")
}

ensure_modeling_dirs <- function() {
  ensure_dirs(c(required_dirs(), modeling_dirs()))
}

normalize_team <- function(x) {
  key <- x |>
    stringi::stri_trans_general("Latin-ASCII") |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("&", "and") |>
    stringr::str_replace_all("[^a-z0-9]+", " ") |>
    stringr::str_squish()

  dplyr::recode(
    key,
    "cabo verde" = "cape verde",
    "cape verde islands" = "cape verde",
    "congo dr" = "dr congo",
    "democratic republic of congo" = "dr congo",
    "cote d ivoire" = "ivory coast",
    "czechia" = "czech republic",
    "ir iran" = "iran",
    "korea republic" = "south korea",
    "turkiye" = "turkey",
    "united states" = "usa",
    "united states of america" = "usa",
    .default = key
  )
}

safe_probability <- function(x, eps = 1e-12) {
  pmin(pmax(x, eps), 1 - eps)
}

normalize_probability_rows <- function(df, cols) {
  row_sum <- rowSums(df[cols], na.rm = FALSE)
  df[cols] <- df[cols] / row_sum
  df
}

result_from_score <- function(score_a, score_b) {
  dplyr::case_when(
    is.na(score_a) | is.na(score_b) ~ NA_character_,
    score_a > score_b ~ "A",
    score_a == score_b ~ "D",
    score_a < score_b ~ "B"
  )
}

result_probs_from_lambdas <- function(lambda_a, lambda_b, max_goals = 10) {
  goals <- 0:max_goals
  probs_a <- stats::dpois(goals, lambda_a)
  probs_b <- stats::dpois(goals, lambda_b)
  matrix_probs <- outer(probs_a, probs_b)

  tibble::tibble(
    p_a = sum(matrix_probs[row(matrix_probs) > col(matrix_probs)]),
    p_d = sum(diag(matrix_probs)),
    p_b = sum(matrix_probs[row(matrix_probs) < col(matrix_probs)])
  ) |>
    normalize_probability_rows(c("p_a", "p_d", "p_b"))
}

fit_poisson_to_result_probs <- function(p_a, p_d, p_b, total_goals_prior = NA_real_,
                                        total_penalty = 0.02, max_goals = 10) {
  if (any(is.na(c(p_a, p_d, p_b)))) {
    return(tibble::tibble(
      lambda_a = NA_real_, lambda_b = NA_real_,
      fitted_p_a = NA_real_, fitted_p_d = NA_real_, fitted_p_b = NA_real_,
      poisson_fit_sse = NA_real_
    ))
  }

  target <- c(p_a = p_a, p_d = p_d, p_b = p_b)
  target <- target / sum(target)
  prior <- ifelse(is.na(total_goals_prior), 2.6, total_goals_prior)

  objective <- function(log_lambda) {
    lambda_a <- exp(log_lambda[[1]])
    lambda_b <- exp(log_lambda[[2]])
    fitted <- result_probs_from_lambdas(lambda_a, lambda_b, max_goals)
    error <- sum((c(fitted$p_a, fitted$p_d, fitted$p_b) - target)^2)
    penalty <- total_penalty * ((lambda_a + lambda_b - prior) / prior)^2
    error + penalty
  }

  start_share <- c(p_a + 0.5 * p_d, p_b + 0.5 * p_d)
  start_share <- pmax(start_share / sum(start_share), 0.05)
  start_total <- prior
  start <- log(start_total * start_share)

  opt <- stats::optim(
    par = start,
    fn = objective,
    method = "L-BFGS-B",
    lower = log(c(0.05, 0.05)),
    upper = log(c(6, 6))
  )

  lambda_a <- exp(opt$par[[1]])
  lambda_b <- exp(opt$par[[2]])
  fitted <- result_probs_from_lambdas(lambda_a, lambda_b, max_goals)

  tibble::tibble(
    lambda_a = lambda_a,
    lambda_b = lambda_b,
    fitted_p_a = fitted$p_a,
    fitted_p_d = fitted$p_d,
    fitted_p_b = fitted$p_b,
    poisson_fit_sse = opt$value
  )
}

score_distribution <- function(lambda_a, lambda_b, max_goals = 10) {
  if (any(is.na(c(lambda_a, lambda_b)))) {
    return(tibble::tibble())
  }

  goals <- 0:max_goals
  tidyr::expand_grid(score_a = goals, score_b = goals) |>
    dplyr::mutate(
      score_probability = stats::dpois(score_a, lambda_a) *
        stats::dpois(score_b, lambda_b),
      result = result_from_score(score_a, score_b)
    )
}

adjusted_score_distribution <- function(lambda_a, lambda_b, rho = 0,
                                        tail_strength = 0,
                                        favorite_side = NA_character_,
                                        negative_binomial_size = NA_real_,
                                        max_goals = 10) {
  if (
    !is.na(tail_strength) && tail_strength > 0 &&
      favorite_side %in% c("A", "B") &&
      !is.na(negative_binomial_size)
  ) {
    goals <- 0:max_goals
    dist <- tidyr::expand_grid(score_a = goals, score_b = goals)

    if (favorite_side == "A") {
      probs_a <- stats::dnbinom(goals, mu = lambda_a, size = negative_binomial_size)
      probs_b <- stats::dpois(goals, lambda_b)
    } else {
      probs_a <- stats::dpois(goals, lambda_a)
      probs_b <- stats::dnbinom(goals, mu = lambda_b, size = negative_binomial_size)
    }

    dist <- dist |>
      dplyr::mutate(
        score_probability = outer(probs_a, probs_b)[
          cbind(score_a + 1, score_b + 1)
        ],
        result = result_from_score(score_a, score_b)
      )
  } else {
    dist <- score_distribution(lambda_a, lambda_b, max_goals)
  }

  if (nrow(dist) == 0) {
    return(dist)
  }

  dist <- dist |>
    dplyr::mutate(adjustment = 1)

  if (!is.na(rho) && rho != 0) {
    dist <- dist |>
      dplyr::mutate(
        dc_adjustment = dplyr::case_when(
          score_a == 0 & score_b == 0 ~ 1 - lambda_a * lambda_b * rho,
          score_a == 0 & score_b == 1 ~ 1 + lambda_a * rho,
          score_a == 1 & score_b == 0 ~ 1 + lambda_b * rho,
          score_a == 1 & score_b == 1 ~ 1 - rho,
          TRUE ~ 1
        ),
        adjustment = adjustment * pmax(dc_adjustment, 0.01)
      )
  }

  dist |>
    dplyr::mutate(score_probability = score_probability * adjustment) |>
    dplyr::mutate(score_probability = score_probability / sum(score_probability)) |>
    dplyr::select(score_a, score_b, score_probability, result)
}

result_probs_from_distribution <- function(dist) {
  if (nrow(dist) == 0) {
    return(tibble::tibble(p_a = NA_real_, p_d = NA_real_, p_b = NA_real_))
  }

  dist |>
    dplyr::summarise(
      p_a = sum(score_probability[result == "A"], na.rm = TRUE),
      p_d = sum(score_probability[result == "D"], na.rm = TRUE),
      p_b = sum(score_probability[result == "B"], na.rm = TRUE)
    ) |>
    normalize_probability_rows(c("p_a", "p_d", "p_b"))
}

top_score_from_lambdas <- function(lambda_a, lambda_b, max_goals = 10) {
  dist <- score_distribution(lambda_a, lambda_b, max_goals)
  if (nrow(dist) == 0) {
    return(tibble::tibble(
      pred_score_a = NA_integer_,
      pred_score_b = NA_integer_,
      pred_score = NA_character_,
      pred_score_probability = NA_real_
    ))
  }

  dist |>
    dplyr::slice_max(score_probability, n = 1, with_ties = FALSE) |>
    dplyr::transmute(
      pred_score_a = score_a,
      pred_score_b = score_b,
      pred_score = paste0(score_a, "-", score_b),
      pred_score_probability = score_probability
    )
}

top_score_from_distribution <- function(dist) {
  if (nrow(dist) == 0) {
    return(tibble::tibble(
      pred_score_a = NA_integer_,
      pred_score_b = NA_integer_,
      pred_score = NA_character_,
      pred_score_probability = NA_real_
    ))
  }

  dist |>
    dplyr::slice_max(score_probability, n = 1, with_ties = FALSE) |>
    dplyr::transmute(
      pred_score_a = score_a,
      pred_score_b = score_b,
      pred_score = paste0(score_a, "-", score_b),
      pred_score_probability = score_probability
    )
}

observed_score_probability <- function(lambda_a, lambda_b, score_a, score_b) {
  if (any(is.na(c(lambda_a, lambda_b, score_a, score_b)))) {
    return(NA_real_)
  }

  stats::dpois(score_a, lambda_a) * stats::dpois(score_b, lambda_b)
}

observed_score_probability_from_distribution <- function(dist, score_a, score_b) {
  if (nrow(dist) == 0 || any(is.na(c(score_a, score_b)))) {
    return(NA_real_)
  }

  value <- dist |>
    dplyr::filter(.data$score_a == !!score_a, .data$score_b == !!score_b) |>
    dplyr::pull(score_probability)

  if (length(value) == 0) NA_real_ else value[[1]]
}

result_log_loss <- function(actual, p_a, p_d, p_b) {
  p <- dplyr::case_when(
    actual == "A" ~ p_a,
    actual == "D" ~ p_d,
    actual == "B" ~ p_b,
    TRUE ~ NA_real_
  )
  -log(safe_probability(p))
}

result_brier <- function(actual, p_a, p_d, p_b) {
  ifelse(
    is.na(actual),
    NA_real_,
    (p_a - (actual == "A"))^2 +
      (p_d - (actual == "D"))^2 +
      (p_b - (actual == "B"))^2
  )
}

aggregate_odds <- function(odds) {
  odds_complete <- odds |>
    dplyr::filter(
      market == "1x2",
      !is.na(odds_team_a),
      !is.na(odds_draw),
      !is.na(odds_team_b),
      odds_team_a > 1,
      odds_draw > 1,
      odds_team_b > 1
    )

  odds_2022 <- odds_complete |>
    dplyr::filter(year == 2022, bookmaker == "Market average") |>
    dplyr::mutate(
      odds_aggregate_method = "football_data_market_average",
      n_bookmakers = 1L
    )

  odds_other <- odds_complete |>
    dplyr::filter(year != 2022) |>
    dplyr::group_by(year, match_id, date, team_a, team_b) |>
    dplyr::summarise(
      odds_team_a = stats::median(odds_team_a, na.rm = TRUE),
      odds_draw = stats::median(odds_draw, na.rm = TRUE),
      odds_team_b = stats::median(odds_team_b, na.rm = TRUE),
      n_bookmakers = dplyr::n_distinct(bookmaker),
      odds_aggregate_method = "median_complete_bookmakers",
      source = paste(sort(unique(source)), collapse = "|"),
      .groups = "drop"
    )

  dplyr::bind_rows(
    odds_2022 |>
      dplyr::select(
        year, match_id, date, team_a, team_b, odds_team_a, odds_draw,
        odds_team_b, n_bookmakers, odds_aggregate_method, source
      ),
    odds_other
  ) |>
    dplyr::mutate(
      implied_raw_p_a = 1 / odds_team_a,
      implied_raw_p_d = 1 / odds_draw,
      implied_raw_p_b = 1 / odds_team_b,
      odds_overround = implied_raw_p_a + implied_raw_p_d + implied_raw_p_b,
      market_p_a = implied_raw_p_a / odds_overround,
      market_p_d = implied_raw_p_d / odds_overround,
      market_p_b = implied_raw_p_b / odds_overround,
      market_pred_result = c("A", "D", "B")[
        max.col(cbind(market_p_a, market_p_d, market_p_b), ties.method = "first")
      ]
    ) |>
    dplyr::select(
      year, match_id, date, team_a, team_b, source, odds_aggregate_method,
      n_bookmakers, odds_team_a, odds_draw, odds_team_b, odds_overround,
      market_p_a, market_p_d, market_p_b, market_pred_result
    )
}

team_recent_form <- function(team, match_date, results, n_recent = 10) {
  history <- results |>
    dplyr::filter(date < match_date, home_team == team | away_team == team) |>
    dplyr::mutate(
      is_home = home_team == team,
      goals_for = dplyr::if_else(is_home, home_score, away_score),
      goals_against = dplyr::if_else(is_home, away_score, home_score),
      points = dplyr::case_when(
        goals_for > goals_against ~ 3,
        goals_for == goals_against ~ 1,
        goals_for < goals_against ~ 0,
        TRUE ~ NA_real_
      )
    ) |>
    dplyr::arrange(dplyr::desc(date)) |>
    dplyr::slice_head(n = n_recent)

  tibble::tibble(
    recent_matches = nrow(history),
    recent_points_per_match = mean(history$points, na.rm = TRUE),
    recent_goals_for = mean(history$goals_for, na.rm = TRUE),
    recent_goals_against = mean(history$goals_against, na.rm = TRUE)
  ) |>
    dplyr::mutate(
      dplyr::across(
        dplyr::everything(),
        ~ dplyr::if_else(is.nan(.x), NA_real_, as.numeric(.x))
      )
    )
}

fit_rating_models <- function(international_results, elo_history) {
  results_norm <- international_results |>
    dplyr::mutate(
      date = lubridate::ymd(date),
      home_key = normalize_team(home_team),
      away_key = normalize_team(away_team),
      total_goals = home_score + away_score,
      is_draw = home_score == away_score,
      home_win_non_draw = home_score > away_score
    )

  elo_norm <- elo_history |>
    dplyr::mutate(
      date = lubridate::ymd(date),
      home_key = normalize_team(home_team),
      away_key = normalize_team(away_team)
    ) |>
    dplyr::select(date, home_key, away_key, home_elo_pre, away_elo_pre) |>
    dplyr::distinct(date, home_key, away_key, .keep_all = TRUE)

  train <- results_norm |>
    dplyr::inner_join(elo_norm, by = c("date", "home_key", "away_key")) |>
    dplyr::mutate(
      elo_diff = home_elo_pre - away_elo_pre,
      abs_elo_diff = abs(elo_diff),
      neutral = as.logical(neutral)
    ) |>
    dplyr::filter(!is.na(total_goals), !is.na(elo_diff))

  if (nrow(train) < 100) {
    return(list(
      draw_model = NULL,
      win_model = NULL,
      total_model = NULL,
      train_rows = nrow(train),
      fallback_draw_rate = 0.25,
      fallback_total_goals = 2.6
    ))
  }

  non_draw <- train |>
    dplyr::filter(!is_draw)

  list(
    draw_model = stats::glm(
      is_draw ~ abs_elo_diff + neutral,
      data = train,
      family = stats::binomial()
    ),
    win_model = stats::glm(
      home_win_non_draw ~ elo_diff + neutral,
      data = non_draw,
      family = stats::binomial()
    ),
    total_model = stats::glm(
      total_goals ~ abs_elo_diff + neutral,
      data = train,
      family = stats::poisson()
    ),
    train_rows = nrow(train),
    fallback_draw_rate = mean(train$is_draw, na.rm = TRUE),
    fallback_total_goals = mean(train$total_goals, na.rm = TRUE)
  )
}

fit_rating_models_v2 <- function(international_results, elo_history) {
  results_norm <- international_results |>
    dplyr::mutate(
      date = lubridate::ymd(date),
      home_key = normalize_team(home_team),
      away_key = normalize_team(away_team),
      total_goals = home_score + away_score,
      is_draw = home_score == away_score,
      home_win_non_draw = home_score > away_score
    )

  elo_norm <- elo_history |>
    dplyr::mutate(
      date = lubridate::ymd(date),
      home_key = normalize_team(home_team),
      away_key = normalize_team(away_team)
    ) |>
    dplyr::select(date, home_key, away_key, home_elo_pre, away_elo_pre) |>
    dplyr::distinct(date, home_key, away_key, .keep_all = TRUE)

  train <- results_norm |>
    dplyr::inner_join(elo_norm, by = c("date", "home_key", "away_key")) |>
    dplyr::mutate(
      elo_diff = home_elo_pre - away_elo_pre,
      abs_elo_diff = abs(elo_diff),
      abs_elo_diff_scaled = abs_elo_diff / 100,
      mismatch_300 = pmax(abs_elo_diff - 300, 0) / 100,
      neutral = as.logical(neutral)
    ) |>
    dplyr::filter(!is.na(total_goals), !is.na(elo_diff))

  if (nrow(train) < 100) {
    return(list(
      draw_model = NULL,
      win_model = NULL,
      total_model = NULL,
      train_rows = nrow(train),
      fallback_draw_rate = 0.25,
      fallback_total_goals = 2.6
    ))
  }

  non_draw <- train |>
    dplyr::filter(!is_draw)

  list(
    draw_model = stats::glm(
      is_draw ~ abs_elo_diff_scaled + mismatch_300 + neutral,
      data = train,
      family = stats::binomial()
    ),
    win_model = stats::glm(
      home_win_non_draw ~ elo_diff + neutral,
      data = non_draw,
      family = stats::binomial()
    ),
    total_model = stats::glm(
      total_goals ~ abs_elo_diff_scaled + mismatch_300 + neutral,
      data = train,
      family = stats::poisson()
    ),
    train_rows = nrow(train),
    fallback_draw_rate = mean(train$is_draw, na.rm = TRUE),
    fallback_total_goals = mean(train$total_goals, na.rm = TRUE)
  )
}

predict_rating_result_probs <- function(elo_diff, neutral, models) {
  if (is.na(elo_diff) || is.null(models$draw_model) || is.null(models$win_model)) {
    p_d <- models$fallback_draw_rate %||% 0.25
    p_a <- (1 - p_d) * 0.5
    p_b <- (1 - p_d) * 0.5
    return(tibble::tibble(rating_p_a = p_a, rating_p_d = p_d, rating_p_b = p_b))
  }

  new_data <- tibble::tibble(
    elo_diff = elo_diff,
    abs_elo_diff = abs(elo_diff),
    abs_elo_diff_scaled = abs(elo_diff) / 100,
    mismatch_300 = pmax(abs(elo_diff) - 300, 0) / 100,
    neutral = as.logical(neutral)
  )

  p_d <- stats::predict(models$draw_model, newdata = new_data, type = "response")
  p_a_cond <- stats::predict(models$win_model, newdata = new_data, type = "response")

  tibble::tibble(
    rating_p_a = (1 - p_d) * p_a_cond,
    rating_p_d = p_d,
    rating_p_b = (1 - p_d) * (1 - p_a_cond)
  )
}

predict_total_goals <- function(elo_diff, neutral, models) {
  if (is.na(elo_diff) || is.null(models$total_model)) {
    return(models$fallback_total_goals %||% 2.6)
  }

  new_data <- tibble::tibble(
    elo_diff = elo_diff,
    abs_elo_diff = abs(elo_diff),
    abs_elo_diff_scaled = abs(elo_diff) / 100,
    mismatch_300 = pmax(abs(elo_diff) - 300, 0) / 100,
    neutral = as.logical(neutral)
  )

  as.numeric(stats::predict(models$total_model, newdata = new_data, type = "response"))
}

predict_total_goals_v2 <- function(elo_diff, neutral, recent_goals_for_a,
                                   recent_goals_for_b, recent_goals_against_a,
                                   recent_goals_against_b, models) {
  base_total <- predict_total_goals(elo_diff, neutral, models)
  abs_diff <- abs(elo_diff)

  recent_attack <- mean(c(recent_goals_for_a, recent_goals_for_b), na.rm = TRUE)
  recent_defense_leak <- mean(c(recent_goals_against_a, recent_goals_against_b), na.rm = TRUE)
  recent_goal_signal <- mean(c(recent_attack, recent_defense_leak), na.rm = TRUE)
  recent_adjustment <- ifelse(
    is.nan(recent_goal_signal),
    0,
    0.18 * (recent_goal_signal - 1.25)
  )

  mismatch_adjustment <- dplyr::case_when(
    is.na(abs_diff) ~ 0,
    abs_diff >= 500 ~ 0.55,
    abs_diff >= 350 ~ 0.35,
    abs_diff >= 220 ~ 0.18,
    TRUE ~ 0
  )

  pmin(pmax(base_total + recent_adjustment + mismatch_adjustment, 1.6), 4.8)
}

dynamic_market_weight <- function(has_market, n_bookmakers, odds_overround, abs_elo_diff) {
  if (!has_market) {
    return(0)
  }

  weight <- 0.78
  if (!is.na(n_bookmakers) && n_bookmakers >= 5) {
    weight <- weight + 0.06
  }
  if (!is.na(odds_overround) && odds_overround <= 1.07) {
    weight <- weight + 0.03
  }
  if (!is.na(abs_elo_diff) && abs_elo_diff >= 350) {
    weight <- weight - 0.05
  }

  pmin(pmax(weight, 0.55), 0.90)
}

blend_result_probs <- function(market_p_a, market_p_d, market_p_b,
                               rating_p_a, rating_p_d, rating_p_b,
                               market_weight = 0.80) {
  has_market <- !any(is.na(c(market_p_a, market_p_d, market_p_b)))
  weight <- ifelse(has_market, market_weight, 0)
  market <- if (has_market) {
    c(market_p_a, market_p_d, market_p_b)
  } else {
    c(0, 0, 0)
  }

  probs <- c(
    p_a = unname(weight * market[[1]] + (1 - weight) * rating_p_a),
    p_d = unname(weight * market[[2]] + (1 - weight) * rating_p_d),
    p_b = unname(weight * market[[3]] + (1 - weight) * rating_p_b)
  )
  probs <- probs / sum(probs)

  tibble::tibble(
    hybrid_p_a = probs[["p_a"]],
    hybrid_p_d = probs[["p_d"]],
    hybrid_p_b = probs[["p_b"]]
  )
}

v2_adjustment_parameters <- function(elo_diff, pred_p_a, pred_p_d, pred_p_b) {
  abs_diff <- abs(elo_diff)
  max_result_prob <- max(c(pred_p_a, pred_p_d, pred_p_b), na.rm = TRUE)
  favorite_side <- dplyr::case_when(
    pred_p_a >= pred_p_b & pred_p_a >= pred_p_d ~ "A",
    pred_p_b > pred_p_a & pred_p_b >= pred_p_d ~ "B",
    TRUE ~ NA_character_
  )

  rho <- dplyr::case_when(
    is.na(abs_diff) ~ -0.04,
    abs_diff <= 120 ~ -0.10,
    abs_diff <= 220 ~ -0.06,
    TRUE ~ -0.02
  )

  tail_strength <- dplyr::case_when(
    is.na(abs_diff) ~ 0,
    max_result_prob < 0.62 ~ 0,
    abs_diff >= 500 ~ 0.85,
    abs_diff >= 350 ~ 0.55,
    abs_diff >= 220 ~ 0.30,
    TRUE ~ 0
  )

  negative_binomial_size <- dplyr::case_when(
    tail_strength <= 0 ~ NA_real_,
    tail_strength >= 0.80 ~ 2.2,
    tail_strength >= 0.50 ~ 3.2,
    tail_strength >= 0.30 ~ 5.0,
    TRUE ~ 7.0
  )

  tibble::tibble(
    dixon_coles_rho = rho,
    tail_strength = tail_strength,
    negative_binomial_size = negative_binomial_size,
    favorite_side = favorite_side
  )
}

evaluate_predictions <- function(predictions) {
  predictions |>
    dplyr::filter(!is.na(actual_result)) |>
    dplyr::mutate(
      result_log_loss = result_log_loss(actual_result, pred_p_a, pred_p_d, pred_p_b),
      result_brier = result_brier(actual_result, pred_p_a, pred_p_d, pred_p_b),
      result_accuracy = pred_result == actual_result,
      score_log_loss = -log(safe_probability(observed_score_probability)),
      goals_a_absolute_error = abs(lambda_a - score_a),
      goals_b_absolute_error = abs(lambda_b - score_b),
      total_goals_absolute_error = abs(lambda_a + lambda_b - score_a - score_b)
    ) |>
    dplyr::group_by(model, year) |>
    dplyr::summarise(
      evaluated_matches = dplyr::n(),
      result_accuracy = mean(result_accuracy, na.rm = TRUE),
      result_log_loss = mean(result_log_loss, na.rm = TRUE),
      result_brier = mean(result_brier, na.rm = TRUE),
      score_log_loss = mean(score_log_loss, na.rm = TRUE),
      goals_a_mae = mean(goals_a_absolute_error, na.rm = TRUE),
      goals_b_mae = mean(goals_b_absolute_error, na.rm = TRUE),
      total_goals_mae = mean(total_goals_absolute_error, na.rm = TRUE),
      .groups = "drop"
    )
}
