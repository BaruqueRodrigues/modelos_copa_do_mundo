source("R/01_coleta/lib_coleta.R")

ensure_dirs(c(required_dirs(), "data/interim/teams"))

fifa_path <- project_path("data/interim/rankings/fifa_rankings_2022_onwards.csv")
elo_raw_path <- project_path("data/raw/elo/world_football_elo_external_current.tsv")
elo_teams_path <- project_path("data/raw/elo/world_football_elo_external_teams.tsv")
ratings_long_path <- project_path("data/interim/teams/team_external_ratings_long.csv")
overall_path <- project_path("data/interim/teams/team_overall_external_consolidated.csv")

elo_url <- "https://www.eloratings.net/World.tsv"
elo_teams_url <- "https://eloratings.net/en.teams.tsv"

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

scale_40_99 <- function(x) {
  if (all(is.na(x)) || length(unique(stats::na.omit(x))) <= 1) {
    return(rep(NA_real_, length(x)))
  }

  40 + 59 * dplyr::percent_rank(x)
}

download_external_file <- function(url, path) {
  response <- httr2::request(url) |>
    httr2::req_user_agent("modelos_copa_do_mundo/0.1 data collection") |>
    httr2::req_perform()

  body <- httr2::resp_body_raw(response)
  writeBin(body, path)

  append_access_log(tibble::tibble(
    url = url,
    accessed_at = now_iso(),
    local_path = fs::path_rel(path, start = project_path()),
    http_status = httr2::resp_status(response),
    bytes = as.numeric(fs::file_size(path))
  ))

  invisible(path)
}

parse_elo_team_names <- function(path) {
  lines <- readr::read_lines(path)

  purrr::map_dfr(lines, function(line) {
    parts <- stringr::str_split(line, "\t", simplify = FALSE)[[1]]
    if (length(parts) < 2 || stringr::str_detect(parts[[1]], "_loc$")) {
      return(tibble::tibble())
    }

    tibble::tibble(
      elo_code = parts[[1]],
      team = parts[[2]],
      aliases = paste(parts[-1], collapse = "|"),
      team_key = normalize_team(parts[[2]])
    )
  })
}

download_external_file(elo_url, elo_raw_path)
download_external_file(elo_teams_url, elo_teams_path)

fifa <- read_existing_csv(fifa_path) |>
  janitor::clean_names() |>
  dplyr::transmute(
    team,
    team_key = normalize_team(team),
    source = "fifa",
    source_name = "FIFA/Coca-Cola Men's World Ranking",
    reference_date = lubridate::ymd(reference_date),
    rank = as.integer(rank),
    rating_points = as.numeric(points),
    country_code = country_code,
    source_url = source_url
  )

elo_names <- parse_elo_team_names(elo_teams_path)

elo_raw <- readr::read_tsv(
  elo_raw_path,
  col_names = FALSE,
  col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE
) |>
  janitor::clean_names()

elo <- elo_raw |>
  dplyr::transmute(
    rank = as.integer(x1),
    elo_previous_rank = as.integer(x2),
    elo_code = x3,
    rating_points = as.numeric(x4)
  ) |>
  dplyr::left_join(elo_names, by = "elo_code") |>
  dplyr::filter(!is.na(team)) |>
  dplyr::transmute(
    team,
    team_key,
    source = "world_football_elo",
    source_name = "World Football Elo Ratings",
    reference_date = as.Date(Sys.Date()),
    rank,
    rating_points,
    country_code = elo_code,
    source_url = "https://www.eloratings.net/"
  )

ratings_long <- dplyr::bind_rows(fifa, elo) |>
  dplyr::group_by(source) |>
  dplyr::mutate(
    source_overall_40_99 = scale_40_99(rating_points)
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(source, rank)

overall <- ratings_long |>
  dplyr::select(
    team_key, team, source, reference_date, rank, rating_points,
    source_overall_40_99
  ) |>
  tidyr::pivot_wider(
    names_from = source,
    values_from = c(team, reference_date, rank, rating_points, source_overall_40_99),
    values_fn = dplyr::first
  ) |>
  dplyr::mutate(
    team = dplyr::coalesce(team_fifa, team_world_football_elo),
    fifa_points = rating_points_fifa,
    fifa_rank = rank_fifa,
    fifa_overall_40_99 = source_overall_40_99_fifa,
    elo_external_rating = rating_points_world_football_elo,
    elo_external_rank = rank_world_football_elo,
    elo_external_overall_40_99 = source_overall_40_99_world_football_elo,
    external_overall_primary_source = "fifa",
    external_overall_primary_40_99 = fifa_overall_40_99,
    external_overall_consensus_40_99 = rowMeans(
      dplyr::pick(fifa_overall_40_99, elo_external_overall_40_99),
      na.rm = TRUE
    )
  ) |>
  dplyr::mutate(
    external_overall_consensus_40_99 = dplyr::if_else(
      is.nan(external_overall_consensus_40_99),
      NA_real_,
      external_overall_consensus_40_99
    )
  ) |>
  dplyr::select(
    team, team_key,
    external_overall_primary_source,
    external_overall_primary_40_99,
    external_overall_consensus_40_99,
    fifa_rank, fifa_points, fifa_overall_40_99, reference_date_fifa,
    elo_external_rank, elo_external_rating, elo_external_overall_40_99,
    reference_date_world_football_elo
  ) |>
  dplyr::arrange(fifa_rank, elo_external_rank)

readr::write_csv(ratings_long, ratings_long_path)
readr::write_csv(overall, overall_path)
