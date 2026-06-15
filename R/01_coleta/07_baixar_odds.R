source("R/01_coleta/lib_coleta.R")

ensure_dirs()

odds_schema <- function() {
  tibble::tibble(
    year = integer(),
    match_id = character(),
    date = as.Date(character()),
    team_a = character(),
    team_b = character(),
    bookmaker = character(),
    market = character(),
    odds_team_a = double(),
    odds_draw = double(),
    odds_team_b = double(),
    odds_type = character(),
    collected_at = character(),
    source = character(),
    source_url = character(),
    source_sheet = character(),
    source_event_id = character()
  )
}

normalize_col <- function(cols, candidates) {
  hit <- intersect(candidates, cols)
  if (length(hit) == 0) NA_character_ else hit[[1]]
}

parse_date_value <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  if (inherits(x, "POSIXt")) {
    return(as.Date(x))
  }
  suppressWarnings(lubridate::dmy(as.character(x)))
}

read_football_data_odds <- function() {
  url <- "https://www.football-data.co.uk/WorldCup2026.xlsx"
  destino <- project_path("data/raw/odds/football_data_worldcup.xlsx")

  entrada <- download_file(url, destino) |>
    dplyr::mutate(dataset = "football_data_worldcup", coverage_status = "xlsx_snapshot")

  append_access_log(entrada)

  parse_sheet <- function(sheet) {
    dados <- readxl::read_excel(destino, sheet = sheet) |>
      janitor::clean_names()

    cols <- names(dados)
    date_col <- normalize_col(cols, c("date", "match_date"))
    home_team_col <- normalize_col(cols, c("home_team", "hometeam", "home"))
    away_team_col <- normalize_col(cols, c("away_team", "awayteam", "away"))

    if (any(is.na(c(date_col, home_team_col, away_team_col)))) {
      return(odds_schema())
    }

    odds_sets <- tibble::tribble(
      ~bookmaker, ~odds_type, ~home_col, ~draw_col, ~away_col,
      "Bet365", "opening", "b365_h", "b365_d", "b365_a",
      "Bet365", "closing", "b365_ch", "b365_cd", "b365_ca",
      "Betfair Exchange", "unknown", "betfair_exch_h", "betfair_exch_d", "betfair_exch_a",
      "Pinnacle", "unknown", "pinny_h", "pinny_d", "pinny_a",
      "Market maximum", "maximum", "h_max", "d_max", "a_max",
      "Market maximum", "closing_maximum", "h_cmax", "d_cmax", "a_cmax",
      "Market average", "average", "h_avg", "d_avg", "a_avg",
      "Market average", "closing_average", "h_cavg", "d_cavg", "a_cavg"
    ) |>
      dplyr::filter(home_col %in% cols, draw_col %in% cols, away_col %in% cols)

    if (nrow(odds_sets) == 0) {
      return(odds_schema())
    }

    odds_sets |>
      purrr::pmap_dfr(function(bookmaker, odds_type, home_col, draw_col, away_col) {
        dados |>
          dplyr::transmute(
            year = lubridate::year(parse_date_value(.data[[date_col]])),
            match_id = NA_character_,
            date = parse_date_value(.data[[date_col]]),
            team_a = as.character(.data[[home_team_col]]),
            team_b = as.character(.data[[away_team_col]]),
            bookmaker = bookmaker,
            market = "1x2",
            odds_team_a = suppressWarnings(as.numeric(.data[[home_col]])),
            odds_draw = suppressWarnings(as.numeric(.data[[draw_col]])),
            odds_team_b = suppressWarnings(as.numeric(.data[[away_col]])),
            odds_type = odds_type,
            collected_at = now_iso(),
            source = "football-data.co.uk",
            source_url = url,
            source_sheet = sheet,
            source_event_id = NA_character_
          )
      }) |>
      dplyr::filter(!is.na(team_a), !is.na(team_b)) |>
      dplyr::filter(!is.na(odds_team_a) | !is.na(odds_draw) | !is.na(odds_team_b))
  }

  sheets <- readxl::excel_sheets(destino) |>
    purrr::keep(\(sheet) stringr::str_detect(sheet, "^WorldCup\\d{4}$")) |>
    purrr::keep(\(sheet) as.integer(stringr::str_extract(sheet, "\\d{4}")) >= 2022)

  sheets |>
    purrr::map_dfr(parse_sheet) |>
    janitor::clean_names()
}

get_the_odds_api_key <- function() {
  key <- Sys.getenv("THE_ODDS_API_KEY")
  if (!nzchar(key)) {
    key <- Sys.getenv("ODDS_API_KEY")
  }
  key
}

write_the_odds_api_status <- function(status, message, path = project_path("data/raw/metadata/the_odds_api_status.csv")) {
  status_row <- tibble::tibble(
    checked_at = now_iso(),
    status = status,
    message = message,
    sport_key = "soccer_fifa_world_cup",
    market = "h2h",
    regions = "us,uk,eu"
  )

  antigo <- read_existing_csv(path)
  if (nrow(antigo) > 0 && "checked_at" %in% names(antigo)) {
    antigo <- antigo |>
      dplyr::mutate(checked_at = as.character(checked_at))
  }

  readr::write_csv(dplyr::bind_rows(antigo, status_row), path)
  invisible(status_row)
}

fetch_the_odds_api_odds <- function(api_key) {
  source_url <- "https://api.the-odds-api.com/v4/sports/soccer_fifa_world_cup/odds"

  resposta <- httr2::request(source_url) |>
    httr2::req_user_agent("modelos_copa_do_mundo/0.1 data collection") |>
    httr2::req_url_query(
      apiKey = api_key,
      regions = "us,uk,eu",
      markets = "h2h",
      oddsFormat = "decimal",
      dateFormat = "iso"
    ) |>
    httr2::req_perform()

  raw_json <- httr2::resp_body_string(resposta)
  collected_at <- now_iso()
  raw_path <- project_path(
    "data/raw/odds",
    paste0("the_odds_api_worldcup_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json")
  )
  readr::write_file(raw_json, raw_path)

  append_access_log(tibble::tibble(
    url = paste0(source_url, "?regions=us,uk,eu&markets=h2h&oddsFormat=decimal&dateFormat=iso"),
    accessed_at = collected_at,
    local_path = fs::path_rel(raw_path, start = project_path()),
    http_status = httr2::resp_status(resposta),
    bytes = as.numeric(fs::file_size(raw_path)),
    dataset = "the_odds_api_worldcup",
    coverage_status = "snapshot"
  ))

  write_the_odds_api_status("ok", paste0("Snapshot salvo em ", fs::path_rel(raw_path, start = project_path())))

  list(
    raw_path = raw_path,
    collected_at = collected_at,
    source_url = source_url,
    payload = jsonlite::fromJSON(raw_json, simplifyVector = FALSE)
  )
}

extract_outcome_price <- function(outcomes, outcome_name) {
  hit <- purrr::keep(outcomes, \(outcome) identical(outcome$name, outcome_name))
  if (length(hit) == 0) {
    return(NA_real_)
  }

  as.numeric(hit[[1]]$price)
}

standardize_the_odds_api_payload <- function(snapshot) {
  events <- snapshot$payload

  if (length(events) == 0) {
    return(odds_schema())
  }

  purrr::map_dfr(events, function(event) {
    if (length(event$bookmakers %||% list()) == 0) {
      return(odds_schema())
    }

    event_date <- as.Date(lubridate::ymd_hms(event$commence_time, quiet = TRUE))

    purrr::map_dfr(event$bookmakers, function(bookmaker) {
      h2h <- purrr::keep(bookmaker$markets %||% list(), \(market) identical(market$key, "h2h"))
      if (length(h2h) == 0) {
        return(odds_schema())
      }

      outcomes <- h2h[[1]]$outcomes
      tibble::tibble(
        year = lubridate::year(event_date),
        match_id = NA_character_,
        date = event_date,
        team_a = event$home_team,
        team_b = event$away_team,
        bookmaker = bookmaker$title,
        market = "1x2",
        odds_team_a = extract_outcome_price(outcomes, event$home_team),
        odds_draw = extract_outcome_price(outcomes, "Draw"),
        odds_team_b = extract_outcome_price(outcomes, event$away_team),
        odds_type = "snapshot",
        collected_at = snapshot$collected_at,
        source = "The Odds API",
        source_url = snapshot$source_url,
        source_sheet = NA_character_,
        source_event_id = event$id
      )
    })
  }) |>
    dplyr::filter(year >= 2022) |>
    dplyr::filter(!is.na(odds_team_a) | !is.na(odds_draw) | !is.na(odds_team_b))
}

read_the_odds_api_odds <- function() {
  output_path <- project_path("data/interim/odds/the_odds_api_worldcup_odds.csv")

  write_the_odds_api_status(
    "skipped_no_open_keyless_api",
    "The Odds API foi descartada na V1 porque exige API key; o projeto deve usar apenas dados abertos sem compra de chave."
  )

  empty <- odds_schema()
  readr::write_csv(empty, output_path)
  empty
}

football_data_odds <- read_football_data_odds()
the_odds_api_odds <- read_the_odds_api_odds()

odds <- dplyr::bind_rows(football_data_odds, the_odds_api_odds) |>
  dplyr::arrange(year, date, team_a, team_b, source, bookmaker, odds_type)

readr::write_csv(football_data_odds, project_path("data/interim/odds/football_data_worldcup_odds.csv"))
readr::write_csv(odds, project_path("data/interim/odds/worldcup_odds_2022_onwards.csv"))
