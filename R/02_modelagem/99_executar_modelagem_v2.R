scripts <- c(
  "R/02_modelagem/01_preparar_base_modelagem.R",
  "R/02_modelagem/02_estimar_modelos_placares.R",
  "R/02_modelagem/03_estimar_modelos_placares_v2.R"
)

purrr::walk(scripts, source)
