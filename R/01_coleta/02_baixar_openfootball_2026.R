source("R/01_coleta/lib_coleta.R")

ensure_dirs()

urls <- c(
  "https://raw.githubusercontent.com/openfootball/worldcup/master/2026--usa/cup.txt",
  "https://raw.githubusercontent.com/openfootball/worldcup/master/2026--usa/cup_finals.txt"
)
destinos <- c(
  project_path("data/raw/matches/openfootball_worldcup_2026.txt"),
  project_path("data/raw/matches/openfootball_worldcup_2026_finals.txt")
)

entrada <- purrr::map2_dfr(urls, destinos, download_file) |>
  dplyr::mutate(dataset = "openfootball_worldcup_2026", coverage_status = "a_classificar_no_parse")

append_access_log(entrada)
