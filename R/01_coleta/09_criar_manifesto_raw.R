source("R/01_coleta/lib_coleta.R")

ensure_dirs()

log_path <- project_path("data/raw/metadata/data_access_log.csv")
access_log <- read_existing_csv(log_path)

raw_files <- fs::dir_ls(project_path("data/raw"), recurse = TRUE, type = "file")

manifest <- tibble::tibble(
  local_path = fs::path_rel(raw_files, start = project_path()),
  size_bytes = as.numeric(fs::file_size(raw_files)),
  checksum_sha256 = purrr::map_chr(raw_files, digest::digest, file = TRUE, algo = "sha256")
) |>
  dplyr::left_join(
    access_log |>
      dplyr::select(local_path, url, accessed_at) |>
      dplyr::group_by(local_path) |>
      dplyr::slice_tail(n = 1) |>
      dplyr::ungroup(),
    by = "local_path"
  ) |>
  dplyr::select(local_path, url, accessed_at, size_bytes, checksum_sha256)

readr::write_csv(manifest, project_path("data/raw/metadata/raw_data_manifest.csv"))

