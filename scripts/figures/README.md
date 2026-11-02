# Website figures: reproducible renderer

All four research figures on the site are drawn by `02_render_figures.R` with one
ggplot template. Three of them come from **saved aggregate estimates**: event-study
coefficients, their saved standard errors and saved 95% bounds. Nothing is
re-estimated. The fourth (monthly wage) has no saved estimates; it is a **graphical
reconstruction** from the image coordinates of the original raster and shows only
its original 95% intervals (see *Monthly wage figure* below).

```
python3 -I scripts/figures/01_extract_aggregates.py   # copy rows verbatim from Dropbox sources (needs Dropbox)
python3 -I -B scripts/figures/04_restyle_wage_raster.py  # read-only: re-measure original wage raster == wage_geometry.json
Rscript   scripts/figures/02_render_figures.R          # write the 4 img/*.png (3300 x 2250 = 11 x 7.5 in at 300 dpi)
Rscript   scripts/figures/03_verify.R                  # programmatic checks; exit 1 on any failure
```

`02_render_figures.R` and `03_verify.R` need only `data/` (R: ggplot2, ragg, jsonlite, digest).
The source re-check in `03_verify.R` runs only when the Dropbox sources are reachable.
To point it at another location, set `FIG_DROPBOX_ROOT`.

## Template

The four figures follow the reference paper figure
`Vocational/5_Package/2_Out/Figures/1_did_offer/01_did_validation/eventstudy_crpc_ctrl.png`
(`make_es_fig()` in `01_did_validation.R`, which calls `plot_event_study_paper_multi()` in
`_helpers.R`). That figure is saved at 11 × 7.5 in and 300 dpi. The reference PNG is
3300 × 2434 because a 184 px technical footer (FUENTE/NOTAS) is appended to it. The
website figures are 3300 × 2250, without that footer. Rendering at the reference's
physical size matters: at the previous 7.2 × 4.4 in canvas, text was about 1.53 times
too large relative to the panel.

* Serif (Times via ragg). Title 16 pt (raised from the reference's 12 pt for
  legibility on the site), regular, centred, wrapped on word boundaries at 65
  characters (all current titles fit on one line). Subtitle 10 pt, grey30. Axis
  titles 11 pt. Tick and legend text 8.8 pt. Notes 8.5 pt, grey15, line height 1.15,
  left aligned, wrapped at 150 characters. Plot margins 8/12/8/24 pt (top/right/bottom/left).
* White background, no grid, black axes (0.35). Zero line `#4D4D4D` and onset line
  `#8C8C8C`, both dashed (0.4).
* Points size 2.0, stroke 0.4, border `#262626`. Single series: circle (21), fill
  `#0072B2`, intervals `#72B1D4` (first slot of the reference). By type: Public circle,
  fill `#0072B2`, intervals `#72B1D4`; Charter triangle (24), fill `#D55E00`, intervals
  `#E7A672`. The interval colours were sampled from the reference PNG. The legend sits
  at the bottom, horizontal and without a title. The single-series figures have no legend.
* Intervals: 90% as thick bars (linewidth 1.3) and 95% as thin bars (linewidth 0.4).
  The 95% bounds are the saved `ci_lo`/`ci_hi` (`ci_lower`/`ci_upper`), copied verbatim.
  In all three sources they equal estimate ± 1.96 × SE (largest discrepancy 7.1e-15), and
  they are not recomputed with `qnorm(0.975)`. The 90% bounds are the estimate ±
  `qnorm(0.95)` (1.644854) × the saved SE. Reference rows keep their saved NA (crime gap,
  e = −1) or 0/0 (reshuffling, 2018) values.
* Marker fill follows the original figures: pooled UP markers are filled exactly where the
  saved p < 0.05 and hollow otherwise (including the 2018 reference year). Crime-gap and
  by-type markers are all filled. The 90% bounds play no role in the fill rule.

## Text

Titles, axis labels and the printed statistics of the original website figures are
kept. Each figure has a left-aligned "Notes:" paragraph that describes its own
estimator and sample and ends with the same sentence, "Bars indicate 90% (thick) and
95% (thin) confidence intervals." How the bounds are computed (saved 95% bounds verbatim;
90% = estimate ± `qnorm(0.95)` × saved SE) is documented here and in the source
comments, not on the public charts. No variable or cache names appear in the Notes.

* Crime gap: subtitle "Effect on the 16–25 minus 36–45 crime-rate gap." The
  post-period average (−17.1 per 1,000, p = 0.011) and the pre-trend test (p = 0.84)
  move from the subtitle into the Notes. The Notes add the estimator ("Callaway and
  Sant'Anna event-study estimates with never-treated controls."; source series
  `csdid_nt`, not printed) and the normalisation (year −1).
* Pooled UP: the original note (BCN public+charter; baseline 2016–2018; quota year 2019,
  ref = 2018; n = 311; filled = p < 0.05) becomes a sentence-form Notes paragraph naming
  the continuous difference-in-differences event study.
* By type: the printed averages (Public +0.057 / +1.259, n = 158; Charter −0.029 / +0.399,
  n = 153) and the baseline, quota and reference years are kept in full. The original
  note was clipped at the right edge of the image; its full text (quota year 2019,
  ref = 2018) is confirmed by the source.

After rendering, copy each of the four PNGs to `static/img/` and `public/img/` under
the same filename. `03_verify.R` checks that the sha256 is equal across the three
locations. The `.paper-figures img` rule in `css/`, `static/css/` and `public/css/style.css`
uses `aspect-ratio: 22 / 15` (= 3300 / 2250), with `object-fit: contain` on a white
background, and `03_verify.R` checks that all three files agree.

`03_verify.R` also checks that each restyled PNG differs from the original website
image at the immutable baseline commit `3c33d79aab0943ff209224029cf80dce9b9f3363`
(`git rev-parse 3c33d79:img/<file>`), the checkout from which the figures were
restyled. The baseline is a fixed constant, not `HEAD`, so the check still holds
after the restyled PNGs are committed. If the baseline blob cannot be resolved
(for example, a shallow clone without that commit), the check fails instead of
passing.

`03_verify.R` compares every drawn point, thin 95% bar and thick 90% bar with the saved
row for the same (period, series) key, so a permutation fails. The 95% bars must equal
the saved bounds exactly and the 90% bars must equal estimate ∓ `qnorm(0.95)` × saved SE
exactly. It also checks the original support (10 crime-gap points, 12 UP, 24 by type),
that there are exactly two interval layers, the UP fill rule, the template (canvas, dpi,
font sizes, colours, point shapes and sizes, line widths) and the exact label text.

## Sources (read-only; hashes in `data/provenance.json`)

| Website image | Source (under Dropbox) | SHA-256 (first 12) | Rows used |
|---|---|---|---|
| `crime_youth_adult_gap_centered.png` | `Vocational/5_Package/2_Out/_baseline_tables_2026-07-30/4_ddd/01_did_validation/es_leads_lags_ddd.csv` (2026-07-20) | `41d36952e4a8` | `estimator == csdid_nt`, e = −6..3 (website x support) |
| (subtitle) | same folder, `anticipation_ddd.tex`, column "Anticipation = 0" | `b65a62cf08e4` | ATT −17.061 (SE 6.697), p 0.011, pre-test p 0.837 |
| `reshuffling_up.png` | `Pla de Xoc/Data/Temp/idescat_onsite/mirror_staging/Package/Out/Tables/06_JP_continuous_did/published_quotas/02_eventstudy_number_inf1_bysign.csv` (2026-07-07) | `00f294ce7f17` | `sign_group == UP` (n = 311) |
| `reshuffling_by_type.png` | same folder, `03_eventstudy_number_inf1_up_by_school_type.csv` (2026-07-07) | `34cbf9d412f3` | all (Public n = 158, Charter n = 153) |

`02_eventstudy_number_inf1_bysign.csv` is byte-identical to
`Pla de Xoc/Data/Clean/_iwip_reference/` and to
`Data/Temp/downstream_before_czonefix_20260922/...`. The live
`Package/Out/Tables/...` versions have since changed (re-runs after 2026-09-22),
so they are **not** used.

### How each source was matched to the original website image (commit 0b43d07, 2026-07-24)

* **Crime gap.** The script `19_saturated_fe.R` (title "(a) Dual VET narrows…") saves no
  coefficients. The `csdid_nt` series in the 2026-07-20 baseline table is the same
  never-treated C&S gap estimate. Its post-average −17.061, p 0.011 and pre-test p 0.837
  round to the original subtitle (−17.1, 0.011, 0.84). Its mean lead over −4..−2 (4.189)
  equals `pretrend_ddd.csv`. Its points and bounds coincide with the original figure: e = 3 is
  −39.6 with CI [−71.2, −8.1], and e = 0 is −14.3 with CI [−24.0, −4.6].
* **Reshuffling (UP).** n = 311, the p < 0.05 markers (2014 and 2019–2024 filled) and the
  CI extremes (2013 lower −0.130, 2022 upper 1.162) match the original.
* **Reshuffling by type.** Only snapshots dated on or before 2026-07-07 match exactly. The
  pre/post averages printed on the original (+0.057 / +1.259 public, −0.029 / +0.399 charter)
  and the counts n = 158 / 153 are reproduced. Re-runs from September give 1.72701 instead
  of 1.72656 for public 2023 and are not used.

## Comparison: original vs restyled

| | Original | Restyled |
|---|---|---|
| Size | 1600×1050 (crime, wage), 1800×1050 (reshuffling) | 3300×2250 all (11 × 7.5 in, 300 dpi), reference template |
| Crime gap | C&S never-treated, 95% bars | identical values and saved 95% bounds (thin), added 90% bars (thick); blue circles; post-average and pre-trend statistics moved to Notes (panel tag "(a)" dropped) |
| UP | ribbon 95% CI; filled = p < 0.05 | identical values and saved 95% bounds as thin bars, added 90% thick bars; filled blue circle = p < 0.05 (reference year hollow, as before); original note as Notes |
| By type | 95% bars, all markers filled | identical values and saved 95% bounds, added 90% bars; Public #0072B2 circle, Charter #D55E00 triangle; untitled bottom legend; Notes keep printed averages and n |
| Wage | 1600×1050 raster, 95% bars, hollow = not significant | same ggplot template; centres and 95% bar endpoints at the original image coordinates (graphical reconstruction, no numbers derived); 95% only; same hollow markers; original title and ATT 39.731*** (SE 13.047) |

## Monthly wage figure (`img/crime_monthly_earnings_large.png`)

The wage event-study estimates were never saved: `08_survey_outcomes.R` passes
`cs$dyn` to the plot without writing it to disk. The figure is therefore a
**graphical reconstruction** of the original image, drawn as new ggplot layers by
the same `plot_single()` helper as the crime-gap and UP figures (circle 21, size 2.0,
stroke 0.4, fill `#0072B2` / white, border `#262626`; thin 95% bars 0.4 `#72B1D4`;
no 90% layer; same theme, canvas and Notes style). The old raster is not overlaid.

Source: `data/original_wage.png`, SHA-256
`9bac3c2192b637dbf538852cc2854e9446b44a1e2d8c86de58ce10d9d3eb98de`, byte-identical to
`img/crime_monthly_earnings_large.png` at baseline `3c33d79aab0943ff209224029cf80dce9b9f3363`
(last changed in `2310c86`). `data/wage_geometry.json` holds the geometric measurements
of that raster in image coordinates (0-based pixel indices, x right, y down, raster
resolution). `04_restyle_wage_raster.py` (filename kept for compatibility) is now a
read-only verifier: it checks the source hash, re-measures the raster with the
unchanged measurement code and fails unless every measured field (13 marker centres,
bar endpoints, tick centres, reference-line profiles, hollow markers, connected
components and the four historical `wage_geometry_*.png` masks) equals the JSON. It
writes nothing; its former recolouring/PIL output path was removed.

How the panel is drawn (`02_render_figures.R`, section 4):

* x and y are the source pixel coordinates; y uses `scale_y_reverse`. Panel limits are
  the original panel bounds (x 120..1546, y 126..931) with `expand = 0`, so every mark
  keeps its normalized position relative to the original axes.
* Breaks are the measured tick centres, labelled with the values printed on the
  original (x −6..6; y 120, 80, 40, 0, −40). The labels carry the original units;
  no coefficient, SE or 90% bound is computed from pixel positions.
* Points are the measured marker-disk `centre_xy`. Hollow markers (white) are those
  measured hollow in the original: e = −6..−1 and 1.
* 95% bars span `bar_core_rows_top_bottom`: the first and last rows of the opaque bar
  core (coverage k ≥ 70) outside the marker disk. `support_rows_top_bottom` (k ≥ 1) also
  contains a 1–4 px anti-aliasing/resampling fringe, and
  `core_rows_top_bottom_ci_endpoints` also counts the marker disk; both stay in the JSON
  as provenance but are not drawn. e = −1 (reference period) has no bar in the original
  (`null`), so none is drawn; its marker footprint is not treated as an interval.
* Zero line at the measured `y_tick_centres_px["0"]`; onset line at the weighted
  centroid of the measured `onset_line_cols_profile` (x ≈ 789.46).

Fidelity is geometric at the original raster resolution, not numerical estimator
exactness. Text keeps the original title, subtitle and axis labels; the Notes keep
"Overall ATT: 39.731*** (SE 13.047)", state that e = −1 is the normalized base period
and that deeper pre-periods come from later adopters, and that bars show 95%
confidence intervals. `03_verify.R` checks that each drawn centre and bar endpoint
equals the saved coordinate for its event time exactly, the ticks, labels, limits,
reference lines, hollow markers, the absence of a 90% layer, and the source hash.

Background: the original shows the C&S event study for `wage_cont` (binary dual-offer
adoption, not-yet-treated controls, school cluster, e = −6..6, overall ATT 39.731,
SE 13.047). The only saved number is the overall ATT, 39.7308, in
`2_Out/_baseline_tables_2026-07-30/1_did_offer/08_survey_outcomes/survey_results_full.csv`
(which reports SE 12.674, not 13.047). Redrawing it from data would require writing
`cs$dyn` to CSV in a re-run on the authorised machine and re-confirming those estimates
against the original before replacing the image.
