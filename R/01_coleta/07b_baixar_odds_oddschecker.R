source("R/01_coleta/lib_coleta.R")

ensure_dirs()

base_url <- "https://www.oddschecker.com"
competition_url <- paste0(base_url, "/br/futebol/internacional/copa-do-mundo-fifa")
raw_dir <- project_path("data/raw/odds/oddschecker")
status_path <- project_path("data/raw/metadata/oddschecker_status.csv")
match_urls_path <- project_path("data/raw/metadata/oddschecker_match_urls.csv")
output_path <- project_path("data/interim/odds/oddschecker_worldcup_2026_group_stage_odds.csv")
combined_odds_path <- project_path("data/interim/odds/worldcup_odds_2022_onwards.csv")

fs::dir_create(raw_dir)

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

write_status <- function(status, message, url = NA_character_) {
  row <- tibble::tibble(
    checked_at = now_iso(),
    status = status,
    message = message,
    url = url
  )

  old <- read_existing_csv(status_path)
  if (nrow(old) > 0 && "checked_at" %in% names(old)) {
    old <- old |>
      dplyr::mutate(checked_at = as.character(checked_at))
  }

  readr::write_csv(dplyr::bind_rows(old, row), status_path)
  invisible(row)
}

safe_slug <- function(x) {
  x |>
    stringr::str_to_lower() |>
    stringi::stri_trans_general("Latin-ASCII") |>
    stringr::str_replace_all("&", " and ") |>
    stringr::str_replace_all("[^a-z0-9]+", "-") |>
    stringr::str_replace_all("(^-|-$)", "")
}

slug_team_map <- tibble::tribble(
  ~slug, ~team,
  "usa", "USA",
  "turkey", "Turkey",
  "turkiye", "Turkey",
  "ivory-coast", "Ivory Coast",
  "cote-d-ivoire", "Ivory Coast",
  "curacao", "Curaçao",
  "czech-republic", "Czech Republic",
  "czechia", "Czech Republic",
  "south-korea", "South Korea",
  "cape-verde", "Cape Verde",
  "dr-congo", "DR Congo",
  "iran", "Iran",
  "ir-iran", "Iran",
  "bosnia-and-herzegovina", "Bosnia & Herzegovina"
)

slug_to_team <- function(slug) {
  mapped <- slug_team_map |>
    dplyr::filter(.data$slug == !!slug) |>
    dplyr::pull(team)

  if (length(mapped) > 0) {
    return(mapped[[1]])
  }

  slug |>
    stringr::str_replace_all("-", " ") |>
    stringr::str_to_title()
}

parse_match_slug <- function(url) {
  slug <- basename(url)
  parts <- stringr::str_split(slug, "-v-", n = 2, simplify = TRUE)

  if (ncol(parts) < 2 || !nzchar(parts[1, 2])) {
    return(tibble::tibble(team_a = NA_character_, team_b = NA_character_))
  }

  tibble::tibble(
    team_a = slug_to_team(parts[1, 1]),
    team_b = slug_to_team(parts[1, 2])
  )
}

is_blocked_html <- function(html) {
  stringr::str_detect(html, "Attention Required! \\| Cloudflare|Sorry, you have been blocked|enable cookies|cf-error-details")
}

fetch_html_httr <- function(url, path) {
  response <- httr2::request(url) |>
    httr2::req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36") |>
    httr2::req_headers(
      "accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "accept-language" = "pt-BR,pt;q=0.9,en;q=0.8"
    ) |>
    httr2::req_error(is_error = \(resp) FALSE) |>
    httr2::req_perform()

  html <- httr2::resp_body_string(response)
  readr::write_file(html, path)

  append_access_log(tibble::tibble(
    url = url,
    accessed_at = now_iso(),
    local_path = fs::path_rel(path, start = project_path()),
    http_status = httr2::resp_status(response),
    bytes = as.numeric(fs::file_size(path)),
    dataset = "oddschecker_worldcup_2026",
    coverage_status = dplyr::if_else(is_blocked_html(html), "blocked", "html")
  ))

  html
}

new_chromote_session <- function() {
  remote_port <- Sys.getenv("ODDSCHECKER_REMOTE_DEBUGGING_PORT")

  if (nzchar(remote_port)) {
    browser <- chromote::ChromeRemote$new(
      host = Sys.getenv("ODDSCHECKER_REMOTE_DEBUGGING_HOST", "127.0.0.1"),
      port = as.integer(remote_port)
    )
    parent <- chromote::Chromote$new(browser = browser)
    return(parent$new_session(width = 1440, height = 1200))
  }

  chromote::ChromoteSession$new(width = 1440, height = 1200)
}

fetch_html_chromote <- function(url, path, click_all_winner_odds = FALSE) {
  if (!requireNamespace("chromote", quietly = TRUE)) {
    write_status("chromote_unavailable", "Pacote chromote nao esta instalado.", url)
    return(NA_character_)
  }

  session <- new_chromote_session()
  on.exit(try(session$close(), silent = TRUE), add = TRUE)

  session$Page$navigate(url)
  Sys.sleep(as.numeric(Sys.getenv("ODDSCHECKER_RENDER_WAIT", "6")))

  if (click_all_winner_odds) {
    session$Runtime$evaluate(
      "
      (async () => {
        const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
        const articles = Array.from(document.querySelectorAll('article'));
        const winner = articles.find(article => article.innerText && article.innerText.includes('Vencedor'));
        if (!winner) return false;
        const buttons = Array.from(winner.querySelectorAll('button'))
          .filter(button => /Ver todas as odds|Comparar todas as odds/i.test(button.innerText || button.getAttribute('aria-label') || ''));
        for (const button of buttons) {
          button.scrollIntoView({ block: 'center' });
          button.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          await sleep(700);
        }
        return true;
      })();
      ",
      awaitPromise = TRUE
    )
    Sys.sleep(1)
  }

  html <- session$Runtime$evaluate(
    "document.documentElement.outerHTML",
    returnByValue = TRUE
  )$result$value

  readr::write_file(html, path)
  html
}

fetch_html <- function(url, path, click_all_winner_odds = FALSE) {
  html <- tryCatch(
    fetch_html_httr(url, path),
    error = function(err) {
      write_status("download_error", conditionMessage(err), url)
      NA_character_
    }
  )

  use_chromote <- identical(stringr::str_to_lower(Sys.getenv("ODDSCHECKER_USE_CHROMOTE", "false")), "true")
  if ((is.na(html) || is_blocked_html(html)) && use_chromote) {
    html <- tryCatch(
      fetch_html_chromote(url, path, click_all_winner_odds = click_all_winner_odds),
      error = function(err) {
        write_status("chromote_error", conditionMessage(err), url)
        html
      }
    )
  }

  if (!is.na(html) && is_blocked_html(html)) {
    write_status("cloudflare_blocked", "OddsChecker retornou pagina de bloqueio Cloudflare para coleta automatica.", url)
  }

  html
}

scrape_match_chromote_long <- function(url, raw_path = NULL) {
  if (!requireNamespace("chromote", quietly = TRUE)) {
    return(tibble::tibble())
  }

  session <- new_chromote_session()
  on.exit(try(session$close(), silent = TRUE), add = TRUE)

  session$Page$navigate(url)
  Sys.sleep(as.numeric(Sys.getenv("ODDSCHECKER_RENDER_WAIT", "6")))

  body_text <- session$Runtime$evaluate(
    "document.body ? document.body.innerText : ''",
    returnByValue = TRUE
  )$result$value

  if (is_blocked_html(body_text)) {
    write_status("chromote_cloudflare_blocked", "Chromote tambem recebeu bloqueio Cloudflare.", url)
    return(tibble::tibble())
  }

  js <- "
    (async () => {
      const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
      const decimal = value => {
        const match = String(value || '').match(/\\d+(?:\\.\\d+)?/);
        return match ? Number(match[0]) : null;
      };
      const articles = Array.from(document.querySelectorAll('article'));
      const winner = articles.find(article => article.innerText && article.innerText.includes('Vencedor'));
      if (!winner) return JSON.stringify([]);

      const compareButton = Array.from(winner.querySelectorAll('button'))
        .find(button => /Ver todas as odds|Comparar todas as odds/i.test(button.innerText || button.getAttribute('aria-label') || ''));
      const outcomes = ['team_a', 'draw', 'team_b'];
      const rows = [];

      if (compareButton) {
        compareButton.scrollIntoView({ block: 'center' });
        compareButton.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        await sleep(1800);
      }

      const grid = winner.querySelector('[data-testid=\"odds-grid-desktop\"]');
      if (!grid) return JSON.stringify(rows);

      const bookmakerNames = {};
      Array.from(grid.querySelectorAll('[data-testid=\"bookmaker-clickout\"][data-bk]')).forEach(link => {
        const code = link.getAttribute('data-bk');
        const name = (link.getAttribute('title') || link.getAttribute('aria-label') || '').trim();
        if (code && name && !bookmakerNames[code]) bookmakerNames[code] = name;
      });

      const bookmakerCodes = Object.keys(bookmakerNames);
      if (bookmakerCodes.length === 0) return JSON.stringify(rows);

      const desktopCells = Array.from(grid.querySelectorAll('[data-testid=\"odds-cell\"][data-bk]'))
        .filter(cell => cell.getAttribute('aria-label') === 'Add to betslip');

      desktopCells.forEach((cell, index) => {
        const code = cell.getAttribute('data-bk');
        const bookmakerIndex = bookmakerCodes.indexOf(code);
        const outcomeIndex = Math.floor(index / bookmakerCodes.length);
        const price = decimal(cell.innerText);

        if (bookmakerIndex < 0 || outcomeIndex < 0 || outcomeIndex >= outcomes.length || price === null) return;

        rows.push({
          bookmaker: bookmakerNames[code],
          outcome: outcomes[outcomeIndex],
          odds: price
        });
      });

      if (rows.length === 0) {
        const cells = Array.from(grid.querySelectorAll('[data-testid=\"odds-cell\"][data-bk]'));
        cells.forEach((cell, index) => {
          if (index % 2 === 1) return;
          const code = cell.getAttribute('data-bk');
          const outcomeIndex = Math.floor((index / 2) / bookmakerCodes.length);
          const price = decimal(cell.innerText);

          if (!bookmakerNames[code] || outcomeIndex < 0 || outcomeIndex >= outcomes.length || price === null) return;

          rows.push({
            bookmaker: bookmakerNames[code],
            outcome: outcomes[outcomeIndex],
            odds: price
          });
        });
      }

      return JSON.stringify(rows);
    })();
  "

  json <- session$Runtime$evaluate(js, awaitPromise = TRUE, returnByValue = TRUE)$result$value

  if (!is.null(raw_path)) {
    expanded_html <- session$Runtime$evaluate(
      "document.documentElement.outerHTML",
      returnByValue = TRUE
    )$result$value
    readr::write_file(expanded_html, raw_path)
  }

  parsed <- jsonlite::fromJSON(json)
  if (length(parsed) == 0 || nrow(parsed) == 0) {
    return(tibble::tibble())
  }

  tibble::as_tibble(parsed) |>
    dplyr::mutate(source_url = url)
}

extract_match_links <- function(html) {
  if (is.na(html) || is_blocked_html(html)) {
    return(tibble::tibble(source_url = character()))
  }

  doc <- xml2::read_html(html)
  hrefs <- doc |>
    rvest::html_elements("a[href]") |>
    rvest::html_attr("href") |>
    unique()

  from_href <- hrefs |>
    purrr::discard(is.na) |>
    purrr::keep(\(href) stringr::str_detect(href, "^/br/futebol/internacional/copa-do-mundo-fifa/.+-v-.+|^https://www\\.oddschecker\\.com/br/futebol/internacional/copa-do-mundo-fifa/.+-v-.+")) |>
    purrr::map_chr(\(href) {
      if (stringr::str_starts(href, "http")) href else paste0(base_url, href)
    })

  from_text <- stringr::str_extract_all(
    html,
    "https://www\\.oddschecker\\.com/br/futebol/internacional/copa-do-mundo-fifa/[a-z0-9-]+-v-[a-z0-9-]+|/br/futebol/internacional/copa-do-mundo-fifa/[a-z0-9-]+-v-[a-z0-9-]+"
  )[[1]] |>
    purrr::map_chr(\(href) {
      if (stringr::str_starts(href, "http")) href else paste0(base_url, href)
    })

  tibble::tibble(source_url = unique(c(from_href, from_text))) |>
    dplyr::mutate(match_slug = basename(source_url)) |>
    dplyr::filter(stringr::str_detect(match_slug, "-v-")) |>
    dplyr::distinct(source_url, .keep_all = TRUE)
}

extract_decimal <- function(x) {
  value <- stringr::str_extract(x, "\\d+(?:\\.\\d+)?")
  suppressWarnings(as.numeric(value))
}

parse_bookmaker_rows_from_lines <- function(lines, outcome, source_url) {
  start <- which(lines == "Casas de apostas")
  if (length(start) == 0) {
    return(tibble::tibble())
  }

  start <- start[[1]] + 2L
  stop_words <- c("Diminuindo", "Aumentando", "Empate", "Mostrar mais")
  rows <- list()
  i <- start

  while (i < length(lines)) {
    current <- lines[[i]]
    next_line <- lines[[i + 1]]

    if (current %in% stop_words || stringr::str_detect(current, "^Ver todas as odds|^bookie logo")) {
      break
    }

    if (stringr::str_detect(current, "Brazil$|Brasil$|Marrocos$|Morocco$|logo$")) {
      break
    }

    odd <- extract_decimal(next_line)
    if (stringr::str_detect(current, "Brazil|Bet|Stake|Sporting|Galera|Seguro") && !is.na(odd)) {
      rows[[length(rows) + 1L]] <- tibble::tibble(
        bookmaker = stringr::str_remove(current, "\\s+logo$"),
        outcome = outcome,
        odds = odd,
        source_url = source_url
      )
      i <- i + 2L
    } else {
      i <- i + 1L
    }
  }

  dplyr::bind_rows(rows)
}

parse_winner_market <- function(html, source_url) {
  if (is.na(html) || is_blocked_html(html)) {
    return(tibble::tibble())
  }

  text <- xml2::read_html(html) |>
    rvest::html_element("body") |>
    rvest::html_text2()

  lines <- text |>
    stringr::str_split("\\n") |>
    purrr::pluck(1) |>
    stringr::str_squish() |>
    purrr::discard(\(x) is.na(x) || !nzchar(x))

  winner_idx <- which(lines == "Vencedor")
  if (length(winner_idx) == 0) {
    return(tibble::tibble())
  }

  match_teams <- parse_match_slug(source_url)
  outcome_aliases <- tibble::tibble(
    outcome = c("team_a", "draw", "team_b"),
    label = c(match_teams$team_a, "Empate", match_teams$team_b),
    label_alt = c(
      dplyr::recode(match_teams$team_a, Brazil = "Brasil", .default = match_teams$team_a),
      "Empate",
      dplyr::recode(match_teams$team_b, Morocco = "Marrocos", .default = match_teams$team_b)
    )
  )

  purrr::pmap_dfr(outcome_aliases, function(outcome, label, label_alt) {
    label_idx <- which(lines %in% c(label, label_alt))
    label_idx <- label_idx[label_idx > winner_idx[[1]]]
    if (length(label_idx) == 0) {
      return(tibble::tibble())
    }

    chunk <- lines[label_idx[[1]]:length(lines)]
    parse_bookmaker_rows_from_lines(chunk, outcome, source_url)
  })
}

pivot_match_odds <- function(long_odds, match_meta) {
  if (nrow(long_odds) == 0) {
    return(odds_schema())
  }

  long_odds |>
    dplyr::group_by(bookmaker, source_url) |>
    dplyr::summarise(
      odds_team_a = odds[outcome == "team_a"][1] %||% NA_real_,
      odds_draw = odds[outcome == "draw"][1] %||% NA_real_,
      odds_team_b = odds[outcome == "team_b"][1] %||% NA_real_,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      year = 2026L,
      match_id = match_meta$match_id,
      date = match_meta$date,
      team_a = match_meta$team_a,
      team_b = match_meta$team_b,
      market = "1x2",
      odds_type = "snapshot",
      collected_at = now_iso(),
      source = "OddsChecker",
      source_sheet = NA_character_,
      source_event_id = basename(source_url)
    ) |>
    dplyr::select(
      year, match_id, date, team_a, team_b, bookmaker, market,
      odds_team_a, odds_draw, odds_team_b, odds_type, collected_at,
      source, source_url, source_sheet, source_event_id
    )
}

match_meta_from_url <- function(url, matches) {
  parsed <- parse_match_slug(url)
  team_a_slug <- safe_slug(parsed$team_a)
  team_b_slug <- safe_slug(parsed$team_b)

  hit <- matches |>
    dplyr::mutate(
      team_a_slug = safe_slug(team_a),
      team_b_slug = safe_slug(team_b)
    ) |>
    dplyr::filter(
      year == 2026,
      team_a_slug == !!team_a_slug,
      team_b_slug == !!team_b_slug
    ) |>
    dplyr::slice_head(n = 1)

  if (nrow(hit) == 0) {
    return(tibble::tibble(
      match_id = NA_character_,
      date = as.Date(NA),
      team_a = parsed$team_a,
      team_b = parsed$team_b
    ))
  }

  hit |>
    dplyr::transmute(match_id, date = lubridate::ymd(date), team_a, team_b)
}

scrape_match <- function(url, matches) {
  slug <- basename(url)
  raw_path <- fs::path(raw_dir, paste0(slug, ".html"))

  use_chromote <- identical(stringr::str_to_lower(Sys.getenv("ODDSCHECKER_USE_CHROMOTE", "false")), "true")
  if (use_chromote) {
    long_chromote <- tryCatch(
      scrape_match_chromote_long(url, raw_path = raw_path),
      error = function(err) {
        write_status("chromote_extract_error", conditionMessage(err), url)
        tibble::tibble()
      }
    )

    if (nrow(long_chromote) > 0) {
      meta <- match_meta_from_url(url, matches)
      return(pivot_match_odds(long_chromote, meta))
    }
  }

  html <- fetch_html(url, raw_path, click_all_winner_odds = TRUE)

  if (is.na(html) || is_blocked_html(html)) {
    return(odds_schema())
  }

  meta <- match_meta_from_url(url, matches)
  long <- parse_winner_market(html, url)
  odds <- pivot_match_odds(long, meta)

  if (nrow(odds) == 0) {
    write_status("no_bookmaker_odds", "Nao foi possivel localizar odds por casa no mercado Vencedor.", url)
  }

  odds
}

matches_path <- project_path("data/interim/matches/worldcup_matches_2022_onwards.csv")
matches <- read_existing_csv(matches_path) |>
  dplyr::mutate(date = lubridate::ymd(date))

index_path <- fs::path(raw_dir, "copa-do-mundo-fifa.html")
index_html <- fetch_html(competition_url, index_path, click_all_winner_odds = FALSE)
match_urls <- extract_match_links(index_html)

if (nrow(match_urls) == 0) {
  write_status("no_match_links", "Nenhum link de partida foi extraido da pagina indice.", competition_url)
  readr::write_csv(tibble::tibble(source_url = character(), match_slug = character()), match_urls_path)
  readr::write_csv(odds_schema(), output_path)
} else {
  readr::write_csv(match_urls, match_urls_path)

  max_matches <- as.integer(Sys.getenv("ODDSCHECKER_MAX_MATCHES", "0"))
  if (!is.na(max_matches) && max_matches > 0) {
    match_urls <- match_urls |>
      dplyr::slice_head(n = max_matches)
  }

  odds <- match_urls$source_url |>
    purrr::map_dfr(\(url) {
      Sys.sleep(as.numeric(Sys.getenv("ODDSCHECKER_DELAY_SECONDS", "1")))
      scrape_match(url, matches)
    }) |>
    janitor::clean_names()

  readr::write_csv(odds, output_path)
}

oddschecker_odds <- read_existing_csv(output_path) |>
  janitor::clean_names()

if (nrow(oddschecker_odds) > 0 && fs::file_exists(combined_odds_path)) {
  combined <- read_existing_csv(combined_odds_path) |>
    janitor::clean_names() |>
    dplyr::filter(source != "OddsChecker") |>
    dplyr::bind_rows(oddschecker_odds) |>
    dplyr::arrange(year, date, team_a, team_b, source, bookmaker)

  readr::write_csv(combined, combined_odds_path)
}
