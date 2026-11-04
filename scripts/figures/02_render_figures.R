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
# Geometry/style template = the local paper figure
#   Vocational/5_Package/2_Out/Figures/1_did_offer/01_did_validation/eventstudy_crpc_ctrl.png
#   (make_es_fig() in 01_did_validation.R -> plot_event_study_paper_multi() in _helpers.R),
# saved at 11 x 7.5 in, 300 dpi. The reference PNG is 3300 x 2434 because a
# 184 px technical footer (FUENTE/NOTAS) is appended; the website figures are
# the 3300 x 2250 figure without that footer.
# Text hierarchy follows the author PDF reference (KiVA draft, 1 July 2026,
# Appendix Figure F1, printed p. 55): titles name the outcome only (e.g.
# "Monthly Earnings"; no ": Event Study" suffix, no estimator). The public Notes
# are plain-language explanations for readers who have not read the paper:
# exactly three explicit lines per figure (two figure-specific lines plus a
# third line with the aggregate treatment effect and significance stars, from
# saved aggregates; see effect_line section); other technical statistics (SE,
# p-values, school counts, estimators) are archived in the README, not printed. Point sizes are a web
# adaptation, not a copy of the PDF sizes (see README):
#   serif (Times); title 24 pt regular centred (word-wrapped at TITLE_WIDTH = 70
#   chars, at most 2 lines); no subtitle; axis titles 16 pt; tick and legend
#   text 13 pt; Notes 12 pt grey15, line height 1.15, left aligned, three
#   explicit lines (each measured to fit by 03_verify.R); plot margins
#   8/12/8/24 pt (t/r/b/l); white, no grid;
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
# Web-adaptation font sizes (pt), shared by all four figures.
TITLE_PT <- 24; AXIS_PT <- 16; TICK_PT <- 13; LEGEND_PT <- 13; NOTES_PT <- 12
TITLE_WIDTH <- 70              # title word-wrap width (chars); all titles fit on 1 line
Z90  <- qnorm(0.95)            # 1.644854; used only for the added 90% bounds
LW95 <- 0.4; LW90 <- 1.3       # thin 95%, thick 90%
PT_SIZE <- 2.0; PT_STROKE <- 0.4; PT_BORDER <- "#262626"
ZERO_COL <- "#4D4D4D"; ONSET_COL <- "#8C8C8C"; REF_LW <- 0.4
MARGIN_PT <- c(8, 12, 8, 24)   # t/r/b/l
# Width available to the title and Notes: canvas minus left/right plot margins,
# less a 0.15 in safety allowance against glyph overhang.
TEXT_W_IN <- W_IN - (MARGIN_PT[2] + MARGIN_PT[4]) / 72 - 0.15

pal_fill <- c(Public = "#0072B2", Charter = "#D55E00")   # reference slots 1, 2
pal_bar  <- c(Public = "#72B1D4", Charter = "#E7A672")
pal_shp  <- c(Public = 21, Charter = 24)
FILL1 <- unname(pal_fill[1]); BAR1 <- unname(pal_bar[1])

theme_paper_serif <- function() {
  theme_classic(base_size = AXIS_PT, base_family = "serif") +
    theme(
      plot.background  = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "white", colour = NA),
      panel.grid       = element_blank(),
      axis.line        = element_line(linewidth = 0.35, colour = "black"),
      axis.ticks       = element_line(linewidth = 0.35, colour = "black"),
      axis.title       = element_text(size = AXIS_PT),
      axis.text        = element_text(size = TICK_PT, colour = "black"),
      plot.title       = element_text(size = TITLE_PT, hjust = 0.5, face = "plain",
                                      margin = margin(b = 10)),
      plot.caption     = element_text(size = NOTES_PT, hjust = 0, colour = "grey15",
                                      lineheight = 1.15, margin = margin(t = 10)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      plot.margin      = margin(MARGIN_PT[1], MARGIN_PT[2], MARGIN_PT[3], MARGIN_PT[4]),
      legend.position  = "bottom",
      legend.direction = "horizontal",
      legend.title     = element_blank(),
      legend.text      = element_text(size = LEGEND_PT),
      legend.key       = element_blank(),
      legend.margin    = margin(0, 0, 0, 0),
      legend.box.spacing = unit(6, "pt")
    )
}

# Third Notes line: the aggregate treatment effect with stars, formatted from
# saved aggregates (crime: data/crime_gap_aggregate.json; enrollment: pooled
# static DiD rows in data/caption_effects.json; wage: printed original ATT and
# stars, also recorded there). Stars come from the saved p (never from rounded
# estimates, arithmetic means of dynamic coefficients, or combined point SEs).
# (Bars, not described on the charts: thin = saved 95% bounds verbatim; thick =
# estimate +/- qnorm(0.95) * saved SE.)
STARS_LEGEND <- "* p<0.10, ** p<0.05, *** p<0.01."
stars_of <- function(p) {
  stopifnot(is.numeric(p), length(p) == 1L, is.finite(p), p >= 0, p <= 1)
  if (p < 0.01) "***" else if (p < 0.05) "**" else if (p < 0.10) "*" else ""
}
fmt_eff <- function(row, digits = 2, sign = TRUE)   # row: verbatim text fields est, pval
  paste0(sprintf(paste0(if (sign) "%+." else "%.", digits, "f"), as.numeric(row$est)),
         stars_of(as.numeric(row$pval)))
effects <- fromJSON(file.path(data_dir, "caption_effects.json"), simplifyVector = FALSE)
# Rendered width (in) of each string at `size` pt serif, measured on a temporary
# ragg device (the device used by save_fig); the caller's device is restored.
text_width_in <- function(s, size) {
  prev <- dev.cur(); tmp <- tempfile(fileext = ".png")
  ragg::agg_png(tmp, width = W_IN, height = H_IN, units = "in", res = DPI)
  on.exit({ dev.off(); unlink(tmp); if (prev > 1) dev.set(prev) })
  vapply(s, function(x) grid::convertWidth(grid::grobWidth(grid::textGrob(
    x, gp = grid::gpar(fontsize = size, fontfamily = "serif"))), "in", valueOnly = TRUE), 1)
}
# Greedy word wrap by rendered width: each line is as long as fits TEXT_W_IN.
wrap_rendered <- function(s, size, max_in = TEXT_W_IN) {
  words <- strsplit(s, " ", fixed = TRUE)[[1]]; lines <- character(0); cur <- ""
  for (w in words) {
    cand <- if (nzchar(cur)) paste(cur, w) else w
    if (nzchar(cur) && text_width_in(cand, size) > max_in) { lines <- c(lines, cur); cur <- w }
    else cur <- cand
  }
  paste(c(lines, cur), collapse = "\n")
}
# "Notes:" block at NOTES_PT: exactly three explicit lines (figure-specific
# line1, line2 and the effect line3), no automatic wrapping and no default.
# 03_verify.R measures each rendered line against the available width.
# (wrap_rendered above is no longer used for the Notes.)
notes_of <- function(line1, line2, line3)
  paste(paste("Notes:", line1), line2, line3, sep = "\n")
# Titles wrapped on word boundaries at TITLE_WIDTH characters (03_verify.R
# measures the rendered lines at TITLE_PT and requires <= 2 lines that fit).
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
plot_single <- function(df, x, onset_x, title, xlab, ylab, caption,
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
    labs(title = wrap_title(title), subtitle = NULL, x = xlab, y = ylab, caption = caption) +
    theme_paper_serif()
}

# ============================================================================
# 1. Crime: youth-adult gap (Callaway & Sant'Anna, never-treated controls)
# ============================================================================
gap <- read.csv(file.path(data_dir, "crime_gap_es.csv"), na.strings = "NA")
agg <- fromJSON(file.path(data_dir, "crime_gap_aggregate.json"))
gap <- add_ci(gap, "att", "ci_lower", "ci_upper")
# Public Notes (plain language). Line 3 prints the post-adoption average ATT
# with stars from its saved p (0.011, 3 decimals in the source table; any value
# in [0.0105, 0.0115) gives **). The pre-trend test is archived in the README.
gap_note <- c(
  "Dots show the estimated effect of company-based vocational training on the crime-rate gap between young people (16\u201325) and adults (36\u201345).",
  "Year 0 marks local adoption. Values below zero indicate a smaller gap than in year -1, in crimes per 1,000 residents.",
  paste0("The youth\u2013adult crime-rate gap falls by ",
         sprintf("%.1f", -as.numeric(agg$post_avg_att)), stars_of(as.numeric(agg$post_avg_p)),
         " crimes per 1,000 on average after adoption. ", STARS_LEGEND))
stopifnot(as.numeric(agg$post_avg_att) < 0)   # "falls by" requires a negative ATT
p_gap <- plot_single(
  gap, x = "event_time", onset_x = -0.5,
  title = "Youth\u2013Adult Crime Gap",
  xlab = "Years relative to dual-VET adoption",
  ylab = "Effect on Crime-Rate Gap (per 1,000)",
  caption = notes_of(gap_note[1], gap_note[2], gap_note[3]))
save_fig(p_gap, "crime_youth_adult_gap_centered.png")

# ============================================================================
# 2. Reshuffling: pooled UP schools (continuous DiD, published quotas)
# ============================================================================
# Public Notes line 2 shared by both enrollment figures. Plain-language reading
# of the coefficient: enrolled vulnerable (NESE-B, Infantil) pupils per unit of
# treat_nb (corrected reserved-seat quota minus baseline 2016-18 mean vulnerable
# enrollment), reference year 2018; "initially below quota" approximates the UP
# group (below baseline quota, 0.5 pp band).
UP_LINE2 <- paste("Values are per extra pupil needed to meet a school's quota, relative to 2018.",
                  "Only schools initially below quota are shown.")
up <- read.csv(file.path(data_dir, "reshuffling_up_es.csv"), na.strings = c("NA", ""))
up <- add_ci(up, "est", "ci_lo", "ci_hi")
# Original marker semantics: filled = saved p < 0.05; hollow otherwise
# (including the 2018 reference year, which has no p-value).
up_sig <- !is.na(up$pval) & up$pval < 0.05
up_note <- c(
  "Barcelona reserves preschool seats to reduce school segregation. Dots show the estimated change in vulnerable children's enrollment.",
  UP_LINE2,
  # Pooled static DiD (treat_nb x post, 2019-2024 vs 2013-2018), saved row; not
  # an average of the dynamic points drawn.
  paste0("Pooled post-policy estimate (2019\u20132024): ", fmt_eff(effects$enrollment_pooled$row),
         " pupils per pupil needed to meet the quota. ", STARS_LEGEND))
p_up <- plot_single(
  up, x = "year", onset_x = 2018.5, hollow = !up_sig,
  title = "Vulnerable Student Enrollment",
  xlab = "Year", ylab = "Effect on Vulnerable Enrollment (Students)",
  caption = notes_of(up_note[1], up_note[2], up_note[3]))
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
# Public Notes (plain language). Line 3 prints the pooled static DiD by school
# type (saved rows, with stars from their saved p). The original printed
# pre/post averages of the dynamic points (avg(); no p-value exists for them)
# and school counts (n_by) are archived in the README and checked in 03_verify.R.
bt_note <- c(
  "Dots show how Barcelona's seat quotas affect vulnerable children's enrollment in public and publicly funded private (charter) preschools.",
  UP_LINE2,
  paste0("Pooled 2019\u20132024 gains: ", fmt_eff(effects$enrollment_by_type$rows$Public),
         " pupils in public schools; ", fmt_eff(effects$enrollment_by_type$rows$Charter),
         " in charter schools. ", STARS_LEGEND))
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
  labs(title = wrap_title("Vulnerable Student Enrollment by School Type"),
       subtitle = NULL,
       x = "Year", y = "Effect on Vulnerable Enrollment (Students)",
       caption = notes_of(bt_note[1], bt_note[2], bt_note[3])) +
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
# Public Notes (plain language): historical producer used male graduates
# (sex == 1); first offer = first adoption of dual training by a program within
# a school (cid x dgid x dgsup); reference e = -1. Line 3 prints the overall
# ATT 39.731*** as printed on the original raster (stars as printed; no exact p
# was archived, so none is computed); its SE 13.047 is archived in the README.
wage_note <- c(
  "Dots show the estimated effect of offering company-based vocational training in a school program on male graduates' monthly earnings, in euros.",
  "Year 0 marks the first offer. Values are relative to the year before that offer; positive values indicate higher earnings.",
  paste0("Male graduates earn \u20ac", sprintf("%.1f", as.numeric(effects$wage$printed_att)),
         effects$wage$printed_stars, " more per month on average after the first offer. ", STARS_LEGEND))
p_wage <- plot_single(
  wage, x = "px_x", onset_x = wage_onset_x, hollow = wage$hollow,
  breaks = unname(wx), x_labels = names(wx), x_limits = unname(wpanel[c("x0", "x1")]),
  y_scale = scale_y_reverse(breaks = unname(wy), labels = names(wy),
                            limits = unname(wpanel[c("y1", "y0")]), expand = c(0, 0)),
  zero_y = wy[["0"]], ci90 = TRUE,
  title = "Monthly Earnings",
  xlab = "Event time (years relative to dual adoption)",
  ylab = "Effect on Monthly Earnings (EUR)",
  caption = notes_of(wage_note[1], wage_note[2], wage_note[3]))
save_fig(p_wage, "crime_monthly_earnings_large.png")
