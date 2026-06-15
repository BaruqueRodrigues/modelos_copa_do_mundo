scripts <- c(
  "R/02_modelagem/01_preparar_base_modelagem.R",
  "R/02_modelagem/02_estimar_modelos_placares.R"
)

purrr::walk(scripts, source)
