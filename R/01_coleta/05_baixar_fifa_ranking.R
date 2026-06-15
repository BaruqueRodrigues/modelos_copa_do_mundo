source("R/01_coleta/lib_coleta.R")

ensure_dirs()

ranking_url <- "https://api.fifa.com/api/v3/rankings/?gender=1&count=300&language=en"
raw_json_path <- project_path("data/raw/rankings/fifa_rankings_current.json")
ranking_raw <- project_path("data/raw/rankings/fifa_rankings.csv")
ranking_interim <- project_path("data/interim/rankings/fifa_rankings_2022_onwards.csv")

response <- httr2::request(ranking_url) |>
  httr2::req_user_agent("modelos_copa_do_mundo/0.1 data collection") |>
  httr2::req_perform()

json_text <- httr2::resp_body_string(response)
readr::write_file(json_text, raw_json_path)

append_access_log(tibble::tibble(
  url = ranking_url,
  accessed_at = now_iso(),
  local_path = fs::path_rel(raw_json_path, start = project_path()),
  http_status = httr2::resp_status(response),
  bytes = as.numeric(fs::file_size(raw_json_path))
))

payload <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
results <- payload$Results %||% list()

extract_localized_name <- function(x) {
  if (length(x) == 0 || is.null(x[[1]]$Description)) {
    return(NA_character_)
  }

  x[[1]]$Description
}

rankings <- purrr::map_dfr(results, function(row) {
  tibble::tibble(
    reference_date = lubridate::as_date(row$PubDate %||% NA_character_),
    team = extract_localized_name(row$TeamName %||% list()),
    country_code = row$IdCountry %||% NA_character_,
    confederation = row$ConfederationName %||% NA_character_,
    rank = as.integer(row$Rank %||% NA_integer_),
    previous_rank = as.integer(row$PrevRank %||% NA_integer_),
    points = as.numeric(row$DecimalTotalPoints %||% row$TotalPoints %||% NA_real_),
    previous_points = as.numeric(row$DecimalPrevPoints %||% row$PrevPoints %||% NA_real_),
    matches = as.integer(row$Matches %||% NA_integer_),
    source = "FIFA/Coca-Cola Men's World Ranking",
    source_url = "https://inside.fifa.com/fifa-world-ranking/men",
    source_api_url = ranking_url,
    source_schedule_id = row$IdSchedule %||% NA_character_,
    collection_status = "ok",
    collected_at = now_iso()
  )
}) |>
  dplyr::arrange(rank)

readr::write_csv(rankings, ranking_raw)
readr::write_csv(
  dplyr::filter(rankings, reference_date >= lubridate::ymd("2022-01-01")),
  ranking_interim
)

decisoes <- c(
  "# Decisoes de Coleta",
  "",
  "Ultima revisao: 2026-06-15",
  "",
  "## DEC-01: Ranking FIFA",
  "",
  "Status: resolvido para V1.",
  "",
  "Usar a API publica da pagina oficial `https://inside.fifa.com/fifa-world-ranking/men` como fonte primaria de rating externo agnostico. O pipeline coleta o release oficial mais recente em `data/raw/rankings/fifa_rankings_current.json` e salva os pontos oficiais em `data/interim/rankings/fifa_rankings_2022_onwards.csv`.",
  "",
  "## DEC-02: Elo",
  "",
  "Status: resolvido para V1.",
  "",
  "Manter Elo calculado internamente apenas como insumo auxiliar/debug. Para o overall agnostico, usar tambem o rating publicado por terceiro em `https://www.eloratings.net/World.tsv`, consolidado por `R/01_coleta/10_consolidar_overall_terceiros.R`.",
  "",
  "## DEC-03: Copa 2026",
  "",
  "Status: incluir como calendario, resultados parciais ou completo conforme `data/raw/metadata/openfootball_coverage_status.csv` gerado no parse.",
  "",
  "## DEC-04: StatsBomb",
  "",
  "Status: adiado para experimento separado. Nao bloqueia V1 minima.",
  "",
  "## DEC-06 e DEC-07: Odds",
  "",
  "Status: usar apenas fontes abertas e reproduziveis sem compra de API key.",
  "",
  "Para a V1, `football-data.co.uk` fica como fonte primaria aberta para odds historicas quando o arquivo World Cup XLSX estiver disponivel. The Odds API foi descartada para a V1 porque exige API key e pode exigir plano pago. OddsChecker foi adicionado como coleta aberta por scraping auditavel em `R/01_coleta/07b_baixar_odds_oddschecker.R`."
)

readr::write_lines(decisoes, project_path("data/raw/metadata/decisoes_coleta.md"))
