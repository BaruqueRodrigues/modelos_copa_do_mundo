source("R/01_coleta/lib_coleta.R")

ensure_dirs()

month_number <- function(month) {
  meses <- c(
    jan = 1, january = 1,
    feb = 2, february = 2,
    mar = 3, march = 3,
    apr = 4, april = 4,
    may = 5,
    jun = 6, june = 6,
    jul = 7, july = 7,
    aug = 8, august = 8,
    sep = 9, september = 9,
    oct = 10, october = 10,
    nov = 11, november = 11,
    dec = 12, december = 12
  )

  unname(meses[stringr::str_to_lower(month)])
}

parse_date_line <- function(line, year) {
  padrao <- "^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\s+([A-Za-z]+)\\s+(\\d{1,2})$"
  partes <- stringr::str_match(stringr::str_squish(line), padrao)

  if (is.na(partes[1, 1])) {
    return(as.Date(NA))
  }

  lubridate::make_date(
    year = year,
    month = month_number(partes[1, 3]),
    day = as.integer(partes[1, 4])
  )
}

parse_location <- function(location, year) {
  location <- stringr::str_squish(location)

  city_country <- tibble::tribble(
    ~pattern, ~city, ~country,
    "Mexico City", "Mexico City", "Mexico",
    "Guadalajara", "Guadalajara", "Mexico",
    "Monterrey", "Monterrey", "Mexico",
    "Atlanta", "Atlanta", "United States",
    "Boston", "Boston", "United States",
    "Dallas", "Dallas", "United States",
    "Houston", "Houston", "United States",
    "Kansas City", "Kansas City", "United States",
    "Los Angeles", "Los Angeles", "United States",
    "Miami", "Miami", "United States",
    "New York/New Jersey", "East Rutherford", "United States",
    "Philadelphia", "Philadelphia", "United States",
    "San Francisco Bay Area", "Santa Clara", "United States",
    "Seattle", "Seattle", "United States",
    "Toronto", "Toronto", "Canada",
    "Vancouver", "Vancouver", "Canada"
  )

  if (year == 2026) {
    hit <- city_country |>
      dplyr::filter(stringr::str_detect(location, stringr::fixed(pattern))) |>
      dplyr::slice_head(n = 1)

    if (nrow(hit) == 1) {
      return(tibble::tibble(stadium = NA_character_, city = hit$city, country = hit$country))
    }
  }

  partes <- stringr::str_split(location, ",", n = 2, simplify = TRUE)
  if (ncol(partes) == 2 && nzchar(partes[1, 2])) {
    return(tibble::tibble(
      stadium = stringr::str_squish(partes[1, 1]),
      city = stringr::str_squish(partes[1, 2]),
      country = dplyr::if_else(year == 2022, "Qatar", NA_character_)
    ))
  }

  tibble::tibble(
    stadium = NA_character_,
    city = location,
    country = dplyr::case_when(
      year == 2022 ~ "Qatar",
      TRUE ~ NA_character_
    )
  )
}

parse_match_line <- function(line, current_date, current_stage, year, source_file, match_index) {
  raw <- stringr::str_squish(line)

  if (is.na(current_date) || !stringr::str_detect(raw, "@")) {
    return(NULL)
  }

  com_hora <- stringr::str_match(raw, "^(\\d{1,2}:\\d{2})(?:\\s+UTC[+-]\\d+)?\\s+(.+)$")
  time <- NA_character_
  rest <- raw
  if (!is.na(com_hora[1, 1])) {
    time <- com_hora[1, 2]
    rest <- com_hora[1, 3]
  }

  split_location <- stringr::str_split(rest, "\\s+@\\s+", n = 2, simplify = TRUE)
  left_side <- if (ncol(split_location) == 2) split_location[1, 1] else rest
  location_side <- if (ncol(split_location) == 2) split_location[1, 2] else NA_character_

  placar <- stringr::str_match(left_side, "^(.+?)\\s+(\\d+)-(\\d+)\\s+(.+)$")
  agenda <- stringr::str_match(rest, "^(.+?)\\s+v\\s+(.+?)\\s+@\\s+(.+)$")

  if (!is.na(placar[1, 1]) && !is.na(location_side)) {
    team_a <- placar[1, 2]
    team_b <- placar[1, 5] |>
      stringr::str_remove("^a\\.e\\.t\\.?\\s*") |>
      stringr::str_remove("^\\([^)]*\\)\\s*") |>
      stringr::str_remove("^,\\s*\\d+-\\d+\\s*pen\\.\\s*") |>
      stringr::str_remove("^a\\.e\\.t\\.?\\s*") |>
      stringr::str_remove("^\\([^)]*\\)\\s*") |>
      stringr::str_remove("^,\\s*\\d+-\\d+\\s*pen\\.\\s*")
    score_a <- as.integer(placar[1, 3])
    score_b <- as.integer(placar[1, 4])
    location <- location_side
    score_status <- "final"
  } else if (!is.na(agenda[1, 1])) {
    team_a <- agenda[1, 2]
    team_b <- agenda[1, 3]
    score_a <- NA_integer_
    score_b <- NA_integer_
    location <- agenda[1, 4]
    score_status <- "scheduled"
  } else {
    return(NULL)
  }

  loc <- parse_location(location, year)
  stage <- current_stage %||% NA_character_
  group <- dplyr::if_else(stringr::str_detect(stage, "^Group "), stage, NA_character_)

  tibble::tibble(
    competition = "FIFA World Cup",
    year = year,
    match_id = sprintf("WC%d_%03d", year, match_index),
    date = current_date,
    time = time,
    stage = stage,
    group = group,
    team_a = stringr::str_squish(team_a),
    team_b = stringr::str_squish(team_b),
    score_a = score_a,
    score_b = score_b,
    score_status = score_status,
    stadium = loc$stadium,
    city = loc$city,
    country = loc$country,
    source = "openfootball/worldcup",
    source_file = fs::path_rel(source_file, start = project_path())
  )
}

parse_openfootball_file <- function(path, year) {
  linhas <- readr::read_lines(path, locale = readr::locale(encoding = "UTF-8"))
  current_date <- as.Date(NA)
  current_stage <- NA_character_
  match_index <- 0L
  matches <- list()

  for (linha in linhas) {
    texto <- stringr::str_squish(linha)

    if (!nzchar(texto) || stringr::str_starts(texto, "#") || stringr::str_starts(texto, "=")) {
      next
    }

    if (stringr::str_starts(texto, "▪")) {
      stage_candidate <- stringr::str_remove(texto, "^▪\\s+")
      if (!stringr::str_starts(stage_candidate, "Matchday")) {
        current_stage <- stage_candidate
      }
      next
    }

    parsed_date <- parse_date_line(texto, year)
    if (!is.na(parsed_date)) {
      current_date <- parsed_date
      next
    }

    parsed <- parse_match_line(texto, current_date, current_stage, year, path, match_index + 1L)
    if (!is.null(parsed)) {
      match_index <- match_index + 1L
      matches[[match_index]] <- parsed
    }
  }

  dplyr::bind_rows(matches)
}

arquivos <- tibble::tribble(
  ~year, ~path,
  2022L, project_path("data/raw/matches/openfootball_worldcup_2022.txt"),
  2022L, project_path("data/raw/matches/openfootball_worldcup_2022_finals.txt"),
  2026L, project_path("data/raw/matches/openfootball_worldcup_2026.txt"),
  2026L, project_path("data/raw/matches/openfootball_worldcup_2026_finals.txt")
) |>
  dplyr::filter(fs::file_exists(path))

matches <- arquivos |>
  dplyr::mutate(data = purrr::map2(path, year, parse_openfootball_file)) |>
  dplyr::pull(data) |>
  dplyr::bind_rows() |>
  janitor::clean_names()

readr::write_csv(matches, project_path("data/interim/matches/worldcup_matches_2022_onwards.csv"))

coverage <- matches |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    n_matches = dplyr::n(),
    n_matches_with_score = sum(!is.na(score_a) & !is.na(score_b)),
    coverage_status = coverage_status(dplyr::pick(dplyr::everything())),
    .groups = "drop"
  )

readr::write_csv(coverage, project_path("data/raw/metadata/openfootball_coverage_status.csv"))
