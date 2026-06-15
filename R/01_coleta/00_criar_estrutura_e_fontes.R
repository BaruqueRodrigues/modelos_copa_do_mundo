source("R/01_coleta/lib_coleta.R")

ensure_dirs()
write_source_inventory()

dir_check <- tibble::tibble(
  path = required_dirs(),
  exists = purrr::map_lgl(project_path(path), fs::dir_exists)
)

readr::write_csv(dir_check, project_path("data/raw/metadata/estrutura_pastas.csv"))

