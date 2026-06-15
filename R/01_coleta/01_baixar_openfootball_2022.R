source("R/01_coleta/lib_coleta.R")

ensure_dirs()

urls <- c(
  "https://raw.githubusercontent.com/openfootball/worldcup/master/2022--qatar/cup.txt",
  "https://raw.githubusercontent.com/openfootball/worldcup/master/2022--qatar/cup_finals.txt"
)
destinos <- c(
  project_path("data/raw/matches/openfootball_worldcup_2022.txt"),
  project_path("data/raw/matches/openfootball_worldcup_2022_finals.txt")
)

entrada <- purrr::map2_dfr(urls, destinos, download_file) |>
  dplyr::mutate(dataset = "openfootball_worldcup_2022", coverage_status = "completo")

append_access_log(entrada)
