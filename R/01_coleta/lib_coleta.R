project_path <- function(...) {
  if (requireNamespace("here", quietly = TRUE)) {
    return(here::here(...))
  }

  file.path(getwd(), ...)
}

required_dirs <- function() {
  c(
    "data/raw/matches",
    "data/raw/rankings",
    "data/raw/elo",
    "data/raw/odds",
    "data/raw/statsbomb",
    "data/raw/metadata",
    "data/interim/matches",
    "data/interim/rankings",
    "data/interim/elo",
    "data/interim/odds",
    "data/processed",
    "R/01_coleta",
    "reports"
  )
}

ensure_dirs <- function(paths = required_dirs()) {
  paths |>
    purrr::map(project_path) |>
    purrr::walk(fs::dir_create)

  invisible(paths)
}

now_iso <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
}

read_existing_csv <- function(path, cols = NULL) {
  if (!fs::file_exists(path)) {
    return(tibble::tibble())
  }

  readr::read_csv(path, col_types = cols %||% readr::cols(), show_col_types = FALSE)
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

download_file <- function(url, destino) {
  fs::dir_create(fs::path_dir(destino))

  resposta <- httr2::request(url) |>
    httr2::req_user_agent("modelos_copa_do_mundo/0.1 data collection") |>
    httr2::req_perform()

  corpo <- httr2::resp_body_raw(resposta)
  writeBin(corpo, destino)

  tibble::tibble(
    url = url,
    accessed_at = now_iso(),
    local_path = fs::path_rel(destino, start = project_path()),
    http_status = httr2::resp_status(resposta),
    bytes = as.numeric(fs::file_size(destino))
  )
}

append_access_log <- function(entries, log_path = project_path("data/raw/metadata/data_access_log.csv")) {
  fs::dir_create(fs::path_dir(log_path))

  antigo <- read_existing_csv(log_path) |>
    dplyr::mutate(
      accessed_at = as.character(accessed_at),
      bytes = suppressWarnings(as.numeric(bytes))
    )
  entries <- entries |>
    dplyr::mutate(
      accessed_at = as.character(accessed_at),
      bytes = suppressWarnings(as.numeric(bytes))
    )

  novo <- dplyr::bind_rows(antigo, entries) |>
    dplyr::distinct(url, local_path, accessed_at, .keep_all = TRUE)

  readr::write_csv(novo, log_path)
  invisible(novo)
}

write_source_inventory <- function(path = project_path("data/raw/metadata/fontes_dados.csv")) {
  ensure_dirs()

  fontes <- tibble::tribble(
    ~fonte, ~url, ~tipo_dado, ~formato, ~cobertura_temporal, ~licenca, ~status, ~observacoes,
    "openfootball/worldcup", "https://github.com/openfootball/worldcup", "jogos, grupos, fases, estadios e resultados", "Football.TXT e CSV", "Copas FIFA masculinas; V1 usa 2022 e 2026", "open data; ver LICENSE.md do repositorio", "primaria", "Fonte primaria para calendario e resultados da Copa.",
    "martj42/international_results", "https://github.com/martj42/international_results", "historico de partidas internacionais", "CSV", "1872 em diante; V1 filtra desde 2018-01-01", "ver licenca/termos do repositorio", "auxiliar", "Usado para forma recente e features pre-jogo.",
    "StatsBomb Open Data", "https://github.com/statsbomb/open-data", "eventos, lineups e dados 360", "JSON", "Inclui competicoes abertas; Copa 2022 a validar", "StatsBomb Open Data terms", "opcional", "Nao bloqueia V1 minima.",
    "FIFA Ranking", "https://inside.fifa.com/fifa-world-ranking/men", "ranking e pontos oficiais de selecoes", "API JSON publica da FIFA", "Rankings periodicos; V1 usa release oficial mais recente coletado", "termos FIFA", "auxiliar", "Fonte primaria para overall externo agnostico.",
    "World Football Elo Ratings", "https://www.eloratings.net/", "Elo publicado por terceiro para selecoes", "TSV publico", "Rating atual e historico no site; V1 usa World.tsv atual", "termos do site a validar", "auxiliar", "Fonte secundaria para overall externo e analise de robustez.",
    "OddsPortal", "https://www.oddsportal.com/football/world/world-cup-2022/results/", "odds historicas e resultados", "HTML", "Copa 2022 e pagina 2026", "termos do site a validar antes de scraping", "auxiliar", "Candidata, mas scraping deve ser validado.",
    "OddsChecker", "https://www.oddschecker.com/br/futebol/internacional/copa-do-mundo-fifa", "odds por jogo e por casa", "HTML renderizado", "Copa do Mundo 2026", "site publico; coleta pode ser bloqueada por Cloudflare e termos devem ser respeitados", "auxiliar", "Scraper auditavel implementado em R/01_coleta/07b_baixar_odds_oddschecker.R.",
    "football-data.co.uk", "https://www.football-data.co.uk/data.php", "resultados e odds", "XLSX/CSV", "World Cup XLSX e ligas historicas", "uso livre com aviso; ver disclaimer do site", "primaria", "Fonte primaria V1 para odds via WorldCup2026.xlsx quando disponivel.",
    "The Odds API", "https://www.the-odds-api.com/", "odds via API", "JSON", "Atual e historico conforme plano/API", "exige chave; pode exigir plano pago", "descartada", "Descartada para V1 porque o pipeline deve usar apenas dados abertos sem compra de API key.",
    "Wikipedia/FIFA/RSSSF", "https://www.rsssf.org/", "validacao cruzada", "HTML", "Historico amplo", "licencas variam por fonte", "auxiliar", "Apoio para auditoria de datas, sedes e divergencias."
  )

  readr::write_csv(fontes, path)
  invisible(fontes)
}

coverage_status <- function(matches) {
  if (nrow(matches) == 0) {
    return("vazio")
  }

  has_scores <- sum(!is.na(matches$score_a) & !is.na(matches$score_b))
  if (has_scores == 0) {
    return("calendario")
  }
  if (has_scores < nrow(matches)) {
    return("parcial")
  }
  "completo"
}
