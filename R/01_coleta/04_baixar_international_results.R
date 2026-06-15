source("R/01_coleta/lib_coleta.R")

ensure_dirs()

url <- "https://raw.githubusercontent.com/martj42/international_results/master/results.csv"
destino <- project_path("data/raw/matches/international_results.csv")

entrada <- download_file(url, destino) |>
  dplyr::mutate(dataset = "international_results", coverage_status = "historico")

append_access_log(entrada)

recentes <- readr::read_csv(destino, show_col_types = FALSE) |>
  janitor::clean_names() |>
  dplyr::mutate(date = lubridate::ymd(date)) |>
  dplyr::filter(date >= lubridate::ymd("2018-01-01"))

readr::write_csv(recentes, project_path("data/interim/matches/international_results_since_2018.csv"))

