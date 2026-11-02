# Render the website event-study figures from the saved aggregate estimates
# in scripts/figures/data/ (see 01_extract_aggregates.py and provenance.json).
#
# Template = the reference paper figure
#   Vocational/5_Package/2_Out/Figures/1_did_offer/01_did_validation/eventstudy_crpc_ctrl.png
#   (make_es_fig() in 01_did_validation.R -> plot_event_study_paper_multi() in _helpers.R),
# saved at 11 x 7.5 in, 300 dpi. The reference PNG is 3300 x 2434 because a
# 184 px technical footer (FUENTE/NOTAS) is appended; the website figures are
# the 3300 x 2250 figure without that footer.
#   serif (Times); title 12 pt regular centred; subtitle 10 pt grey30; axis
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
# saved p < 0.05) do not depend on the 90% bounds.
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
      plot.title       = element_text(size = base_size + 1, hjust = 0.5, face = "plain"),
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
notes_of <- function(text, width = 150)
  paste(strwrap(paste("Notes:", text, BARS_NOTE), width = width), collapse = "\n")

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

ref_lines <- function(onset_x) list(
  geom_hline(yintercept = 0, linetype = "dashed", colour = ZERO_COL, linewidth = REF_LW),
  geom_vline(xintercept = onset_x, linetype = "dashed", colour = ONSET_COL, linewidth = REF_LW))

# Single-series event study (reference slot 1: blue circle). `hollow` marks
# points drawn with a white fill (only where the original encoded p >= 0.05).
plot_single <- function(df, x, onset_x, title, subtitle, xlab, ylab, caption,
                        hollow = rep(FALSE, nrow(df)), breaks = sort(unique(df[[x]]))) {
  df$x <- df[[x]]; df$fillcol <- ifelse(hollow, "white", FILL1)
  ggplot(df, aes(x = x, y = est)) +
    ref_lines(onset_x) +
    geom_linerange(aes(ymin = lo95, ymax = hi95), colour = BAR1, linewidth = LW95, na.rm = TRUE) +
    geom_linerange(aes(ymin = lo90, ymax = hi90), colour = BAR1, linewidth = LW90, na.rm = TRUE) +
    geom_point(aes(fill = I(fillcol)), shape = 21, size = PT_SIZE, colour = PT_BORDER,
               stroke = PT_STROKE) +
    scale_x_continuous(breaks = breaks, limits = range(df$x) + c(-0.5, 0.5), expand = c(0, 0)) +
    labs(title = title, subtitle = subtitle, x = xlab, y = ylab, caption = caption) +
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
  labs(title = "Continuous DiD – Infantil (UP schools by type; published quotas)",
       subtitle = "Outcome: Effect on NESE-B number",
       x = "Year", y = "Effect on NESE-B number",
       caption = notes_of(bt_note)) +
  theme_paper_serif()
save_fig(p_bt, "reshuffling_by_type.png")
