# Render the website event-study figures from the saved aggregate estimates
# in scripts/figures/data/ (see 01_extract_aggregates.py and provenance.json).
#
# Visual style follows Vocational 5_Package/1_Codes/_helpers.R
# (theme_paper_serif / plot_event_study_paper / plot_event_study_paper_multi):
# theme_classic serif 11pt, thin black axes, centred regular titles, no grid,
# grey diamonds for a single series, Okabe-Ito colour + distinct marker per
# series with CI bars lightened 45%, dashed zero and onset lines.
#
# Inference is NOT recomputed and no new interval level is added. The only
# bars drawn are the saved 95% intervals (ci_lo/ci_hi or ci_lower/ci_upper),
# copied verbatim from the source. Titles, axis labels and notes reproduce the
# original website figures (wording, estimands and printed numbers).
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

# ---- shared geometry: 1800 x 1100 px for every figure --------------------------
W_IN <- 7.2; H_IN <- 4.4; DPI <- 250   # 7.2*250 = 1800, 4.4*250 = 1100
BASE <- 11

pal_multi_series <- c("#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00", "#56B4E9")
shp_multi_series <- c(21, 24, 22, 25, 21, 24)
lighten_col <- function(col, f = 0.45) {
  m <- grDevices::col2rgb(col)
  grDevices::rgb(t((1 - f) * m + f * 255), maxColorValue = 255)
}

theme_paper_serif <- function(base_size = BASE) {
  theme_classic(base_size = base_size, base_family = "serif") +
    theme(
      axis.line        = element_line(linewidth = 0.35, colour = "black"),
      axis.ticks       = element_line(linewidth = 0.35, colour = "black"),
      axis.text        = element_text(colour = "black"),
      plot.title       = element_text(size = base_size + 1, hjust = 0.5),
      plot.subtitle    = element_text(size = base_size - 1, hjust = 0.5, colour = "grey30"),
      plot.caption     = element_text(size = base_size - 2.5, hjust = 0, colour = "grey15",
                                      lineheight = 1.15, margin = margin(t = 8)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      plot.margin      = margin(10, 14, 8, 10),
      legend.position  = "bottom",
      legend.title     = element_blank(),
      legend.margin    = margin(0, 0, 0, 0),
      legend.box.spacing = unit(4, "pt")
    )
}

BARS_NOTE <- "Bars show 95% confidence intervals."
# Wrap a caption at `width` characters and append the bars sentence on its own line.
caption_of <- function(text = NULL, width = 125)
  paste(c(if (!is.null(text)) strwrap(text, width = width), BARS_NOTE), collapse = "\n")

# Saved 95% bounds, verbatim (reference rows keep their saved 0/0 or NA bounds).
add_ci <- function(df, est, lo, hi) {
  df$est <- df[[est]]; df$lo95 <- df[[lo]]; df$hi95 <- df[[hi]]
  df
}

save_fig <- function(p, name) {
  if (identical(Sys.getenv("FIG_NO_SAVE"), "1")) return(invisible(NULL))  # used by 03_verify.R
  out <- file.path(img_dir, name)
  ggsave(out, p, width = W_IN, height = H_IN, dpi = DPI, units = "in",
         device = ragg::agg_png, bg = "white")
  message("wrote ", out)
}

# Single-series event study (grey diamonds). `hollow` marks points drawn with a
# white fill (used only where the original figure encoded p >= 0.05).
plot_single <- function(df, x, ref_x, onset_x, title, subtitle, xlab, ylab, caption,
                        hollow = rep(FALSE, nrow(df)), breaks = sort(unique(df[[x]])),
                        x_labels = waiver()) {
  df$x <- df[[x]]; df$fillcol <- ifelse(hollow, "white", "grey35")
  ggplot(df, aes(x = x, y = est)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey30", linewidth = 0.4) +
    geom_vline(xintercept = onset_x, linetype = "dashed", colour = "grey55", linewidth = 0.4) +
    geom_linerange(aes(ymin = lo95, ymax = hi95), colour = "grey45", linewidth = 0.5,
                   na.rm = TRUE) +
    geom_point(aes(fill = I(fillcol)), shape = 23, size = 2.6, colour = "grey15", stroke = 0.45) +
    scale_x_continuous(breaks = breaks, labels = x_labels,
                       limits = range(df$x) + c(-0.5, 0.5), expand = c(0, 0)) +
    labs(title = title, subtitle = subtitle, x = xlab, y = ylab, caption = caption) +
    theme_paper_serif()
}

# ============================================================================
# 1. Crime: youth-adult gap (Callaway & Sant'Anna, never-treated controls)
# ============================================================================
gap <- read.csv(file.path(data_dir, "crime_gap_es.csv"), na.strings = "NA")
agg <- fromJSON(file.path(data_dir, "crime_gap_aggregate.json"))
gap <- add_ci(gap, "att", "ci_lower", "ci_upper")
gap_subtitle <- paste0(
  "Effect on the 16-25 minus 36-45 crime-rate gap.\n",
  sprintf("Post-period average: %.1f per 1,000 (p = %s); pre-trend p = %.2f.",
          as.numeric(agg$post_avg_att), agg$post_avg_p, as.numeric(agg$pretest_wald_p)))
p_gap <- plot_single(
  gap, x = "event_time", ref_x = -1, onset_x = -0.5,
  title = "Dual VET narrows the youth-adult crime gap",
  subtitle = gap_subtitle,
  xlab = "Years relative to dual-VET adoption",
  ylab = "Gap, crimes per 1,000 residents",
  caption = caption_of())
save_fig(p_gap, "crime_youth_adult_gap_centered.png")

# ============================================================================
# 2. Reshuffling: pooled UP schools (continuous DiD, published quotas)
# ============================================================================
up <- read.csv(file.path(data_dir, "reshuffling_up_es.csv"), na.strings = c("NA", ""))
up <- add_ci(up, "est", "ci_lo", "ci_hi")
# Original marker semantics: filled = p < 0.05 (saved pval); hollow otherwise
# (including the 2018 reference year, which has no p-value).
up_sig <- !is.na(up$pval) & up$pval < 0.05
up_note <- sprintf(paste0("BCN public+charter; baseline 2016\u20132018; quota year 2019 (ref = 2018); ",
                          "n = %d UP schools (filled = p<0.05)"), up$n_schools[1])
p_up <- plot_single(
  up, x = "year", ref_x = 2018, onset_x = 2018.5, hollow = !up_sig,
  title = "Continuous DiD \u2013 Infantil (published quotas; UP schools)",
  subtitle = "Outcome: Effect on NESE-B number",
  xlab = "Year", ylab = "Effect on NESE-B number",
  caption = caption_of(up_note))
save_fig(p_up, "reshuffling_up.png")

# ============================================================================
# 3. Reshuffling: UP schools by type (two series, Okabe-Ito)
# ============================================================================
bt <- read.csv(file.path(data_dir, "reshuffling_by_type_es.csv"), na.strings = c("NA", ""))
bt <- add_ci(bt, "est", "ci_lo", "ci_hi")
bt$school_type <- factor(bt$school_type, levels = c("Public", "Charter"))
n_by <- tapply(bt$n_schools, bt$school_type, `[`, 1)
avg <- function(t, yrs) mean(bt$est[bt$school_type == t & bt$year %in% yrs])
pre_yrs <- 2013:2018; post_yrs <- 2019:2024   # reproduces the original printed averages
lev  <- levels(bt$school_type)
cols <- setNames(pal_multi_series[seq_along(lev)], lev)
bars <- setNames(vapply(cols, lighten_col, ""), lev)
shps <- setNames(shp_multi_series[seq_along(lev)], lev)
bt_note <- paste0(
  sprintf("Public: pre-avg %+.3f, post-avg %+.3f (n=%d) | Charter: pre-avg %+.3f, post-avg %+.3f (n=%d) | ",
          avg("Public", pre_yrs), avg("Public", post_yrs), n_by[["Public"]],
          avg("Charter", pre_yrs), avg("Charter", post_yrs), n_by[["Charter"]]),
  "BCN UP-direction schools; baseline 2016\u20132018; quota year 2019 (ref=2018)")
# Line breaks at the original " | " separators (text otherwise unchanged).
bt_caption <- paste(c(sub("\\| BCN", "|\nBCN", bt_note), BARS_NOTE), collapse = "\n")
pos  <- position_dodge(width = 0.5)
p_bt <- ggplot(bt, aes(x = year, y = est, group = school_type)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey30", linewidth = 0.4) +
  geom_vline(xintercept = 2018.5, linetype = "dashed", colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(ymin = lo95, ymax = hi95, colour = school_type), linewidth = 0.5,
                 position = pos, na.rm = TRUE) +
  geom_point(aes(fill = school_type, shape = school_type), size = 2.3, colour = "grey15",
             stroke = 0.4, position = pos) +
  scale_colour_manual(values = bars, name = "School type") +
  scale_fill_manual(values = cols, name = "School type") +
  scale_shape_manual(values = shps, name = "School type") +
  scale_x_continuous(breaks = 2013:2024, limits = c(2012.5, 2024.5), expand = c(0, 0)) +
  labs(title = "Continuous DiD \u2013 Infantil (UP schools by type; published quotas)",
       subtitle = "Outcome: Effect on NESE-B number",
       x = "Year", y = "Effect on NESE-B number",
       caption = bt_caption) +
  theme_paper_serif() +
  theme(legend.title = element_text(size = BASE - 1))
save_fig(p_bt, "reshuffling_by_type.png")
