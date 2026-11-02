# Programmatic checks for the website figures.
#   1. Plotting CSVs are byte-identical to what provenance.json recorded and,
#      when the Dropbox sources are reachable, the source files still have the
#      recorded SHA-256 and every plotted row equals the source row verbatim.
#   2. Every drawn point and 95% bar equals the saved estimate / ci_lo / ci_hi
#      for the same (period, series) key, row by row (a permutation fails),
#      with the original support (10 gap, 12 UP, 24 by-type) and no interval
#      layer other than the single saved-95% linerange.
#   3. Pooled UP markers are filled exactly where the saved p < 0.05.
#   4. Titles, subtitles, axis labels, legend and notes equal the original
#      website wording; no "90" interval text anywhere.
#   5. Output PNGs are 1800 x 1100, differ from the original website image at
#      the fixed baseline commit BASELINE (not the moving HEAD, so the check
#      survives later commits of the restyled PNGs), and the copies under
#      static/img and public/img are byte-identical (sha256). A baseline blob
#      that cannot be resolved is a FAIL, never a pass.
#   6. Printed numbers reproduce those on the original figures.
# Usage (repo root):  Rscript scripts/figures/03_verify.R
suppressPackageStartupMessages({ library(ggplot2); library(jsonlite); library(digest) })

args <- commandArgs(trailingOnly = FALSE)
fig_here <- dirname(normalizePath(sub("^--file=", "", args[grep("^--file=", args)])))
repo <- normalizePath(file.path(fig_here, "..", ".."))
data_dir <- file.path(fig_here, "data")
prov <- fromJSON(file.path(data_dir, "provenance.json"))
fails <- 0L
check <- function(ok, msg) {
  cat(if (isTRUE(ok)) "PASS " else { fails <<- fails + 1L; "FAIL " }, msg, "\n", sep = "")
}

# ---- 1. hashes and verbatim rows ---------------------------------------------
for (f in names(prov$extracts))
  check(identical(digest(file = file.path(data_dir, f), algo = "sha256"), prov$extracts[[f]]$sha256),
        sprintf("%s matches provenance hash", f))

dropbox <- Sys.getenv("FIG_DROPBOX_ROOT", path.expand("~/Library/CloudStorage/Dropbox"))
src_path <- function(k) file.path(dropbox, sub("^<Dropbox>/", "", prov$sources[[k]]$path))
if (all(file.exists(vapply(names(prov$sources), src_path, "")))) {
  for (k in names(prov$sources))
    check(identical(digest(file = src_path(k), algo = "sha256"), prov$sources[[k]]$sha256),
          sprintf("source %s unchanged (sha256 %s)", k, substr(prov$sources[[k]]$sha256, 1, 12)))
  rd <- function(p) read.csv(p, colClasses = "character", na.strings = character(0))
  same_rows <- function(src, ext, key_filter) {
    s <- rd(src); s <- s[key_filter(s), names(ext)]
    rownames(s) <- NULL; identical(s, ext)
  }
  check(same_rows(src_path("crime_gap_es"), rd(file.path(data_dir, "crime_gap_es.csv")),
                  function(s) s$estimator == "csdid_nt" & as.integer(s$event_time) >= -6 &
                    as.integer(s$event_time) <= 3),
        "crime_gap_es.csv rows identical (as text) to source csdid_nt rows, e = -6..3")
  check(same_rows(src_path("reshuffling_up"), rd(file.path(data_dir, "reshuffling_up_es.csv")),
                  function(s) s$sign_group == "UP"),
        "reshuffling_up_es.csv rows identical (as text) to source UP rows")
  check(same_rows(src_path("reshuffling_by_type"), rd(file.path(data_dir, "reshuffling_by_type_es.csv")),
                  function(s) rep(TRUE, nrow(s))),
        "reshuffling_by_type_es.csv rows identical (as text) to source")
} else cat("SKIP source re-check: Dropbox sources not reachable\n")

gap <- read.csv(file.path(data_dir, "crime_gap_es.csv"), na.strings = "NA")
up  <- read.csv(file.path(data_dir, "reshuffling_up_es.csv"), na.strings = c("NA", ""))
bt  <- read.csv(file.path(data_dir, "reshuffling_by_type_es.csv"), na.strings = c("NA", ""))

# ---- 2. drawn values == saved values, keyed by (period, series) ---------------
Sys.setenv(FIG_NO_SAVE = "1")
source(file.path(fig_here, "02_render_figures.R"), local = TRUE)
Sys.unsetenv("FIG_NO_SAVE")
interval_geoms <- c("GeomLinerange", "GeomErrorbar", "GeomCrossbar", "GeomPointrange",
                    "GeomRibbon", "GeomArea", "GeomRect", "GeomSegment")
layer_idx <- function(p, cls) which(vapply(p$layers, function(l) inherits(l$geom, cls), TRUE))
# Built layer data with a "period|series" key. Dodged x is mapped back to the
# period by rounding; the series comes from the group index (factor level order).
keyed <- function(p, cls, series_levels = NULL) {
  i <- layer_idx(p, cls); stopifnot(length(i) == 1)
  d <- ggplot_build(p)$data[[i]]
  s <- if (is.null(series_levels)) rep("all", nrow(d)) else series_levels[d$group]
  d$key <- paste(round(d$x), s, sep = "|"); d
}
saved_keyed <- function(period, series, est, lo, hi)
  data.frame(key = paste(period, series, sep = "|"), est = est, lo = lo, hi = hi)
compare_keyed <- function(p, saved, series_levels = NULL) {
  pts  <- keyed(p, "GeomPoint", series_levels)
  bars <- keyed(p, "GeomLinerange", series_levels)
  bars <- bars[!is.na(bars$ymin) & !is.na(bars$ymax), ]   # NA bounds are not drawn (na.rm)
  m_pt <- match(saved$key, pts$key)
  # bars with NA bounds (gap reference period) are dropped by na.rm; compare the rest
  sv_b <- saved[!is.na(saved$lo) & !is.na(saved$hi), ]
  m_b  <- match(sv_b$key, bars$key)
  list(n_pts = nrow(pts), n_bars = nrow(bars), n_bar_saved = nrow(sv_b),
       keys_unique = !anyDuplicated(pts$key) && !anyDuplicated(bars$key),
       pts_ok = !anyNA(m_pt) && identical(pts$y[m_pt], saved$est),
       bars_ok = !anyNA(m_b) && nrow(bars) == nrow(sv_b) &&
         identical(bars$ymin[m_b], sv_b$lo) && identical(bars$ymax[m_b], sv_b$hi))
}
check_fig <- function(p, saved, n_expected, label, series_levels = NULL) {
  r <- compare_keyed(p, saved, series_levels)
  check(nrow(saved) == n_expected && r$n_pts == n_expected && r$keys_unique,
        sprintf("%s: original support of %d (period, series) points, keys unique", label, n_expected))
  check(r$pts_ok, sprintf("%s: each drawn point equals the saved estimate for its key", label))
  check(r$bars_ok, sprintf("%s: each drawn bar equals saved ci_lo/ci_hi for its key (%d bars)",
                           label, r$n_bar_saved))
  n_int <- vapply(interval_geoms, function(g) length(layer_idx(p, g)), 1L)
  check(identical(unname(n_int[["GeomLinerange"]]), 1L) && sum(n_int) == 1L,
        sprintf("%s: exactly one interval layer (saved 95%%), no other interval geoms", label))
  # negative control: a swap of two periods' values must be detected
  perm <- saved; perm[c(1, nrow(perm)), c("est", "lo", "hi")] <- perm[c(nrow(perm), 1), c("est", "lo", "hi")]
  rp <- compare_keyed(p, perm, series_levels)
  check(!rp$pts_ok && !rp$bars_ok, sprintf("%s: keyed comparison rejects a permuted copy", label))
}
sv_gap <- saved_keyed(gap$event_time, "all", gap$att, gap$ci_lower, gap$ci_upper)
sv_up  <- saved_keyed(up$year, "all", up$est, up$ci_lo, up$ci_hi)
sv_bt  <- saved_keyed(bt$year, as.character(bt$school_type), bt$est, bt$ci_lo, bt$ci_hi)
check_fig(p_gap, sv_gap, 10L, "crime gap")
check_fig(p_up,  sv_up,  12L, "UP")
check_fig(p_bt,  sv_bt,  24L, "by type", series_levels = levels(bt$school_type))

# ---- 3. pooled UP filled markers = saved p < 0.05 ------------------------------
up_pts <- keyed(p_up, "GeomPoint")
m <- match(paste(up$year, "all", sep = "|"), up_pts$key)
check(identical(up_pts$fill[m] == "grey35", !is.na(up$pval) & up$pval < 0.05),
      "UP: filled markers exactly where saved p < 0.05 (original marker semantics)")

# ---- 4. original wording ------------------------------------------------------
lab_is <- function(p, want) all(vapply(names(want), function(k) identical(p$labels[[k]], want[[k]]), TRUE))
bars_line <- "Bars show 95% confidence intervals."
check(lab_is(p_gap, list(
  title = "Dual VET narrows the youth-adult crime gap",
  subtitle = paste0("Effect on the 16-25 minus 36-45 crime-rate gap.\n",
                    "Post-period average: -17.1 per 1,000 (p = 0.011); pre-trend p = 0.84."),
  y = "Gap, crimes per 1,000 residents", x = "Years relative to dual-VET adoption",
  caption = bars_line)), "crime gap: original title, subtitle, axis labels; caption = bars line only")
check(lab_is(p_up, list(
  title = "Continuous DiD \u2013 Infantil (published quotas; UP schools)",
  subtitle = "Outcome: Effect on NESE-B number", y = "Effect on NESE-B number", x = "Year")) &&
  identical(gsub("\n", " ", p_up$labels$caption), paste(
    "BCN public+charter; baseline 2016\u20132018; quota year 2019 (ref = 2018);",
    "n = 311 UP schools (filled = p<0.05)", bars_line)),
  "UP: original title, subtitle, axis labels and note")
check(lab_is(p_bt, list(
  title = "Continuous DiD \u2013 Infantil (UP schools by type; published quotas)",
  subtitle = "Outcome: Effect on NESE-B number", y = "Effect on NESE-B number", x = "Year")) &&
  identical(gsub("\n", " ", p_bt$labels$caption), paste(
    "Public: pre-avg +0.057, post-avg +1.259 (n=158) | Charter: pre-avg -0.029, post-avg +0.399 (n=153) |",
    "BCN UP-direction schools; baseline 2016\u20132018; quota year 2019 (ref=2018)", bars_line)),
  "by type: original title, subtitle, axis labels and note (printed averages and n)")
bt_scales <- ggplot_build(p_bt)$plot$scales
leg_ok <- all(vapply(c("colour", "fill", "shape"), function(a) {
  sc <- bt_scales$get_scales(a); identical(sc$name, "School type") &&
    identical(sc$get_labels(), c("Public", "Charter")) }, TRUE))
check(leg_ok, "by type: legend 'School type: Public, Charter'")
all_text <- unlist(lapply(list(p_gap, p_up, p_bt), function(p) unlist(p$labels)))
check(!any(grepl("90", all_text)) && !any(grepl("\\bSE\\b", all_text)),
      "no 90% interval or SE text in any figure label")
src <- readLines(file.path(fig_here, "02_render_figures.R"))
check(!any(grepl("qnorm|90|lo90|hi90", src)), "renderer contains no 90% interval computation")

# ---- 5. PNG size, change vs immutable baseline, site copies identical --------
# BASELINE = original website checkout (commit 3c33d79, "Clip figures to their
# rounded frames") from which the figures were restyled. Fixed constant: do not
# replace with HEAD.
BASELINE <- "3c33d79aab0943ff209224029cf80dce9b9f3363"
git_blob <- function(rev_path) {
  out <- suppressWarnings(system2("git", c("-C", repo, "rev-parse", "--verify", "--quiet", rev_path),
                                  stdout = TRUE, stderr = FALSE))
  st <- attr(out, "status")
  if ((!is.null(st) && st != 0L) || length(out) != 1L || !grepl("^[0-9a-f]{40}$", out)) NA_character_ else out
}
png_dim <- function(f) { con <- file(f, "rb"); on.exit(close(con)); readBin(con, "raw", 16)
  h <- readBin(con, "raw", 8); c(sum(as.integer(h[1:4]) * 256^(3:0)), sum(as.integer(h[5:8]) * 256^(3:0))) }
owned <- c("crime_youth_adult_gap_centered.png", "reshuffling_up.png", "reshuffling_by_type.png")
for (f in owned) {
  p <- file.path(repo, "img", f)
  check(identical(png_dim(p), c(1800, 1100)), sprintf("%s is 1800 x 1100", f))
  base_blob <- git_blob(paste0(BASELINE, ":img/", f))
  now_blob  <- system2("git", c("-C", repo, "hash-object", p), stdout = TRUE)
  check(!is.na(base_blob), sprintf("baseline blob %s:img/%s resolves", substr(BASELINE, 1, 7), f))
  check(!is.na(base_blob) && length(now_blob) == 1L && !identical(base_blob, now_blob),
        sprintf("%s differs from original at baseline %s (%s -> %s)", f, substr(BASELINE, 1, 7),
                substr(base_blob, 1, 8), substr(now_blob, 1, 8)))
  h <- vapply(c("img", "static/img", "public/img"),
              function(d) digest(file = file.path(repo, d, f), algo = "sha256"), "")
  check(length(unique(h)) == 1L, sprintf("%s identical in img/, static/img/, public/img/ (sha256 %s)",
                                         f, substr(h[[1]], 1, 12)))
}

# ---- 6. caption numbers vs numbers printed on the original figures -----------
check(identical(sprintf("%+.3f", c(avg("Public", 2013:2018), avg("Public", 2019:2024),
                                   avg("Charter", 2013:2018), avg("Charter", 2019:2024))),
                c("+0.057", "+1.259", "-0.029", "+0.399")),
      "by type: pre/post averages reproduce original caption (+0.057, +1.259, -0.029, +0.399)")
check(identical(as.integer(n_by[c("Public", "Charter")]), c(158L, 153L)) && up$n_schools[1] == 311,
      "school counts reproduce originals (UP 311; public 158; charter 153)")
check(identical(c(sprintf("%.1f", as.numeric(agg$post_avg_att)), agg$post_avg_p,
                  sprintf("%.2f", as.numeric(agg$pretest_wald_p))), c("-17.1", "0.011", "0.84")),
      "crime gap: post average / p / pre-test round to original subtitle (-17.1, 0.011, 0.84)")

cat(sprintf("\n%d failure(s)\n", fails))
quit(status = if (fails) 1L else 0L)
