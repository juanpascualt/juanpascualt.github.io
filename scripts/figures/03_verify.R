# Programmatic checks for the website figures.
#   1. Plotting CSVs are byte-identical to what provenance.json recorded and,
#      when the Dropbox sources are reachable, the source files still have the
#      recorded SHA-256 and every plotted row equals the source row verbatim.
#   2. Every drawn point and 95% bar equals the saved estimate / ci_lo / ci_hi
#      for the same (period, series) key, row by row (a permutation fails),
#      with the original support (10 gap, 12 UP, 24 by-type). Each figure has
#      exactly two interval layers: thin saved 95% (verbatim) and thick 90%
#      equal to est -/+ qnorm(0.95) * saved SE, keyed the same way.
#   3. Pooled UP markers are filled exactly where the saved p < 0.05.
#   3b. Monthly wage (graphical reconstruction): archived original's sha256 and
#      baseline identity; every drawn centre and 95% bar endpoint equals the
#      saved source image coordinate for its event time (after scale_y_reverse);
#      no 95% or 90% bar at e = -1; exactly two interval layers (thin 95% =
#      saved endpoints, thick 90% = centre + qnorm(0.95)/1.96 x (95% endpoint -
#      centre), checked with an independently written formula); hollow markers;
#      tick positions/labels, panel limits and reference-line positions from
#      wage_geometry.json; no coefficient/SE columns.
#   4. Template on all four: web-adaptation serif sizes (title 24, axis 16,
#      ticks 13, legend 13, Notes 12 pt), no subtitle, outcome titles (no
#      ": Event Study") word-wrapped at 70 characters and measured to fit the
#      canvas width in at most 2 lines, colours, margins, point
#      shape/size/stroke, line widths, palette, and the exact title / axis /
#      legend text. Explanatory Notes: exactly 3 explicit lines per figure
#      (exact text; "Notes:" prefix on line 1; line 3 = treatment-effect
#      reading with stars and a percent magnitude, no p-threshold legend), each
#      rendered line measured at
#      12 pt to fit the width; no other technical statistics (ATT, SE,
#      p-values, school counts, estimator names) on the charts.
#   5. All four PNGs are 3300 x 2250 at 300 dpi (11 x 7.5 in), differ from the
#      original website image at the fixed baseline commit BASELINE (not the
#      moving HEAD), and the copies under static/img and public/img are
#      byte-identical (sha256). A baseline blob that cannot be resolved is a
#      FAIL, never a pass. The .paper-figures img rule has aspect-ratio 22 / 15
#      in css/, static/css/ and public/css/style.css.
#   6. Archived statistics (printed on the original figures, documented in the
#      README, no longer on the charts) are reproduced from the saved data.
#   7. Third-line effects: data/caption_effects.json rows equal the saved source
#      rows verbatim (static DiD; crime tab_main_ddd.csv) or their selected-column
#      projections as text (wage survey_results_full.csv; mfx_levels_ddd.csv;
#      field names checked exactly) and the sources keep their
#      SHA-256 (when reachable); printed numbers/stars/percentages follow from
#      the full-precision saved rows and unrounded p (independent star rule,
#      boundary cases); wage row rounds to the printed original ATT/SE; crime
#      percent uses the descriptive full-panel mean gap; quota percent = 100 * beta.
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
Sys.setenv(FIG_NO_SAVE = "1")
source(file.path(fig_here, "02_render_figures.R"), local = TRUE)
Sys.unsetenv("FIG_NO_SAVE")
interval_geoms <- c("GeomLinerange", "GeomErrorbar", "GeomCrossbar", "GeomPointrange",
                    "GeomRibbon", "GeomArea", "GeomRect", "GeomSegment")
layer_idx <- function(p, cls) which(vapply(p$layers, function(l) inherits(l$geom, cls), TRUE))
lw_of <- function(l) l$aes_params$linewidth
# The linerange layer drawn with linewidth `lw` (0.4 = 95%, 1.3 = 90%).
range_idx <- function(p, lw) {
  i <- layer_idx(p, "GeomLinerange")
  i[vapply(p$layers[i], function(l) isTRUE(all.equal(lw_of(l), lw)), TRUE)]
}
# Built layer data with a "period|series" key. Dodged x is mapped back to the
# period by rounding; the series comes from the group index (factor level order).
keyed_i <- function(p, i, series_levels = NULL) {
  stopifnot(length(i) == 1)
  d <- ggplot_build(p)$data[[i]]
  s <- if (is.null(series_levels)) rep("all", nrow(d)) else series_levels[d$group]
  d$key <- paste(round(d$x), s, sep = "|"); d
}
keyed <- function(p, cls, series_levels = NULL) keyed_i(p, layer_idx(p, cls), series_levels)
Z <- qnorm(0.95)
saved_keyed <- function(period, series, est, lo, hi, se)
  data.frame(key = paste(period, series, sep = "|"), est = est, lo = lo, hi = hi,
             lo90 = est - Z * se, hi90 = est + Z * se)
bars_match <- function(p, i, saved, lo, hi, series_levels) {
  bars <- keyed_i(p, i, series_levels)
  bars <- bars[!is.na(bars$ymin) & !is.na(bars$ymax), ]   # NA bounds are not drawn (na.rm)
  sv <- saved[!is.na(saved[[lo]]) & !is.na(saved[[hi]]), ]
  m <- match(sv$key, bars$key)
  list(n = nrow(sv), unique = !anyDuplicated(bars$key),
       ok = !anyNA(m) && nrow(bars) == nrow(sv) &&
         identical(bars$ymin[m], sv[[lo]]) && identical(bars$ymax[m], sv[[hi]]))
}
compare_keyed <- function(p, saved, series_levels = NULL) {
  pts <- keyed(p, "GeomPoint", series_levels)
  m_pt <- match(saved$key, pts$key)
  b95 <- bars_match(p, range_idx(p, 0.4), saved, "lo", "hi", series_levels)
  b90 <- bars_match(p, range_idx(p, 1.3), saved, "lo90", "hi90", series_levels)
  list(n_pts = nrow(pts), keys_unique = !anyDuplicated(pts$key) && b95$unique && b90$unique,
       pts_ok = !anyNA(m_pt) && identical(pts$y[m_pt], saved$est),
       bars_ok = b95$ok, n95 = b95$n, bars90_ok = b90$ok, n90 = b90$n)
}
check_fig <- function(p, saved, n_expected, label, series_levels = NULL) {
  n_int <- vapply(interval_geoms, function(g) length(layer_idx(p, g)), 1L)
  check(identical(unname(n_int[["GeomLinerange"]]), 2L) && sum(n_int) == 2L &&
          length(range_idx(p, 0.4)) == 1L && length(range_idx(p, 1.3)) == 1L &&
          max(range_idx(p, 0.4)) < min(range_idx(p, 1.3)),
        sprintf("%s: exactly two interval layers (thin 0.4 = 95%%, thick 1.3 = 90%%, 95%% drawn first)", label))
  r <- compare_keyed(p, saved, series_levels)
  check(nrow(saved) == n_expected && r$n_pts == n_expected && r$keys_unique,
        sprintf("%s: original support of %d (period, series) points, keys unique", label, n_expected))
  check(r$pts_ok, sprintf("%s: each drawn point equals the saved estimate for its key", label))
  check(r$bars_ok, sprintf("%s: each thin bar equals saved 95%% ci_lo/ci_hi verbatim (%d bars)", label, r$n95))
  check(r$bars90_ok, sprintf("%s: each thick bar equals est -/+ qnorm(0.95) x saved SE (%d bars)", label, r$n90))
  # negative controls: a swap of two periods, or 1.96-based 90% bars, must be detected
  perm <- saved; cols <- c("est", "lo", "hi", "lo90", "hi90")
  perm[c(1, nrow(perm)), cols] <- perm[c(nrow(perm), 1), cols]
  rp <- compare_keyed(p, perm, series_levels)
  check(!rp$pts_ok && !rp$bars_ok && !rp$bars90_ok,
        sprintf("%s: keyed comparison rejects a permuted copy", label))
  wrong <- saved; wrong$lo90 <- saved$lo; wrong$hi90 <- saved$hi
  check(!compare_keyed(p, wrong, series_levels)$bars90_ok,
        sprintf("%s: 90%% check rejects bars equal to the 95%% bounds", label))
}
sv_gap <- saved_keyed(gap$event_time, "all", gap$att, gap$ci_lower, gap$ci_upper, gap$se)
sv_up  <- saved_keyed(up$year, "all", up$est, up$ci_lo, up$ci_hi, up$se)
sv_bt  <- saved_keyed(bt$year, as.character(bt$school_type), bt$est, bt$ci_lo, bt$ci_hi, bt$se)
check_fig(p_gap, sv_gap, 10L, "crime gap")
check_fig(p_up,  sv_up,  12L, "UP")
check_fig(p_bt,  sv_bt,  24L, "by type", series_levels = levels(bt$school_type))
check(max(abs(c(gap$ci_upper - gap$att - 1.96 * gap$se, up$ci_hi - up$est - 1.96 * up$se,
                bt$ci_hi - bt$est - 1.96 * bt$se)), na.rm = TRUE) < 1e-12,
      "saved 95% bounds are est + 1.96 SE (drawn verbatim, not recomputed)")
check(all(gap$se[gap$event_time == -1] %in% NA) && all(up$se[up$year == 2018] == 0) &&
        all(bt$se[bt$year == 2018] == 0), "reference rows keep saved NA (gap) or 0/0 (reshuffling)")

# ---- 3. pooled UP filled markers = saved p < 0.05 ------------------------------
up_pts <- keyed(p_up, "GeomPoint")
m <- match(paste(up$year, "all", sep = "|"), up_pts$key)
check(identical(up_pts$fill[m] == "#0072B2", !is.na(up$pval) & up$pval < 0.05) &&
        all(up_pts$fill[m] %in% c("#0072B2", "white")),
      "UP: filled (#0072B2) markers exactly where saved p < 0.05, white otherwise")
gap_pts <- keyed(p_gap, "GeomPoint")
check(all(gap_pts$fill == "#0072B2"), "crime gap: all markers filled #0072B2 (as original: all filled)")

# ---- 3b. monthly wage: source-coordinate reconstruction --------------------------
notes_text <- function(p) gsub(" ", " ", gsub("\n", " ", p$labels$caption))
unwrap <- function(s) gsub("\n", " ", s)
WAGE_SRC_SHA <- "9bac3c2192b637dbf538852cc2854e9446b44a1e2d8c86de58ce10d9d3eb98de"
gj <- fromJSON(file.path(data_dir, "wage_geometry.json"), simplifyVector = FALSE)
orig <- file.path(data_dir, "original_wage.png")
check(identical(digest(file = orig, algo = "sha256"), WAGE_SRC_SHA) && identical(gj$source_sha256, WAGE_SRC_SHA),
      "wage: archived original_wage.png sha256 9bac3c2192b6 (= wage_geometry.json source_sha256)")
orig_blob <- system2("git", c("-C", repo, "hash-object", orig), stdout = TRUE)
base_wage <- git_blob(paste0(BASELINE, ":img/crime_monthly_earnings_large.png"))
check(!is.na(base_wage) && identical(orig_blob, base_wage),
      "wage: original_wage.png is byte-identical to img/crime_monthly_earnings_large.png at baseline 3c33d79")
check(!any(c("output", "output_sha256", "class_colours", "font", "font_px", "note_lines", "text_bboxes_px",
             "checks", "reference_line_max_grey_shift") %in% names(gj)) &&
        all(c("coordinate_system", "measurement_method", "ci_endpoint_choice", "rendering") %in% names(gj)),
      "wage_geometry.json: measured source fields only (no raster-output hash, recolour or PIL text fields); method documented")
wb <- ggplot_build(p_wage)
wl <- function(cls) { i <- layer_idx(p_wage, cls); stopifnot(length(i) == 1); wb$data[[i]] }
wpt <- wl("GeomPoint")
wl_i <- function(i) { stopifnot(length(i) == 1); wb$data[[i]] }
wbar <- wl_i(range_idx(p_wage, 0.4)); wbar90 <- wl_i(range_idx(p_wage, 1.3))
et <- vapply(gj$markers, function(m) as.integer(m$event_time), 1L)
cx <- vapply(gj$markers, function(m) m$centre_xy[[1]], 1); cy <- vapply(gj$markers, function(m) m$centre_xy[[2]], 1)
has_bar <- !vapply(gj$markers, function(m) is.null(m$bar_core_rows_top_bottom), TRUE)
check(identical(et, -6:6) && identical(et[!has_bar], -1L), "wage: 13 saved markers e = -6..6; only e = -1 has no bar core")
# event-time key = nearest saved x tick centre; built y is -y_px under scale_y_reverse
wx_c <- vapply(gj$x_tick_centres_px, as.numeric, 1)
key_of <- function(x) as.integer(names(wx_c))[vapply(x, function(v) which.min(abs(wx_c - v)), 1L)]
m <- match(et, key_of(wpt$x))
check(nrow(wpt) == 13L && !anyNA(m) && !anyDuplicated(key_of(wpt$x)) &&
        identical(wpt$x[m], cx) && identical(-wpt$y[m], cy),
      "wage: each drawn centre equals saved centre_xy for its event time exactly (y via scale_y_reverse)")
wbar <- wbar[!is.na(wbar$ymin) & !is.na(wbar$ymax), ]
mb <- match(et[has_bar], key_of(wbar$x))
top <- vapply(gj$markers[has_bar], function(m) as.numeric(m$bar_core_rows_top_bottom[[1]]), 1)
bot <- vapply(gj$markers[has_bar], function(m) as.numeric(m$bar_core_rows_top_bottom[[2]]), 1)
w_top <- pmin(-wbar$ymin, -wbar$ymax)[mb]; w_bot <- pmax(-wbar$ymin, -wbar$ymax)[mb]
check(nrow(wbar) == 12L && !anyNA(mb) && identical(wbar$x[mb], cx[has_bar]) &&
        identical(w_top, top) && identical(w_bot, bot),
      "wage: each 95% bar spans saved bar_core_rows_top_bottom exactly (12 bars; none at e = -1)")
check(!identical(w_top, rev(top)) && !identical(w_bot, rev(bot)),
      "wage: endpoint comparison rejects a permuted copy")
n_int_w <- vapply(interval_geoms, function(g) length(layer_idx(p_wage, g)), 1L)
check(identical(unname(n_int_w[["GeomLinerange"]]), 2L) && sum(n_int_w) == 2L &&
        length(range_idx(p_wage, 0.4)) == 1L && length(range_idx(p_wage, 1.3)) == 1L &&
        max(range_idx(p_wage, 0.4)) < min(range_idx(p_wage, 1.3)),
      "wage: exactly two interval layers (thin 0.4 = original 95%, thick 1.3 = 90%, 95% drawn first)")
# 90% bars. The historical producer (5_Package @ 96eec10, 08_survey_outcomes.R
# l. 511-517) drew the 95% bars as att -/+ 1.96 * bootstrap se (cband = FALSE),
# so a pointwise normal 90% bar is the 95% bar shrunk about the centre by
# qnorm(0.95) / 1.96. Written here as a weighted average, independently of the
# renderer's est + r * (lo95 - est).
R90 <- qnorm(0.95) / 1.96
check(isTRUE(all.equal(R90, 0.83921103, tolerance = 1e-8)) && isTRUE(all.equal(WAGE90_RATIO, R90, tolerance = 0)),
      sprintf("wage: 90/95 half-length ratio qnorm(0.95)/1.96 = %.8f (renderer WAGE90_RATIO identical)", R90))
wbar90 <- wbar90[!is.na(wbar90$ymin) & !is.na(wbar90$ymax), ]
m90 <- match(et[has_bar], key_of(wbar90$x))
ctr <- cy[has_bar]
top90 <- (1 - R90) * ctr + R90 * top; bot90 <- (1 - R90) * ctr + R90 * bot
w_top90 <- pmin(-wbar90$ymin, -wbar90$ymax)[m90]; w_bot90 <- pmax(-wbar90$ymin, -wbar90$ymax)[m90]
check(nrow(wbar90) == 12L && !anyNA(m90) && !anyDuplicated(key_of(wbar90$x)) &&
        identical(wbar90$x[m90], cx[has_bar]) &&
        isTRUE(all.equal(w_top90, top90, tolerance = 1e-12)) &&
        isTRUE(all.equal(w_bot90, bot90, tolerance = 1e-12)) &&
        isTRUE(all.equal((ctr - w_top90) / (ctr - top), rep(R90, 12), tolerance = 1e-12)) &&
        isTRUE(all.equal((w_bot90 - ctr) / (bot - ctr), rep(R90, 12), tolerance = 1e-12)),
      "wage: each 90% bar = centre + qnorm(0.95)/1.96 x (saved 95% endpoint - centre), both sides (12 bars; none at e = -1)")
check(all(w_top90 > top & w_bot90 < bot & w_top90 < ctr & w_bot90 > ctr),
      "wage: every 90% bar lies strictly inside its 95% bar and contains the centre")
check(!isTRUE(all.equal(w_top90, top, tolerance = 1e-12)) &&
        !isTRUE(all.equal(w_top90, rev(top90), tolerance = 1e-12)),
      "wage: 90% check rejects bars equal to the 95% endpoints and a permuted copy")
check(!any(is.finite(wage$lo95[wage$event_time == -1]), is.finite(wage$hi95[wage$event_time == -1]),
           is.finite(wage$lo90[wage$event_time == -1]), is.finite(wage$hi90[wage$event_time == -1])) &&
        !any(key_of(wbar$x) == -1L) && !any(key_of(wbar90$x) == -1L),
      "wage: e = -1 reference has NA 95% and 90% bounds and no drawn bar")
hol <- vapply(gj$markers, function(m) isTRUE(m$hollow), TRUE)
check(identical(et[hol], as.integer(unlist(gj$hollow_markers_at_event_time))) &&
        identical(et[hol], c(-6:-1, 1L)) &&
        identical(wpt$fill[m] == "white", hol) && all(wpt$fill[m][!hol] == "#0072B2"),
      "wage: hollow (white) at e = -6..-1 and 1 as in the original; others filled #0072B2")
pp <- wb$layout$panel_params[[1]]
wy_c <- vapply(gj$y_tick_centres_px, as.numeric, 1); pb <- gj$panel_bounds_px
check(identical(pp$x.range, as.numeric(c(pb$x0, pb$x1))) && identical(-rev(pp$y.range), as.numeric(c(pb$y0, pb$y1))) &&
        identical(as.numeric(pp$x$get_breaks()), unname(wx_c)) && identical(pp$x$get_labels(), as.character(-6:6)) &&
        identical(-as.numeric(pp$y$get_breaks()), unname(wy_c)) &&
        identical(pp$y$get_labels(), c("120", "80", "40", "0", "-40")),
      "wage: panel = source bounds x 120..1546, y 126..931 (expand 0); saved tick centres with original labels")
onp <- vapply(gj$onset_line_cols_profile, as.numeric, 1)
check(identical(-wl("GeomHline")$yintercept, wy_c[["0"]]) &&
        identical(wl("GeomVline")$xintercept, sum(as.numeric(names(onp)) * onp) / sum(onp)),
      "wage: zero line at saved y tick '0'; onset at weighted centroid of saved onset profile")
check(identical(sort(names(wage)), sort(c("event_time", "px_x", "est", "lo95", "hi95", "lo90", "hi90", "hollow"))),
      "wage: plotted data are image coordinates only (centre, 95% and derived 90% endpoints; no coefficient/SE columns)")
wcap <- notes_text(p_wage)
check(!grepl("ATT|SE|39\\.73|13\\.047|14\\.329|18\\.721", wcap),
      "wage: explanatory Notes print no 'ATT'/SE and no unrounded 39.731 (line 3 shows the saved ATT rounded, 39.7***); no substituted SE/ATT")

# ---- 4. reference template and wording ----------------------------------------
el <- function(p, k) calc_element(k, p$theme)
tmpl_ok <- function(p) {
  t <- function(k, size, colour = NULL, hjust = NULL) {
    e <- el(p, k); isTRUE(all.equal(e$size, size)) && identical(e$family, "serif") &&
      (is.null(colour) || identical(e$colour, colour)) && (is.null(hjust) || identical(e$hjust, hjust))
  }
  mg <- p$theme$plot.margin
  t("plot.title", 24, hjust = 0.5) && identical(el(p, "plot.title")$face, "plain") &&
    is.null(p$labels$subtitle) && t("axis.title.x", 16) && t("axis.title.y", 16) &&
    t("axis.text.x", 13, "black") && t("axis.text.y", 13, "black") && t("legend.text", 13) &&
    t("plot.caption", 12, "grey15", 0) && identical(el(p, "plot.caption")$lineheight, 1.15) &&
    identical(as.numeric(mg), c(8, 12, 8, 24)) && identical(unique(grid::unitType(mg)), "points") &&
    inherits(el(p, "panel.grid.major"), "element_blank") &&
    identical(el(p, "panel.background")$fill, "white") &&
    identical(el(p, "axis.line.x")$colour, "black") && isTRUE(all.equal(el(p, "axis.line.x")$linewidth, 0.35)) &&
    identical(p$theme$legend.position, "bottom") && inherits(p$theme$legend.title, "element_blank")
}
lines_ok <- function(p) {
  h <- p$layers[[layer_idx(p, "GeomHline")]]; v <- p$layers[[layer_idx(p, "GeomVline")]]
  identical(h$aes_params$colour, "#4D4D4D") && identical(v$aes_params$colour, "#8C8C8C") &&
    identical(h$aes_params$linetype, "dashed") && identical(v$aes_params$linetype, "dashed") &&
    h$aes_params$linewidth == 0.4 && v$aes_params$linewidth == 0.4
}
pt_ok <- function(p, single) {
  l <- p$layers[[layer_idx(p, "GeomPoint")]]; ap <- l$aes_params
  ap$size == 2.0 && ap$stroke == 0.4 && identical(ap$colour, "#262626") &&
    (!single || identical(ap$shape, 21))
}
bar_col_single <- function(p) all(vapply(p$layers[layer_idx(p, "GeomLinerange")],
                                         function(l) identical(l$aes_params$colour, "#72B1D4"), TRUE))
for (nm in c("p_gap", "p_up", "p_bt", "p_wage")) {
  p <- get(nm)
  check(tmpl_ok(p), sprintf("%s: theme (serif 24/16/13/13/12 pt title/axis/ticks/legend/Notes, no subtitle, grey15 Notes, lineheight 1.15, margins 8/12/8/24 pt, no grid, black 0.35 axes)", nm))
  check(lines_ok(p), sprintf("%s: zero line #4D4D4D and onset #8C8C8C, dashed 0.4", nm))
  check(pt_ok(p, nm != "p_bt"), sprintf("%s: points size 2.0, stroke 0.4, border #262626%s", nm,
                                         if (nm != "p_bt") ", circle 21" else ""))
}
check(bar_col_single(p_gap) && bar_col_single(p_up) && bar_col_single(p_wage),
      "single series (gap, UP, wage): interval layers #72B1D4")
bt_scales <- ggplot_build(p_bt)$plot$scales
sv <- function(a) { sc <- bt_scales$get_scales(a); unname(sc$palette(2)) }
check(identical(sv("fill"), c("#0072B2", "#D55E00")) && identical(sv("colour"), c("#72B1D4", "#E7A672")) &&
        identical(as.numeric(sv("shape")), c(21, 24)) &&
        all(vapply(c("colour", "fill", "shape"), function(a) {
          sc <- bt_scales$get_scales(a); is.null(sc$name) && identical(sc$get_labels(), c("Public", "Charter")) }, TRUE)),
      "by type: Public circle #0072B2 / CI #72B1D4, Charter triangle #D55E00 / CI #E7A672; legend without title")

lab_is <- function(p, want) all(vapply(names(want), function(k)
  identical(if (k == "title") unwrap(p$labels[[k]]) else p$labels[[k]], want[[k]]), TRUE))
# Explanatory Notes: exactly three explicit lines (line 1 starts "Notes: ";
# line 3 = authored treatment-effect reading with stars and percent magnitude,
# exact text, no p-threshold legend; numbers checked in 7).
line3 <- list(
  wage = "Male graduates earn €39.7*** more per month on average after the first offer (+3.9% of the €1,030 control mean).",
  gap  = "The estimated average reduction is 17.1** crimes per 1,000, equivalent to 37.0% of the full-panel mean gap (46.2 per 1,000).",
  up   = "Pooled 2019–2024 effect: +0.43** pupils per pupil needed to meet the quota, equivalent to 43.0% of the initial quota gap.",
  bt   = "Pooled 2019–2024 estimates: public +1.16*** pupils (115.9% of the initial quota gap); charter +0.41* pupils (41.2%).")
up_line2 <- paste("Values are per extra pupil needed to meet a school's quota, relative to 2018.",
                  "Only schools initially below quota are shown.")
notes_are <- function(p, l1, l2, l3) identical(p$labels$caption, paste(paste("Notes:", l1), l2, l3, sep = "\n"))
no_sub <- function(p) is.null(p$labels$subtitle)
check(no_sub(p_gap) && lab_is(p_gap, list(
  title = "Youth–Adult Crime Gap",
  y = "Effect on Crime-Rate Gap (per 1,000)", x = "Years relative to dual-VET adoption")) &&
  notes_are(p_gap,
    "Dots show the estimated effect of company-based vocational training on the crime-rate gap between young people (16–25) and adults (36–45).",
    "Year 0 marks local adoption. Values below zero indicate a smaller gap than in year -1, in crimes per 1,000 residents.",
    line3$gap),
  "crime gap: outcome title, no subtitle, axis labels; exact 3-line explanatory Notes (ages 16-25 vs 36-45, year 0 adoption, ref year -1, per 1,000)")
check(no_sub(p_up) && lab_is(p_up, list(
  title = "Vulnerable Student Enrollment",
  y = "Effect on Vulnerable Enrollment (Students)", x = "Year")) &&
  notes_are(p_up,
    "Barcelona reserves preschool seats to reduce school segregation. Dots show the estimated change in vulnerable children's enrollment.",
    up_line2, line3$up),
  "UP: outcome title, no subtitle, axis labels; exact 3-line explanatory Notes (reserved seats, per extra pupil to quota, ref 2018, initially below quota)")
check(no_sub(p_bt) && lab_is(p_bt, list(
  title = "Vulnerable Student Enrollment by School Type",
  y = "Effect on Vulnerable Enrollment (Students)", x = "Year")) &&
  notes_are(p_bt,
    "Dots show how Barcelona's seat quotas affect vulnerable children's enrollment in public and publicly funded private (charter) preschools.",
    up_line2, line3$bt),
  "by type: outcome title, no subtitle, axis labels; exact 3-line explanatory Notes (public vs charter, per extra pupil to quota, ref 2018)")
check(no_sub(p_wage) && lab_is(p_wage, list(
  title = "Monthly Earnings",
  y = "Effect on Monthly Earnings (EUR)", x = "Event time (years relative to dual adoption)")) &&
  notes_are(p_wage,
    "Dots show the estimated effect of offering company-based vocational training in a school program on male graduates' monthly earnings, in euros.",
    "Year 0 marks the first offer. Values are relative to the year before that offer; positive values indicate higher earnings.",
    line3$wage),
  "wage: outcome title, no subtitle, axis labels; exact 3-line explanatory Notes (male graduates, first program offer, ref year before offer, euros)")
four <- list(p_gap, p_up, p_bt, p_wage)
title_lines <- lapply(four, function(p) strsplit(p$labels$title, "\n")[[1]])
check(!any(grepl("Event Study", vapply(four, function(p) p$labels$title, ""), fixed = TRUE)),
      "titles: no ': Event Study' suffix")
check(all(vapply(seq_along(four), function(j) {
  l <- title_lines[[j]]
  length(l) <= 2L && all(nchar(l) <= TITLE_WIDTH) &&
    identical(l, strwrap(unwrap(four[[j]]$labels$title), TITLE_WIDTH)) }, TRUE)) &&
    TITLE_PT == 24 && TITLE_WIDTH == 70,
  sprintf("titles: uniform 24 pt, word-wrapped at <= 70 characters, at most 2 lines (lines %s)",
          paste(lengths(title_lines), collapse = "/")))
# Rendered widths (ragg, serif, as in save_fig) of every title line at 24 pt
# and every Notes line at 12 pt must fit the 11 in canvas minus the 12 + 24 pt
# plot margins (strict bound, without the renderer's 0.15 in allowance).
avail_in <- W_IN - 36 / 72
title_w_in <- max(text_width_in(unlist(title_lines), TITLE_PT))
check(title_w_in < avail_in,
      sprintf("titles: widest 24 pt line %.2f in < %.2f in available width (no horizontal clipping)",
              title_w_in, avail_in))
note_split <- lapply(four, function(p) strsplit(p$labels$caption, "\n", fixed = TRUE)[[1]])
note_lines <- unlist(note_split)
note_w <- text_width_in(note_lines, NOTES_PT)
cat(sprintf("  Notes line %d.%d: %.3f in\n", rep(seq_along(four), lengths(note_split)),
            sequence(lengths(note_split)), note_w), sep = "")
check(NOTES_PT == 12 && all(lengths(note_split) == 3L) &&
        all(vapply(note_split, function(l) startsWith(l[1], "Notes: ") && !any(grepl("Notes:", l[-1])) &&
                     endsWith(l[3], ".") && !any(grepl("p ?<|p-value", l)), TRUE)) &&
        identical(vapply(note_split, `[`, "", 3), unname(unlist(line3[c("gap", "up", "bt", "wage")]))) &&
        !any(grepl("Bars show uncertainty", note_lines, fixed = TRUE)) &&
        !any(grepl("STARS_LEGEND|p<0\\.", sub("#.*$", "", readLines(file.path(fig_here, "02_render_figures.R"), encoding = "UTF-8")))),
      "Notes: 12 pt, exactly 3 explicit lines per figure; 'Notes:' prefix on line 1 only; line 3 = effect + stars + percent; no p-threshold legend on any line or in renderer code (no bars line)")
w3 <- note_w[cumsum(lengths(note_split))]
check(all(w3 <= TEXT_W_IN),
      sprintf("Notes line 3 rendered widths at 12 pt (gap/up/bt/wage %s in) <= %.2f in",
              paste(sprintf("%.2f", w3), collapse = "/"), TEXT_W_IN))
check(all(note_w < avail_in) && all(note_w <= TEXT_W_IN),
      sprintf("Notes: every rendered 12 pt line fits (widest %.2f in <= %.2f in renderer width < %.2f in available; no right clipping, no 4th line)",
              max(note_w), TEXT_W_IN, avail_in))
note_body <- note_lines
check(!any(grepl("ATT|\\bSE\\b|p ?[=<]|n ?= ?[0-9]|Callaway|Sant'Anna|NESE|pre-avg|post-avg|1\\.259|0\\.399|1\\.26|0\\.40\\b", note_body)),
      "Notes: no technical statistics (ATT, SE, p-values, school counts, estimator names) and no dynamic-mean numbers (1.259/0.399) on the charts")
all_text <- unlist(lapply(four, function(p) unlist(p$labels)))
check(!any(grepl("FUENTE|NOTAS|pixel|px|source_|centre_xy|bar_core", all_text)),
      "no technical FUENTE/NOTAS footer text or implementation/source-pixel terms on the charts")
src <- readLines(file.path(fig_here, "02_render_figures.R"), encoding = "UTF-8")
code <- sub("#.*$", "", src)
# The only authorised 1.96 is the denominator of WAGE90_RATIO (the historical
# producer's 95% multiplier); any other 1.96 or qnorm(0.975) would be a 95% recompute.
l196 <- grep("1\\.96", code)
check(!any(grepl("qnorm\\(0\\.975\\)", code)) && sum(grepl("qnorm\\(0\\.95\\)", code)) == 1L &&
        length(l196) == 1L && grepl("^WAGE90_RATIO <- Z90 / 1\\.96\\s*$", code[l196]) &&
        length(grep("WAGE90_RATIO", code)) == 3L,
      "renderer never recomputes 95% bounds; qnorm(0.95) once; 1.96 only as WAGE90_RATIO denominator (wage 90% scaling)")

# ---- 5. PNG size/dpi, change vs immutable baseline, site copies, CSS --------
# (BASELINE and git_blob are defined at the top.)
be32 <- function(b) sum(as.integer(b) * 256^(3:0))
png_dim <- function(f) { con <- file(f, "rb"); on.exit(close(con)); readBin(con, "raw", 16)
  h <- readBin(con, "raw", 8); c(be32(h[1:4]), be32(h[5:8])) }
# pixels per inch from the pHYs chunk (unit 1 = metre); NA if absent
png_dpi <- function(f) {
  r <- readBin(f, "raw", file.info(f)$size); i <- 9L
  while (i + 8L <= length(r)) {
    len <- be32(r[i:(i + 3L)]); typ <- rawToChar(r[(i + 4L):(i + 7L)])
    if (typ == "pHYs") { d <- r[(i + 8L):(i + 16L)]
      return(if (as.integer(d[9]) == 1L) round(c(be32(d[1:4]), be32(d[5:8])) * 0.0254) else NA) }
    if (typ == "IDAT") break
    i <- i + 12L + len
  }
  NA
}
check(W_IN == 11 && H_IN == 7.5 && DPI == 300, "renderer canvas 11 x 7.5 in at 300 dpi")
owned <- c("crime_youth_adult_gap_centered.png", "reshuffling_up.png", "reshuffling_by_type.png",
           "crime_monthly_earnings_large.png")
for (f in owned) {
  p <- file.path(repo, "img", f)
  check(identical(png_dim(p), c(3300, 2250)), sprintf("%s is 3300 x 2250", f))
  check(identical(png_dpi(p), c(300, 300)), sprintf("%s records 300 dpi (pHYs)", f))
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
css_rule <- function(f) {
  x <- paste(readLines(file.path(repo, f), warn = FALSE), collapse = "\n")
  m <- regmatches(x, regexpr("\\.paper-figures img \\{[^}]*\\}", x)); if (length(m)) m else ""
}
rules <- vapply(c("css/style.css", "static/css/style.css", "public/css/style.css"), css_rule, "")
check(all(grepl("aspect-ratio: 22 / 15;", rules, fixed = TRUE)) &&
        all(grepl("object-fit: contain;", rules, fixed = TRUE)) &&
        all(grepl("background-color: #ffffff;", rules, fixed = TRUE)) &&
        length(unique(rules)) == 1L,
      ".paper-figures img: aspect-ratio 22 / 15, object-fit contain, white background, same in 3 CSS files")

# ---- 6. caption numbers vs numbers printed on the original figures -----------
check(identical(sprintf("%+.3f", c(avg("Public", 2013:2018), avg("Public", 2019:2024),
                                   avg("Charter", 2013:2018), avg("Charter", 2019:2024))),
                c("+0.057", "+1.259", "-0.029", "+0.399")),
      "by type: archived pre/post averages reproduce original printed caption (+0.057, +1.259, -0.029, +0.399)")
check(identical(as.integer(n_by[c("Public", "Charter")]), c(158L, 153L)) && up$n_schools[1] == 311,
      "archived school counts reproduce originals (UP 311; public 158; charter 153)")
check(identical(c(sprintf("%.1f", as.numeric(agg$post_avg_att)), agg$post_avg_p,
                  sprintf("%.2f", as.numeric(agg$pretest_wald_p))), c("-17.1", "0.011", "0.84")),
      "crime gap: archived post average / p / pre-test round to original subtitle (-17.1, 0.011, 0.84)")

# ---- 7. third-line effects: caption_effects.json, sources, numbers, stars ------
ce <- fromJSON(file.path(data_dir, "caption_effects.json"), simplifyVector = FALSE)
# Projected wage / mfx rows expose exactly the caption-input columns (no extra fields).
WAGE_COLS <- c("var", "label", "arm", "csdid", "csdid_se", "csdid_p", "ctrl_mean", "n_obs", "G")
MFX_COLS <- c("dose", "mfx", "pct_of_mean")
ce_rows <- list(pooled = ce$enrollment_pooled$row, Public = ce$enrollment_by_type$rows$Public,
                Charter = ce$enrollment_by_type$rows$Charter)
ce_src <- list(pooled = ce$enrollment_pooled$source, bytype = ce$enrollment_by_type$source)
CE_SHA <- c(pooled = "c0855ad40ac64b798d28864c90ecfda829a23201abf533bf02c6e2cba6bd3bac",
            bytype = "80891ff0d8a984b33ecea2271457c8d047c6fc2c7d532303ff09f66a90c9165d")
filt <- list(arm = "published", stage = "inf1", kind = "number", outcome = "n_nese_b",
             treatment = "did_nb", sign_group = "UP")
check(identical(vapply(ce_src, `[[`, "", "sha256"), CE_SHA) &&
        all(vapply(ce_rows, function(r) all(vapply(names(filt), function(k) identical(r[[k]], filt[[k]]), TRUE)), TRUE)) &&
        identical(c(ce_rows$Public$school_type, ce_rows$Charter$school_type), c("Public", "Charter")) &&
        all(vapply(ce_rows, function(r) all(vapply(r, is.character, TRUE)), TRUE)),
      "caption_effects.json: recorded source SHA-256 c0855ad40ac6 / 80891ff0d8a9; rows carry the selection filters; values stored as text")
ce_path <- function(k) file.path(dropbox, sub("^<Dropbox>/", "", ce_src[[k]]$path))
if (all(file.exists(vapply(names(ce_src), ce_path, "")))) {
  rdc <- function(p) read.csv(p, colClasses = "character", na.strings = character(0))
  sel <- function(s, type = NULL) {
    k <- Reduce(`&`, Map(function(col, v) s[[col]] == v, names(filt), filt))
    if (!is.null(type)) k <- k & s$school_type == type
    s[k, , drop = FALSE]
  }
  s1 <- rdc(ce_path("pooled")); s3 <- rdc(ce_path("bytype"))
  same <- function(df, r) nrow(df) == 1L && identical(names(df), names(r)) && identical(unname(unlist(df[1, ])), unname(unlist(r)))
  check(identical(unname(vapply(names(ce_src), function(k) digest(file = ce_path(k), algo = "sha256"), "")), unname(CE_SHA)),
        "static DiD sources unchanged (01_static_did_number.csv, 03_static_did_UP_by_school_type.csv sha256)")
  check(same(sel(s1), ce_rows$pooled) && same(sel(s3, "Public"), ce_rows$Public) && same(sel(s3, "Charter"), ce_rows$Charter),
        "caption_effects.json rows identical (as text, unique match) to source rows: pooled UP; UP Public; UP Charter")
  b <- sel(s3, "Both"); cols <- c("est", "se", "pval", "n_obs", "n_schools", "pre_mean")
  check(nrow(b) == 1L && identical(unlist(b[1, cols]), unlist(sel(s1)[1, cols])),
        "by-type source 'Both' row equals the pooled 01 UP row (same model and sample)")
  # Vocational baseline-archive rows (wage; crime ATT; crime full-panel mean gap).
  VOC_SHA <- c(wage = "2c8da53d23c1eba0b3314d754b9a4aed880d727f0f112fdd72b1db1ba4b343a0",
               crime = "7c2c1839ab6b02d3f1b4bb5b89ff3e54cd09bb7016042e46efe459a0532b35bd",
               mfx = "155ce440e76f29c33572efb7b9e09a23fe2265dd7603c1ac0a16f80b1dc9464d")
  voc_src <- list(wage = ce$wage$source, crime = ce$crime$source, mfx = ce$crime$denominator$source)
  voc_path <- function(k) file.path(dropbox, sub("^<Dropbox>/", "", voc_src[[k]]$path))
  if (all(file.exists(vapply(names(voc_src), voc_path, "")))) {
    rdv <- function(k) read.csv(voc_path(k), colClasses = "character", na.strings = character(0), check.names = FALSE)
    check(identical(unname(vapply(names(voc_src), function(k) digest(file = voc_path(k), algo = "sha256"), "")), unname(VOC_SHA)),
          "wage/crime caption sources unchanged (survey_results_full.csv 2c8da53d23c1, tab_main_ddd.csv 7c2c1839ab6b, mfx_levels_ddd.csv 155ce440e76f)")
    sw <- rdv("wage"); sw <- sw[sw$var == "wage_cont" & sw$arm == "quality", , drop = FALSE]
    sc <- rdv("crime"); sc <- sc[sc$estimator == "csdid (Callaway-Sant'Anna, never-treated)" & sc$treatment == "binary adoption", , drop = FALSE]
    sm <- rdv("mfx")
    # Wage row and mfx rows are column PROJECTIONS of the source rows (only the
    # caption inputs); the crime ATT row stays a full-row copy.
    same_proj <- function(df, r, cols) nrow(df) == 1L && identical(names(r), cols) &&
      all(cols %in% names(df)) && identical(unname(unlist(df[1, cols])), unname(unlist(r)))
    check(same(sc, ce$crime$row) &&
            same_proj(sw, ce$wage$row, WAGE_COLS) &&
            nrow(sm) == length(ce$crime$denominator$rows) &&
            all(vapply(seq_len(nrow(sm)), function(i) same_proj(sm[i, , drop = FALSE], ce$crime$denominator$rows[[i]], MFX_COLS), TRUE)),
          "caption_effects.json crime ATT row (csdid never-treated) identical (as text, unique, full row) to source; wage row (wage_cont/quality) and six mfx rows equal (as text, in order) the source projections on the selected columns")
  } else cat("SKIP wage/crime caption source re-check: Vocational baseline tables not reachable\n")
  tex <- paste(readLines(src_path("crime_gap_agg"), warn = FALSE), collapse = "\n")
  check(grepl("ATT (post average) & -17.061** (6.697)", tex, fixed = TRUE),
        "crime source table prints the post average as -17.061** (6.697)")
} else cat("SKIP caption source re-check: Dropbox static DiD sources not reachable\n")
# Independent star rule (left-closed intervals: p = 0.01 is **, not ***).
star_ref <- function(p) c("***", "**", "*", "")[findInterval(p, c(0.01, 0.05, 0.10)) + 1L]
bnd <- c(0.0099999, 0.01, 0.0499999, 0.05, 0.0999999, 0.10, 0.5)
check(identical(vapply(bnd, stars_of, ""), star_ref(bnd)) &&
        identical(star_ref(bnd), c("***", "**", "**", "*", "*", "", "")),
      "stars: renderer rule = independent rule at thresholds (p < .01 ***, < .05 **, < .10 *; boundaries strict)")
pv <- vapply(ce_rows, function(r) as.numeric(r$pval), 1); es <- vapply(ce_rows, function(r) as.numeric(r$est), 1)
check(identical(star_ref(pv), c("**", "***", "*")) &&
        identical(sprintf("%+.2f%s", es, star_ref(pv)), c("+0.43**", "+1.16***", "+0.41*")) &&
        grepl("+0.43**", line3$up, fixed = TRUE) && grepl("public +1.16*** pupils", line3$bt, fixed = TRUE) &&
        grepl("charter +0.41* pupils", line3$bt, fixed = TRUE),
      sprintf("enrollment: printed +0.43** / +1.16*** / +0.41* follow from saved est and unrounded p (%.4g, %.3g, %.4g)",
              pv[1], pv[2], pv[3]))
# Quota percent = 100 * beta (beta is pupils per pupil of the initial quota gap
# D, so beta * D / D = beta); explicitly not beta / pre_mean.
pq <- 100 * es; pre <- vapply(ce_rows, function(r) as.numeric(r$pre_mean), 1)
check(identical(sprintf("%.1f%%", pq), c("43.0%", "115.9%", "41.2%")) &&
        grepl("43.0% of the initial quota gap", line3$up, fixed = TRUE) &&
        grepl("+1.16*** pupils (115.9% of the initial quota gap)", line3$bt, fixed = TRUE) &&
        grepl("+0.41* pupils (41.2%)", line3$bt, fixed = TRUE) &&
        !any(vapply(sprintf("%.1f%%", 100 * es / pre), function(x) grepl(x, paste(line3, collapse = " "), fixed = TRUE), TRUE)) &&
        !any(grepl("enrollment", c(line3$up, line3$bt), ignore.case = TRUE)),
      sprintf("enrollment: percent = 100 x saved beta (%.6f / %.6f / %.6f) of the initial quota gap; not beta / pre_mean", pq[1], pq[2], pq[3]))
check(identical(names(ce$wage$row), WAGE_COLS) &&
        length(ce$crime$denominator$rows) == 6L &&
        all(vapply(ce$crime$denominator$rows, function(r) identical(names(r), MFX_COLS), TRUE)) &&
        all(vapply(c(ce$wage$row, unlist(ce$crime$denominator$rows, recursive = FALSE)), is.character, TRUE)),
      "caption_effects.json: wage row has exactly var,label,arm,csdid,csdid_se,csdid_p,ctrl_mean,n_obs,G; each of 6 mfx rows exactly dose,mfx,pct_of_mean; values stored as text")
cr <- ce$crime$row; cest <- as.numeric(cr$est); cpv <- as.numeric(cr$p)
check(identical(c(cr$est, cr$se, cr$p, cr$pretrend_p),
                c("-17.061055386083886", "6.696800686456225", "0.010845348670942416", "0.83721")) &&
        identical(c(sprintf("%.3f", c(cest, as.numeric(cr$se), cpv)), sprintf("%.3f", as.numeric(cr$pretrend_p))),
                  c(agg$post_avg_att, agg$post_avg_se, agg$post_avg_p, agg$pretest_wald_p)) &&
        identical(sprintf("%.1f%s", -cest, star_ref(cpv)), "17.1**") &&
        grepl("reduction is 17.1**", line3$gap, fixed = TRUE),
      sprintf("crime: exact saved ATT row (-17.061055, p %.6f) rounds to unchanged crime_gap_aggregate.json (-17.061/6.697/0.011/0.837); 17.1**", cpv))
mrows <- ce$crime$denominator$rows
mg <- vapply(mrows, function(r) 100 * as.numeric(r$mfx) / as.numeric(r$pct_of_mean), 1)
cpct <- 100 * abs(cest) / mg[1]
check(length(mg) == 6L && max(abs(mg - mg[1])) < 1e-10 && abs(mg[1] - 46.17016395309781) < 1e-10 &&
        isTRUE(all.equal(as.numeric(ce$crime$denominator$mean_gap), mg[1], tolerance = 1e-14)) &&
        abs(cpct - 36.95255534) < 1e-8 && identical(sprintf("%.1f", c(cpct, mg[1])), c("37.0", "46.2")) &&
        grepl("37.0% of the full-panel mean gap (46.2 per 1,000)", line3$gap, fixed = TRUE) &&
        !any(vapply(mrows, function(r) grepl(sprintf("%.1f", abs(as.numeric(r$mfx))), line3$gap, fixed = TRUE), TRUE)),
      sprintf("crime: full-panel mean gap 100 x mfx / pct_of_mean = %.10f in all 6 saved rows (spread %.1e); 100 x |main ATT| / mean = %.8f%% -> 37.0%% (descriptive benchmark; numerator is the main ATT, no mfx)",
              mg[1], diff(range(mg)), cpct))
wr <- ce$wage$row; wpv <- as.numeric(wr$csdid_p); wpct <- 100 * as.numeric(wr$csdid) / as.numeric(wr$ctrl_mean)
check(identical(c(wr$var, wr$arm, wr$csdid, wr$csdid_se, wr$csdid_p, wr$ctrl_mean, wr$n_obs, wr$G),
                c("wage_cont", "quality", "39.7308163126299", "13.0468925248729", "0.00232500785676238",
                  "1030.05280139392", "13570", "454")) &&
        is.null(ce$wage[["p", exact = TRUE]]) && is.null(ce$wage[["p_note", exact = TRUE]]),
      "wage: exact saved row wage_cont/quality (csdid, csdid_se, csdid_p, ctrl_mean, n_obs 13570, G 454); no retired p: null field")
op <- ce$wage$original_printed
check(identical(c(op$printed_att, op$printed_stars, op$printed_se), c("39.731", "***", "13.047")) &&
        grepl(WAGE_SRC_SHA, op$source, fixed = TRUE) &&
        identical(sprintf("%.3f", as.numeric(c(wr$csdid, wr$csdid_se))), c(op$printed_att, op$printed_se)) &&
        identical(star_ref(wpv), op$printed_stars) &&
        grepl("€39.7***", line3$wage, fixed = TRUE),
      sprintf("wage: saved csdid/csdid_se round to the original printed 39.731/13.047; *** from unadjusted csdid_p %.6f (= printed stars)", wpv))
check(abs(wpct - 3.8571630754) < 1e-9 && identical(sprintf("%.1f", wpct), "3.9") &&
        identical(formatC(as.numeric(wr$ctrl_mean), format = "d", big.mark = ","), "1,030") &&
        grepl("(+3.9% of the €1,030 control mean)", line3$wage, fixed = TRUE),
      sprintf("wage: 100 x csdid / ctrl_mean = %.10f%% -> +3.9%% of the EUR 1,030 control mean", wpct))
check(!any(vapply(unlist(line3), function(l) grepl("1\\.259|0\\.399|1\\.26\\b|0\\.40\\b", l), TRUE)),
      "no stars on the dynamic-point means (1.259 / 0.399); enrollment line 3 uses pooled static DiD rows")

cat(sprintf("\n%d failure(s)\n", fails))
quit(status = if (fails) 1L else 0L)
