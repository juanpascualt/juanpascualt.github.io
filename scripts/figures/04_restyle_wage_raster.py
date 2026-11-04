#!/usr/bin/env python3
"""Read-only extractor/verifier of the original wage-figure geometry.

(Filename kept for compatibility. Until 2026-11-02 this script also recoloured the
raster and wrote img/crime_monthly_earnings_large.png; that public-output path has
been removed. The wage figure is now drawn by 02_render_figures.R with the same
ggplot template as the other three figures, from the coordinates verified here.)

Input (read-only): scripts/figures/data/original_wage.png, the public figure
img/crime_monthly_earnings_large.png at baseline commit 3c33d79 (last changed in
2310c86), protected by its SHA-256.
Reference (read-only): scripts/figures/data/wage_geometry.json and the four
historical wage_geometry_*.png masks written by the earlier recolouring run.

The script writes nothing. It re-measures the original raster with the unchanged
measurement functions and exits non-zero unless every measured field equals the
saved JSON exactly (after the same rounding):

  * coverage level k = clip(B - R, 0, 139): every statistical mark is a single blue
    (#2166AC) alpha-blended over a neutral background, so b - r = alpha * 139;
  * support S = {k >= 1}; hollow-marker interiors = enclosed non-S regions >= 30 px;
  * panel bounds and the 13 x / 5 y tick centres from the light grid lines; zero and
    onset reference-line cross-section profiles;
  * per event time (-6..6): marker-disk centre (y = midpoint of the rows whose
    k >= 70 span exceeds the 4 px bar width; x = k-weighted centroid of those rows),
    hollow flag, support_rows_top_bottom (all rows with k >= 1 in the column,
    including the 1-4 px resampling fringe), core_rows_top_bottom_ci_endpoints
    (rows with k >= 70, including the marker disk) and bar_core_rows_top_bottom
    (rows with k >= 70 outside the marker disk = the opaque 95% bar core; null at
    e = -1, which has no bar). 02_render_figures.R uses bar_core_rows_top_bottom;
  * connected components of S, of the core and of the hollow interiors;
  * the historical masks (support, k, hollow interiors, marker/bar class map)
    equal the re-measured arrays.

All quantities are image coordinates (pixel indices, y downward) at raster
resolution. No coefficient or standard error is derived from them. The 90% bars
of the website figure are not measured here: 02_render_figures.R derives them
from centre_xy and bar_core_rows_top_bottom (see WAGE90_RATIO there).

Usage (repo root):
  python3 -I -B scripts/figures/04_restyle_wage_raster.py
"""
from __future__ import annotations

import hashlib
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "scripts" / "figures" / "data"
SRC = DATA / "original_wage.png"
GEOMETRY = DATA / "wage_geometry.json"
SRC_SHA256 = "9bac3c2192b637dbf538852cc2854e9446b44a1e2d8c86de58ce10d9d3eb98de"

W, H = 1600, 1050
BLUE = (33, 102, 172)
D = BLUE[2] - BLUE[0]           # 139 coverage levels
CLS_NONE, CLS_BAR, CLS_FILL, CLS_BORDER = 0, 1, 2, 3
CLS_NAME = {CLS_BAR: "ci_bar", CLS_FILL: "marker_fill", CLS_BORDER: "marker_border"}
CORE_K = 70                     # k >= 70 (alpha >= 0.5) defines the opaque core
BAR_CORE_W = 4                  # core width of a CI bar (px)
DISK_ROWS = (15, 20)            # admissible marker-disk height (px)
R_OUT = 11.0                    # marker region radius: disk fringe reaches k = 0 by ~10.5
R_IN = 8.0                      # fill/border split of the historical class map
Y_TICKS = [120, 80, 40, 0, -40]          # top to bottom, as printed in the original
X_TICKS = list(range(-6, 7))             # left to right, as printed in the original


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


# ----------------------------------------------------------------------------
# Geometry helpers (no scipy dependency)
# ----------------------------------------------------------------------------
def components(mask: np.ndarray, weights: np.ndarray | None = None) -> list[dict]:
    """8-connected components with bbox, area, centroid and k-weighted centroid."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        pix = []
        while q:
            y, x = q.popleft()
            pix.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
        p = np.array(pix)
        py, px = p[:, 0], p[:, 1]
        c = {"area": int(len(p)),
             "bbox_x0y0x1y1": [int(px.min()), int(py.min()), int(px.max()), int(py.max())],
             "centroid_xy": [round(float(px.mean()), 6), round(float(py.mean()), 6)]}
        if weights is not None:
            wt = weights[py, px].astype(float)
            c["k_weighted_centroid_xy"] = [round(float((px * wt).sum() / wt.sum()), 6),
                                           round(float((py * wt).sum() / wt.sum()), 6)]
        out.append(c)
    out.sort(key=lambda c: (c["bbox_x0y0x1y1"][0], c["bbox_x0y0x1y1"][1]))
    return out


def enclosed_holes(support: np.ndarray) -> np.ndarray:
    """Non-support pixels not 4-connected to the image border."""
    h, w = support.shape
    outside = np.zeros_like(support, dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not support[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if not support[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and not support[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                q.append((ny, nx))
    return ~support & ~outside


HOLLOW_MIN_AREA = 30   # smaller enclosed gaps are diagonal slivers in faint halos


def hollow_interiors(support: np.ndarray) -> np.ndarray:
    """Enclosed non-support regions large enough to be a marker's white fill."""
    holes = enclosed_holes(support)
    keep = np.zeros_like(holes)
    seen = np.zeros_like(holes)
    h, w = holes.shape
    for y0, x0 in zip(*np.nonzero(holes)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)]); seen[y0, x0] = True; pix = []
        while q:
            y, x = q.popleft(); pix.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and holes[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((ny, nx))
        if len(pix) >= HOLLOW_MIN_AREA:
            for y, x in pix:
                keep[y, x] = True
    return keep


def line_clusters(profile: np.ndarray, lo: int, hi: int, thr: int = 250) -> list[dict]:
    """Darkness-weighted centres of grid-line cross-sections in profile[lo:hi]."""
    idx = [i for i in range(lo, hi) if profile[i] < thr]
    groups, cur = [], []
    for i in idx:
        if cur and i != cur[-1] + 1:
            groups.append(cur)
            cur = []
        cur.append(i)
    if cur:
        groups.append(cur)
    res = []
    for g in groups:
        wts = 255.0 - profile[g].astype(float)
        res.append({"pixels": g, "centre": float((np.array(g) * wts).sum() / wts.sum())})
    return res


def partition(k: np.ndarray, S: np.ndarray, Hh: np.ndarray, x_ticks: list[float]):
    """Deterministic marker / CI-bar colour partition of the support S.

    Returns the class map and per-column marker geometry measured from k.
    """
    yy, xx = np.mgrid[0:H, 0:W]
    cls = np.zeros((H, W), dtype=np.uint8)
    cls[S] = CLS_BAR
    hole_cc = components(Hh)
    markers = []
    for v, xc in zip(X_TICKS, x_ticks):
        x = round(xc)
        x0, x1 = x - 14, x + 15
        core = k[:, x0:x1] >= CORE_K
        cols = np.arange(core.shape[1])
        span = np.where(core.any(1),
                        np.where(core, cols, -1).max(1) - np.where(core, cols, 10 ** 6).min(1) + 1, 0)
        wide = np.nonzero(span > BAR_CORE_W + 1)[0]     # core span wider than a bar
        assert len(wide) and wide[-1] - wide[0] + 1 == len(wide), f"e={v}: disk rows not contiguous"
        assert DISK_ROWS[0] <= len(wide) <= DISK_ROWS[1], f"e={v}: disk height {len(wide)}"
        cy = (wide[0] + wide[-1]) / 2
        sub = k[wide[0]:wide[-1] + 1, x0:x1].astype(float)
        cx = float((sub * np.arange(x0, x1)).sum() / sub.sum())
        d = np.hypot(xx - cx, yy - cy)
        disk = S & (d <= R_OUT)
        # the marker region must not reach any other event-time column
        others = [round(t) for t in x_ticks if round(t) != x]
        assert not any(disk[:, max(o - 20, 0):o + 21].any() for o in others)
        hollow = [h for h in hole_cc
                  if (h["centroid_xy"][0] - cx) ** 2 + (h["centroid_xy"][1] - cy) ** 2 < 4.0]
        assert len(hollow) <= 1
        if hollow:
            cls[disk] = CLS_BORDER                    # the stroke ring is the whole mark
        else:
            cls[disk & (d <= R_IN)] = CLS_FILL
            cls[disk & (d > R_IN)] = CLS_BORDER
        # off-bar support just outside the marker region (should be ~empty)
        stray = S & (d > R_OUT) & (d <= 14) & (np.abs(xx - cx) > 4.5)
        # CI geometry: vertical extent of support and of the opaque core in this column
        col_s = np.nonzero(S[:, x0:x1].any(1))[0]
        col_c = np.nonzero(core.any(1))[0]
        bar_rows = np.nonzero(((cls[:, x0:x1] == CLS_BAR) & (k[:, x0:x1] >= CORE_K)).any(1))[0]
        markers.append({
            "event_time": v,
            "centre_xy": [round(cx, 4), round(float(cy), 4)],
            "disk_rows": [int(wide[0]), int(wide[-1])],
            "hollow": bool(hollow),
            "marker_pixels": int(disk.sum()),
            "fill_pixels": int((disk & (cls == CLS_FILL)).sum()),
            "border_pixels": int((disk & (cls == CLS_BORDER)).sum()),
            "stray_offbar_support_pixels_outside_marker": int(stray.sum()),
            "stray_offbar_max_k": int(k[stray].max()) if stray.any() else 0,
            "support_rows_top_bottom": [int(col_s[0]), int(col_s[-1])],
            "core_rows_top_bottom_ci_endpoints": [int(col_c[0]), int(col_c[-1])],
            "bar_core_rows_top_bottom": ([int(bar_rows[0]), int(bar_rows[-1])]
                                         if len(bar_rows) else None),
        })
    return cls, markers


def main() -> int:
    if sha256(SRC) != SRC_SHA256:
        sys.exit(f"archived original SHA-256 mismatch: {SRC}")
    im = Image.open(SRC)
    assert im.size == (W, H) and im.mode == "RGB", (im.size, im.mode)
    a = np.asarray(im).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]

    # --- 1. statistical layer -------------------------------------------------
    k = np.clip(b - r, 0, D).astype(np.int32)       # coverage level 0..139
    S = k >= 1
    Hh = hollow_interiors(S)
    ys_s, xs_s = np.nonzero(S)
    stat_bbox = [int(xs_s.min()), int(ys_s.min()), int(xs_s.max()), int(ys_s.max())]
    chroma = a.max(-1) - a.min(-1)
    ringing = (chroma > 0) & ~S                   # resampling overshoot, b - r <= 0
    # Chromatic pixels outside S have b - r <= 0: negative-lobe ringing from the
    # earlier upscaling, sitting on grid/background next to a mark. Check they are
    # all within 3 px of S (so no other coloured element is being discarded).
    near = S.copy()
    for _ in range(3):
        n2 = near.copy()
        n2[1:] |= near[:-1]; n2[:-1] |= near[1:]; n2[:, 1:] |= near[:, :-1]; n2[:, :-1] |= near[:, 1:]
        near = n2
    assert not (ringing & ~near).any(), "chromatic pixels far from statistical marks"

    # --- 2. non-statistical geometry measured from the original ---------------
    # Panel bounds and tick positions from the light grid lines.
    gray = a[..., 0]
    xcl = line_clusters(gray[135], 125, W)          # row above all marks
    xcl = [c for c in xcl if len(c["pixels"]) <= 5]
    onset = [c for c in xcl if 770 < c["centre"] < 810 and gray[135, c["pixels"]].min() < 200]
    xgrid = [c for c in xcl if c not in onset]
    assert len(xgrid) == len(X_TICKS), len(xgrid)
    x_ticks = [c["centre"] for c in xgrid]
    ycl = line_clusters(gray[:, 1540], 120, 935)    # column right of all marks
    assert len(ycl) == len(Y_TICKS), len(ycl)
    y_ticks = [c["centre"] for c in ycl]
    zero = ycl[Y_TICKS.index(0)]
    sx = np.diff(x_ticks); sy = np.diff(y_ticks)
    assert sx.max() - sx.min() < 1.0 and sy.max() - sy.min() < 1.0, "uneven tick spacing"
    row = gray[y_ticks[0].__round__()]
    xs_row = [x for x in range(120, W) if row[x] < 252]
    col = gray[:, round(x_ticks[-1])]
    ys_col = [y for y in range(115, 940) if col[y] < 252 and not S[y, round(x_ticks[-1])]]
    panel = {"x0": min(xs_row), "x1": max(xs_row), "y0": min(ys_col), "y1": max(ys_col)}
    assert panel["x0"] < stat_bbox[0] and panel["x1"] > stat_bbox[2]
    assert panel["y0"] < stat_bbox[1] and panel["y1"] > stat_bbox[3]

    # Cross-section intensity profiles of the original reference lines.
    zr = list(range(zero["pixels"][0] - 1, zero["pixels"][-1] + 2))
    zprof = 255.0 - np.median(gray[zr][:, 1450:1540], axis=1)     # free of marks
    oc = onset[0]["pixels"]
    oc = list(range(oc[0] - 1, oc[-1] + 2))
    seg = gray[200:215][:, oc]                                    # inside one dash
    oprof = 255.0 - np.median(seg, axis=0)
    zw = zprof / zprof.max(); ow = oprof / oprof.max()

    # --- 2b. marker / CI-bar partition (historical class map) -----------------
    cls, markers = partition(k, S, Hh, x_ticks)
    assert ((cls != CLS_NONE) == S).all()
    assert [m["hollow"] for m in markers].count(True) == len(components(Hh))

    # --- 3. compare with the saved geometry (read-only) ----------------------
    saved = json.loads(GEOMETRY.read_text())
    hole_cc = components(Hh)
    hollow_cols = sorted({int(round((c["bbox_x0y0x1y1"][0] + c["bbox_x0y0x1y1"][2]) / 2))
                          for c in hole_cc})
    nearest = lambda x: X_TICKS[int(np.argmin([abs(x - t) for t in x_ticks]))]
    measured = {
        "source_sha256": SRC_SHA256,
        "size": [W, H],
        "panel_bounds_px": panel,
        "statistical_bbox_px": stat_bbox,
        "x_tick_centres_px": dict(zip(map(str, X_TICKS), [round(v, 3) for v in x_ticks])),
        "y_tick_centres_px": dict(zip(map(str, Y_TICKS), [round(v, 3) for v in y_ticks])),
        "zero_line_rows_profile": dict(zip(map(str, zr), [round(float(v), 4) for v in zw])),
        "onset_line_cols_profile": dict(zip(map(str, oc), [round(float(v), 4) for v in ow])),
        "support_pixels": int(S.sum()),
        "class_pixels": {CLS_NAME[c]: int((cls == c).sum()) for c in CLS_NAME},
        "class_components": {CLS_NAME[c]: len(components(cls == c)) for c in CLS_NAME},
        "ringing_pixels_excluded": int(ringing.sum()),
        "hollow_interior_pixels": int(Hh.sum()),
        "hollow_markers_at_event_time": [nearest(x) for x in hollow_cols],
        "markers": markers,
        "support_components": components(S, k),
        "core_components": components(k >= (D + 1) // 2, k),
        "hollow_components": hole_cc,
    }
    bad = [key for key, v in measured.items() if json.loads(json.dumps(v)) != saved.get(key)]
    pp = saved.get("partition_parameters", {})
    if pp != {"core_k": CORE_K, "bar_core_width_px": BAR_CORE_W, "disk_rows_range": list(DISK_ROWS),
              "r_out_px": R_OUT, "r_in_px": R_IN}:
        bad.append("partition_parameters")
    # historical masks (written by the earlier recolouring run) == re-measured arrays
    mask = lambda n: np.asarray(Image.open(DATA / n)).astype(np.int32)
    masks_ok = {
        "wage_geometry_support_mask.png": (mask("wage_geometry_support_mask.png") == S * 255).all(),
        "wage_geometry_alpha.png": (mask("wage_geometry_alpha.png") == k).all(),
        "wage_geometry_hollow_mask.png": (mask("wage_geometry_hollow_mask.png") == Hh * 255).all(),
        "wage_geometry_class_mask.png": (mask("wage_geometry_class_mask.png") == cls.astype(np.int32) * 85).all(),
    }
    bad += [n for n, ok in masks_ok.items() if not ok]
    # structural expectations used by the renderer
    ms = saved["markers"]
    if [m["event_time"] for m in ms] != X_TICKS:
        bad.append("marker event times")
    if [m["event_time"] for m in ms if m["bar_core_rows_top_bottom"] is None] != [-1]:
        bad.append("only e = -1 lacks a 95% bar core")
    if [m["event_time"] for m in ms if m["hollow"]] != saved["hollow_markers_at_event_time"]:
        bad.append("hollow flags")
    for m in ms:
        b = m["bar_core_rows_top_bottom"]
        if b is not None and not (m["support_rows_top_bottom"][0] <= b[0] < b[1] <= m["support_rows_top_bottom"][1]):
            bad.append(f"e={m['event_time']}: bar core outside support rows")
    if bad:
        print("MISMATCH (saved geometry NOT confirmed; do not substitute values):", ", ".join(bad))
        return 1
    print(f"ok: source sha256 {SRC_SHA256[:12]}; {len(markers)} marker centres, "
          f"{sum(m['bar_core_rows_top_bottom'] is not None for m in markers)} bar-core endpoint pairs, "
          f"{len(x_ticks)} x / {len(y_ticks)} y ticks, reference-line profiles, "
          f"{len(hole_cc)} hollow markers, {len(measured['support_components'])} support components "
          f"and 4 historical masks equal wage_geometry.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
