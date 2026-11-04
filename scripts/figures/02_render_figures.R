# Render the four website event-study figures with one ggplot template.
#   * crime gap, pooled UP, UP by type: from the saved aggregate estimates in
#     scripts/figures/data/ (see 01_extract_aggregates.py and provenance.json).
#   * monthly wage: graphical reconstruction from the image coordinates of the
#     original raster (data/original_wage.png), as recorded in
#     data/wage_geometry.json and re-verified by 04_restyle_wage_raster.py. Its
#     event-study estimates were never saved, so the panel is drawn in source
#     pixel units (x right, y down -> scale_y_reverse) with the original tick
#     positions and printed labels. Its 90% bars are a graphical re-expression of
#     the original pointwise normal 95% bars (see section 4). No coefficient or SE
#     is derived from pixels.
#
# Template = the reference paper figure
#   Vocational/5_Package/2_Out/Figures/1_did_offer/01_did_validation/eventstudy_crpc_ctrl.png
#   (make_es_fig() in 01_did_validation.R -> plot_event_study_paper_multi() in _helpers.R),
# saved at 11 x 7.5 in, 300 dpi. The reference PNG is 3300 x 2434 because a
# 184 px technical footer (FUENTE/NOTAS) is appended; the website figures are
# the 3300 x 2250 figure without that footer.
#   serif (Times); title 32 pt regular centred (wrapped at TITLE_WIDTH = 36 chars); subtitle 10 pt grey30; axis
#   titles 11 pt; tick and legend text 8.8 pt; Notes 8.5 pt grey15, line height
#   1.15, left aligned; plot margins 8/12/8/24 pt (t/r/b/l); white, no grid;
#   black axes 0.35 mm; zero line #4D4D4D and onset line #8C8C8C dashed 0.4 mm.
#   Series 1: circle (21) fill #0072B2, intervals #72B1D4; series 2: triangle
#   (24) fill #D55E00, intervals #E7A672 (colours sampled from the reference).
#   Point size 2.0, stroke 0.4, border #262626. Intervals: 95% thin (0.4),
#   90% thick (1.3).
#
# Inference is NOT re-estimated. The 95% bounds are the saved ci_lo/ci_hi
# (ci_lower/ci_upper), copied verbatim (they equal est +/- 1.96 SE in the
# source). The 90% bounds are added as est +/- qnorm(0.95) * saved SE. Reference
# rows keep their saved 0/0 (or NA) bounds. Marker fill rules (UP: filled iff
# saved p < 0.05) do not depend on the 90% bounds. The wage figure has no saved
# SE; its 90% bars are scaled from its 95% bars by WAGE90_RATIO (section 4).
#
# Usage (from the repository root):  Rscript scripts/figures/02_render_figures.R
suppressPackageStartupMessages({
  library(ggplot2)
  library(jsonlite)
})

if (!exists("fig_here")) {
  args <- commandArgs(trailingOnly = FALSE)
  fig_here <- dirname(normalizePath(sub("^--file=", "", args[grep("^--file=", args)])))
}
here <- fig_here
data_dir <- file.path(here, "data")
img_dir  <- normalizePath(file.path(here, "..", "..", "img"))

# ---- shared geometry: 3300 x 2250 px (11 x 7.5 in at 300 dpi) -------------------
W_IN <- 11; H_IN <- 7.5; DPI <- 300
BASE <- 11
Z90  <- qnorm(0.95)            # 1.644854; used only for the added 90% bounds
LW95 <- 0.4; LW90 <- 1.3       # thin 95%, thick 90%
PT_SIZE <- 2.0; PT_STROKE <- 0.4; PT_BORDER <- "#262626"
ZERO_COL <- "#4D4D4D"; ONSET_COL <- "#8C8C8C"; REF_LW <- 0.4
TITLE_PT <- 32; TITLE_WIDTH <- 36   # 32 pt title; 36-char lines (2 lines each) fit the 11 in canvas

pal_fill <- c(Public = "#0072B2", Charter = "#D55E00")   # reference slots 1, 2
pal_bar  <- c(Public = "#72B1D4", Charter = "#E7A672")
pal_shp  <- c(Public = 21, Charter = 24)
FILL1 <- unname(pal_fill[1]); BAR1 <- unname(pal_bar[1])

theme_paper_serif <- function(base_size = BASE) {
  theme_classic(base_size = base_size, base_family = "serif") +
    theme(
      plot.background  = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "white", colour = NA),
      panel.grid       = element_blank(),
      axis.line        = element_line(linewidth = 0.35, colour = "black"),
      axis.ticks       = element_line(linewidth = 0.35, colour = "black"),
      axis.title       = element_text(size = base_size),
      axis.text        = element_text(size = base_size * 0.8, colour = "black"),
      plot.title       = element_text(size = TITLE_PT, hjust = 0.5, face = "plain"),
      plot.subtitle    = element_text(size = base_size - 1, hjust = 0.5, colour = "grey30"),
      plot.caption     = element_text(size = base_size - 2.5, hjust = 0, colour = "grey15",
                                      lineheight = 1.15, margin = margin(t = 10)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      plot.margin      = margin(8, 12, 8, 24),
      legend.position  = "bottom",
      legend.direction = "horizontal",
      legend.title     = element_blank(),
      legend.text      = element_text(size = base_size * 0.8),
      legend.key       = element_blank(),
      legend.margin    = margin(0, 0, 0, 0),
      legend.box.spacing = unit(6, "pt")
    )
}

# Public Notes sentence. Computation (not shown on the charts): thin bars are the
# saved 95% bounds verbatim; thick bars are estimate +/- qnorm(0.95) * saved SE.
BARS_NOTE <- "Bars indicate 90% (thick) and 95% (thin) confidence intervals."
# "Notes:" paragraph, wrapped at 150 characters as in the reference.
notes_of <- function(text, width = 150, bars = BARS_NOTE)
  paste(strwrap(paste("Notes:", text, bars), width = width), collapse = "\n")
# Titles wrapped on word boundaries so a long title never clips at 32 pt.
wrap_title <- function(s, width = TITLE_WIDTH) paste(strwrap(s, width = width), collapse = "\n")

# Saved 95% bounds verbatim; 90% bounds = est +/- qnorm(0.95) * saved SE.
add_ci <- function(df, est, lo, hi, se = "se") {
  df$est  <- df[[est]]; df$lo95 <- df[[lo]]; df$hi95 <- df[[hi]]
  df$lo90 <- df$est - Z90 * df[[se]]; df$hi90 <- df$est + Z90 * df[[se]]
  df
}

save_fig <- function(p, name) {
  if (identical(Sys.getenv("FIG_NO_SAVE"), "1")) return(invisible(NULL))  # used by 03_verify.R
  out <- file.path(img_dir, name)
  ggsave(out, p, width = W_IN, height = H_IN, dpi = DPI, units = "in",
         device = ragg::agg_png, bg = "white")
  message("wrote ", out)
}

ref_lines <- function(onset_x, zero_y = 0) list(
  geom_hline(yintercept = zero_y, linetype = "dashed", colour = ZERO_COL, linewidth = REF_LW),
  geom_vline(xintercept = onset_x, linetype = "dashed", colour = ONSET_COL, linewidth = REF_LW))

# Single-series event study (reference slot 1: blue circle). `hollow` marks
# points drawn with a white fill (only where the original encoded p >= 0.05).
# Optional arguments serve the wage figure: `x_labels`/`x_limits`/`y_scale`/
# `zero_y` set the source-coordinate axes. `ci90 = FALSE` would drop the 90%
# layer; all four figures use the default TRUE. Defaults reproduce the numeric
# figures unchanged.
plot_single <- function(df, x, onset_x, title, subtitle, xlab, ylab, caption,
                        hollow = rep(FALSE, nrow(df)), breaks = sort(unique(df[[x]])),
                        x_labels = waiver(), x_limits = range(df[[x]]) + c(-0.5, 0.5),
                        y_scale = NULL, zero_y = 0, ci90 = TRUE) {
  df$x <- df[[x]]; df$fillcol <- ifelse(hollow, "white", FILL1)
  ggplot(df, aes(x = x, y = est)) +
    ref_lines(onset_x, zero_y) +
    geom_linerange(aes(ymin = lo95, ymax = hi95), colour = BAR1, linewidth = LW95, na.rm = TRUE) +
    (if (ci90) geom_linerange(aes(ymin = lo90, ymax = hi90), colour = BAR1, linewidth = LW90,
                              na.rm = TRUE)) +
    geom_point(aes(fill = I(fillcol)), shape = 21, size = PT_SIZE, colour = PT_BORDER,
               stroke = PT_STROKE) +
    scale_x_continuous(breaks = breaks, labels = x_labels, limits = x_limits, expand = c(0, 0)) +
    y_scale +
    labs(title = wrap_title(title), subtitle = subtitle, x = xlab, y = ylab, caption = caption) +
    theme_paper_serif()
}

# ============================================================================
# 1. Crime: youth-adult gap (Callaway & Sant'Anna, never-treated controls)
# ============================================================================
gap <- read.csv(file.path(data_dir, "crime_gap_es.csv"), na.strings = "NA")
agg <- fromJSON(file.path(data_dir, "crime_gap_aggregate.json"))
gap <- add_ci(gap, "att", "ci_lower", "ci_upper")
gap_note <- sprintf(paste0(
  "Callaway and Sant'Anna event-study estimates with never-treated controls. ",  # estimator == "csdid_nt"
  "The outcome is the gap between the 16–25 and 36–45 crime rates, in crimes per 1,000 residents. ",
  "Estimates are normalized to zero in year -1. ",
  "Post-period average: %.1f per 1,000 (p = %s); pre-trend test p = %.2f."),
  as.numeric(agg$post_avg_att), agg$post_avg_p, as.numeric(agg$pretest_wald_p))
p_gap <- plot_single(
  gap, x = "event_time", onset_x = -0.5,
  title = "Dual VET narrows the youth-adult crime gap",
  subtitle = "Effect on the 16–25 minus 36–45 crime-rate gap.",
  xlab = "Years relative to dual-VET adoption",
  ylab = "Gap, crimes per 1,000 residents",
  caption = notes_of(gap_note))
save_fig(p_gap, "crime_youth_adult_gap_centered.png")

# ============================================================================
# 2. Reshuffling: pooled UP schools (continuous DiD, published quotas)
# ============================================================================
up <- read.csv(file.path(data_dir, "reshuffling_up_es.csv"), na.strings = c("NA", ""))
up <- add_ci(up, "est", "ci_lo", "ci_hi")
# Original marker semantics: filled = saved p < 0.05; hollow otherwise
# (including the 2018 reference year, which has no p-value).
up_sig <- !is.na(up$pval) & up$pval < 0.05
up_note <- sprintf(paste0(
  "Continuous difference-in-differences event-study estimates for UP schools ",
  "(BCN public+charter; n = %d UP schools). Baseline 2016–2018; quota year 2019; ",
  "estimates are relative to the reference year 2018. Filled markers: p < 0.05; hollow markers otherwise."),
  up$n_schools[1])
p_up <- plot_single(
  up, x = "year", onset_x = 2018.5, hollow = !up_sig,
  title = "Continuous DiD – Infantil (published quotas; UP schools)",
  subtitle = "Outcome: Effect on NESE-B number",
  xlab = "Year", ylab = "Effect on NESE-B number",
  caption = notes_of(up_note))
save_fig(p_up, "reshuffling_up.png")

# ============================================================================
# 3. Reshuffling: UP schools by type (two series, reference slots 1-2)
# ============================================================================
bt <- read.csv(file.path(data_dir, "reshuffling_by_type_es.csv"), na.strings = c("NA", ""))
bt <- add_ci(bt, "est", "ci_lo", "ci_hi")
bt$school_type <- factor(bt$school_type, levels = c("Public", "Charter"))
n_by <- tapply(bt$n_schools, bt$school_type, `[`, 1)
avg <- function(t, yrs) mean(bt$est[bt$school_type == t & bt$year %in% yrs])
pre_yrs <- 2013:2018; post_yrs <- 2019:2024   # reproduces the original printed averages
bt_note <- paste0(
  "Continuous difference-in-differences event-study estimates for BCN UP-direction schools, by school type. ",
  "Baseline 2016–2018; quota year 2019; estimates are relative to the reference year 2018. ",
  sprintf("Public: pre-avg %+.3f, post-avg %+.3f (n=%d). Charter: pre-avg %+.3f, post-avg %+.3f (n=%d).",
          avg("Public", pre_yrs), avg("Public", post_yrs), n_by[["Public"]],
          avg("Charter", pre_yrs), avg("Charter", post_yrs), n_by[["Charter"]]))
pos <- position_dodge(width = 0.4)
p_bt <- ggplot(bt, aes(x = year, y = est, group = school_type)) +
  ref_lines(2018.5) +
  geom_linerange(aes(ymin = lo95, ymax = hi95, colour = school_type), linewidth = LW95,
                 position = pos, na.rm = TRUE) +
  geom_linerange(aes(ymin = lo90, ymax = hi90, colour = school_type), linewidth = LW90,
                 position = pos, na.rm = TRUE) +
  geom_point(aes(fill = school_type, shape = school_type), size = PT_SIZE, colour = PT_BORDER,
             stroke = PT_STROKE, position = pos) +
  scale_colour_manual(values = pal_bar, name = NULL) +
  scale_fill_manual(values = pal_fill, name = NULL) +
  scale_shape_manual(values = pal_shp, name = NULL) +
  scale_x_continuous(breaks = 2013:2024, limits = c(2012.5, 2024.5), expand = c(0, 0)) +
  labs(title = wrap_title("Continuous DiD – Infantil (UP schools by type; published quotas)"),
       subtitle = "Outcome: Effect on NESE-B number",
       x = "Year", y = "Effect on NESE-B number",
       caption = notes_of(bt_note)) +
  theme_paper_serif()
save_fig(p_bt, "reshuffling_by_type.png")

# ============================================================================
# 4. Monthly wage: graphical reconstruction from original image coordinates
# ============================================================================
# Source: data/wage_geometry.json, measured from data/original_wage.png
# (sha256 recorded there; re-checked by 04_restyle_wage_raster.py). Units are
# source pixel indices: x to the right, y downward (hence scale_y_reverse).
#   * point  = measured marker-disk centre_xy (13 markers, e = -6..6);
#   * 95% bar = bar_core_rows_top_bottom, the first/last row of the opaque
#     (k >= 70) bar core outside the marker disk. support_rows_top_bottom also
#     contains the 1-4 px anti-aliasing/resampling fringe and is not used. At
#     e = -1 (reference period) the original has no bar (null), so none is drawn;
#     the marker footprint is not treated as an interval;
#   * 90% bar = graphical re-expression of that 95% bar (WAGE90_RATIO below);
#   * hollow = white interior measured in the original (e = -6..-1 and 1);
#   * panel limits = original panel bounds (x 120..1546, y 126..931), expand 0,
#     so every mark keeps its normalized position relative to the original axes;
#   * ticks = measured tick centres with the labels printed on the original;
#   * zero line = measured y tick centre for "0"; onset line = weighted centroid
#     of the measured onset-line column profile.
# The printed labels give the original units; no coefficient or SE is computed
# from these coordinates.
#
# Construction of the original 95% bars (immutable historical producer, read
# only): nested repo Vocational/5_Package, commit
# 96eec106c1d82821daaff2f0b8d0512d99d190fa (11 August 2026), file
# 1_Codes/3_Analysis/08_survey_outcomes.R. Lines 447-458: did::att_gt(...,
# bstrap = TRUE, biters = 1999, cband = FALSE); did::aggte(type = "dynamic");
# out$dyn = (event_time = dy$egt, att = dy$att.egt, se = dy$se.egt). Lines
# 511-517: ci_lower = att - 1.96*se, ci_upper = att + 1.96*se, drawn by
# geom_linerange(aes(ymin = ci_lower, ymax = ci_upper)). Lines 523-529: title,
# subtitle, printed ATT/SE and filename match the original raster. So each 95%
# bar is pointwise normal (Wald) with the bootstrap SE: half-length 1.96*se,
# not a uniform band and not percentile quantiles.
# Hence the pointwise normal 90% bar has half-length qnorm(0.95)*se =
# WAGE90_RATIO * (95% half-length), with WAGE90_RATIO = qnorm(0.95)/1.96
# (0.83921103). Because the y axis is linear in the coefficient, the same ratio
# applies in image coordinates: lo90 = est + r*(lo95 - est), hi90 = est +
# r*(hi95 - est), with est/lo95/hi95 the measured centre and 95% endpoints.
# This is a graphical re-expression at the original raster resolution (endpoint
# precision ~1 source px, about 0.2 EUR on the printed scale); no coefficient or
# SE is recovered, and the 1.96 here is the producer's 95% multiplier, not a
# recomputation of any 95% bound.
WAGE90_RATIO <- Z90 / 1.96
geo <- fromJSON(file.path(data_dir, "wage_geometry.json"), simplifyVector = FALSE)
wm <- geo$markers
null_na <- function(v) if (is.null(v)) c(NA_real_, NA_real_) else as.numeric(unlist(v))
wage <- data.frame(
  event_time = vapply(wm, function(m) as.integer(m$event_time), 1L),
  px_x       = vapply(wm, function(m) as.numeric(m$centre_xy[[1]]), 1),
  est        = vapply(wm, function(m) as.numeric(m$centre_xy[[2]]), 1),
  lo95       = vapply(wm, function(m) null_na(m$bar_core_rows_top_bottom)[1], 1),
  hi95       = vapply(wm, function(m) null_na(m$bar_core_rows_top_bottom)[2], 1),
  hollow     = vapply(wm, function(m) isTRUE(m$hollow), TRUE))
wage$lo90 <- wage$est + WAGE90_RATIO * (wage$lo95 - wage$est)   # NA at e = -1 (no bar)
wage$hi90 <- wage$est + WAGE90_RATIO * (wage$hi95 - wage$est)
wpanel <- vapply(geo$panel_bounds_px[c("x0", "x1", "y0", "y1")], as.numeric, 1)
wx <- vapply(geo$x_tick_centres_px, as.numeric, 1)    # names "-6".."6"
wy <- vapply(geo$y_tick_centres_px, as.numeric, 1)    # names "120".."-40"
onset_prof <- vapply(geo$onset_line_cols_profile, as.numeric, 1)
wage_onset_x <- sum(as.numeric(names(onset_prof)) * onset_prof) / sum(onset_prof)
wage_note <- paste0(
  "Overall ATT: 39.731*** (SE 13.047). e = \u22121 is the normalized base period; ",
  "deeper pre-periods come from later adopters.")
p_wage <- plot_single(
  wage, x = "px_x", onset_x = wage_onset_x, hollow = wage$hollow,
  breaks = unname(wx), x_labels = names(wx), x_limits = unname(wpanel[c("x0", "x1")]),
  y_scale = scale_y_reverse(breaks = unname(wy), labels = names(wy),
                            limits = unname(wpanel[c("y1", "y0")]), expand = c(0, 0)),
  zero_y = wy[["0"]], ci90 = TRUE,
  title = "Callaway-Sant'Anna event study: Monthly Wage (EUR, midpoints)",
  subtitle = "Binary dual-offer adoption | not-yet-treated controls | clustered at school",
  xlab = "Event time (years relative to dual adoption)",
  ylab = "Effect on Monthly Wage (EUR, midpoints)",
  caption = notes_of(wage_note))
save_fig(p_wage, "crime_monthly_earnings_large.png")
