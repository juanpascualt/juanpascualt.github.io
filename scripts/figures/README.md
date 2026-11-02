# Website figures: reproducible renderer

Three of the four research figures on the site are drawn from **saved aggregate
estimates**: event-study coefficients and their saved 95% bounds. Nothing is
re-estimated or digitised, and no new inference is computed. The fourth figure
(monthly wage) is handled separately (see *Monthly wage figure* below).

```
python3 -I scripts/figures/01_extract_aggregates.py   # copy rows verbatim from Dropbox sources (needs Dropbox)
Rscript   scripts/figures/02_render_figures.R          # write img/*.png (1800 x 1100, 250 dpi)
Rscript   scripts/figures/03_verify.R                  # 48 programmatic checks; exit 1 on any failure
```

`02_render_figures.R` and `03_verify.R` need only `data/` (R: ggplot2, ragg, jsonlite, digest).
The source re-check in `03_verify.R` runs only when the Dropbox sources are reachable.
To point it at another location, set `FIG_DROPBOX_ROOT`.

The style matches `Vocational/5_Package/1_Codes/_helpers.R` (`theme_paper_serif`,
`plot_event_study_paper[_multi]`): serif 11 pt, `theme_classic`, centred titles,
grey diamonds for a single series, and Okabe-Ito colours with distinct markers
and 45%-lightened bars for two series. Zero and onset lines are dashed. The only
interval drawn is a thin bar for the saved 95% CI, copied verbatim from the source
(`ci_lo`/`ci_hi`, `ci_lower`/`ci_upper`). No other interval level is shown.

Titles, subtitles, axis labels, legend and notes reproduce the original website
figures. Only line breaks change, plus one added line, "Bars show 95% confidence
intervals." (the original UP figure used a ribbon; the saved bounds are drawn
verbatim). The by-type note was clipped at the right edge of the original image.
Its full text (quota year 2019, ref = 2018) is confirmed by the source.

After rendering, copy each of the three PNGs to `static/img/` and `public/img/` under
the same filename. `03_verify.R` checks that the sha256 is equal across the three locations.

`03_verify.R` also checks that each restyled PNG differs from the original website
image at the immutable baseline commit `3c33d79aab0943ff209224029cf80dce9b9f3363`
(`git rev-parse 3c33d79:img/<file>`), the checkout from which the figures were
restyled. The baseline is a fixed constant, not `HEAD`, so the check still holds
after the restyled PNGs are committed. If the baseline blob cannot be resolved
(for example, a shallow clone without that commit), the check fails instead of
passing.

`03_verify.R` compares every drawn point and 95% bar with the saved row for the same
(period, series) key, so a permutation fails. It also checks the original support
(10 crime-gap points, 12 UP, 24 by type), that there is exactly one interval layer,
that UP markers are filled exactly where the saved p < 0.05, and the exact label text.

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
| Size | 1600×1050 (crime), 1800×1050 (reshuffling) | 1800×1100 all, shared margins/text scale |
| Crime gap | C&S never-treated, 95% bars | identical values and 95% bounds; original title/subtitle/axis text (panel tag "(a)" dropped) |
| UP | ribbon 95% CI; filled = p < 0.05 | identical values and 95% bounds, drawn as bars; filled diamond = p < 0.05 (reference year hollow, as before); original note |
| By type | 95% bars, all markers filled | identical values and 95% bounds; Public #0072B2 circle, Charter #D55E00 triangle; legend "School type"; original note with printed averages and n |

## Monthly wage figure (`img/crime_monthly_earnings_large.png`)

The wage figure uses `04_restyle_wage_raster.py` (Python with NumPy and Pillow).
Its exact event-study estimates were never saved: `08_survey_outcomes.R` passes
`cs$dyn` to the plot without writing it to disk. The script therefore recolours
the statistical pixels of `data/original_wage.png` in place and redraws the
background, axes and labels. It neither estimates nor digitises coefficients.

Run `python3 -I scripts/figures/04_restyle_wage_raster.py` with those packages
installed. The archived original is protected by its SHA-256
`9bac3c2192b637dbf538852cc2854e9446b44a1e2d8c86de58ce10d9d3eb98de`.
It is byte-identical to `img/crime_monthly_earnings_large.png` at the same baseline
commit `3c33d79aab0943ff209224029cf80dce9b9f3363` (last changed in `2310c86`).
The output remains 1600×1050, preserving the original coordinate grid.
`data/wage_geometry.json` records the final hash and checks; the adjacent masks
store statistical coverage, support and hollow-marker interiors. All 31,478
statistical pixels, 141 connected components and seven hollow interiors retain
their positions and coverage. Labels, printed statistics and the existing 95%
intervals are unchanged. No new interval level is added.

The PNG is copied byte for byte to `static/img/` and `public/img/`. Font and PNG
rendering can vary across Pillow versions; the geometry checks run on every
render. The final output was reproduced twice with the Codex bundled Python
runtime, with identical output hashes.

Background: the original shows the C&S event study for `wage_cont` (binary dual-offer
adoption, not-yet-treated controls, school cluster, e = −6..6, overall ATT 39.731,
SE 13.047). The only saved number is the overall ATT, 39.7308, in
`2_Out/_baseline_tables_2026-07-30/1_did_offer/08_survey_outcomes/survey_results_full.csv`
(which reports SE 12.674, not 13.047). Redrawing it from data would require writing
`cs$dyn` to CSV in a re-run on the authorised machine and re-confirming those estimates
against the original before replacing the image.
