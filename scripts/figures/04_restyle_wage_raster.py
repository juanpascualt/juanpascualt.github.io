#!/usr/bin/env python3
"""Deterministic restyle of the legacy wage event-study raster.

Input  (read-only): scripts/figures/data/original_wage.png  (archived copy of the
        public figure img/crime_monthly_earnings_large.png at commit 2310c86).
Output: img/crime_monthly_earnings_large.png (1600x1050, same pixel grid)
        scripts/figures/data/wage_geometry_support_mask.png  (binary support mask)
        scripts/figures/data/wage_geometry_alpha.png         (per-pixel coverage level k)
        scripts/figures/data/wage_geometry_hollow_mask.png   (hollow-marker interiors)
        scripts/figures/data/wage_geometry.json              (verification report)

No numeric source for this figure survives, so the statistical marks (95% CIs and
point markers) are NOT re-plotted. They are isolated algorithmically from the
original pixels and recoloured in place:

  * Every statistical mark in the original is a single blue (#2166AC = 33,102,172)
    alpha-blended over a neutral (r=g=b) background. For such a blend
    b - r = alpha * (172 - 33), so the coverage level k = clip(b - r, 0, 139) is an
    exact, background-independent per-pixel measure of mark coverage.
  * Support mask S = {k >= 1}. Hollow-marker interiors (white fill = original
    "not significant" encoding) are the enclosed non-S regions H.
  * Output on S u H: grey = round(255 - k/139 * (255 - 89)) over white, i.e. the
    same coverage of grey35 instead of blue. Because 255 - 89 = 166 > 139 the map
    k -> grey is injective, so k is exactly recoverable from the output.
  * Everything else (grid, text, axes, reference lines) is redrawn from scratch in
    serif on white. The zero and onset lines keep the original sub-pixel
    position by reusing the original cross-section intensity profile.

The script asserts (i) the archived original's SHA-256, (ii) exact equality of the
per-pixel coverage level, support mask, hollow mask, and connected-component
bounds/areas/centroids recovered independently from the output, and (iii) that
no redrawn text is clipped or enters the panel. Nothing numeric is inferred.
"""
from __future__ import annotations

import hashlib
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "scripts" / "figures" / "data"
SRC = DATA / "original_wage.png"
OUT = ROOT / "img" / "crime_monthly_earnings_large.png"
SRC_SHA256 = "9bac3c2192b637dbf538852cc2854e9446b44a1e2d8c86de58ce10d9d3eb98de"

W, H = 1600, 1050
BLUE = (33, 102, 172)
D = BLUE[2] - BLUE[0]           # 139 coverage levels
MARK_GREY = 89                  # grey35, as in the paper renderer's filled markers
ZERO_GREY = 77                  # grey30 dashed zero line
ONSET_GREY = 140                # grey55 dashed onset line
TEXT = (0, 0, 0)
SUBTITLE = (77, 77, 77)         # grey30
CAPTION = (38, 38, 38)          # grey15
AXIS_W = 2                      # ~0.35 pt at this resolution
TICK_LEN = 9
DASH_ON, DASH_OFF = 14, 10

FONT_REG = "/System/Library/Fonts/Supplemental/Times New Roman.ttf"

TITLE = "Callaway-Sant’Anna event study: Monthly Wage (EUR, midpoints)"
SUBTITLE_TXT = "Binary dual-offer adoption | not-yet-treated controls | clustered at school"
YLAB = "Effect on Monthly Wage (EUR, midpoints)"
XLAB = "Event time (years relative to dual adoption)"
# Wording exactly as printed in the original raster.
NOTE = ("Overall ATT: 39.731*** (SE 13.047). e=−1 is the normalized base; "
        "deeper pre-periods come from later adopters.")
Y_TICKS = [120, 80, 40, 0, -40]          # top to bottom, as printed in the original
X_TICKS = list(range(-6, 7))             # left to right, as printed in the original


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def fmt(v: int) -> str:
    return str(v).replace("-", "−")


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


# ----------------------------------------------------------------------------
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

    # --- 3. background layer (independent of the statistical mask) -------------
    bg = Image.new("L", (W, H), 255)
    bga = np.full((H, W), 255.0)
    # dashed zero line, original vertical profile, across the panel
    xs_line = np.arange(panel["x0"], panel["x1"] + 1)
    on_x = ((xs_line - panel["x0"]) % (DASH_ON + DASH_OFF)) < DASH_ON
    for yy, wt in zip(zr, zw):
        vals = 255.0 - wt * (255 - ZERO_GREY)
        bga[yy, xs_line[on_x]] = np.minimum(bga[yy, xs_line[on_x]], vals)
    # dashed onset line, original horizontal profile, panel height
    ys_line = np.arange(panel["y0"], panel["y1"] + 1)
    on_y = ((ys_line - panel["y0"]) % (DASH_ON + DASH_OFF)) < DASH_ON
    for xx, wt in zip(oc, ow):
        vals = 255.0 - wt * (255 - ONSET_GREY)
        bga[ys_line[on_y], xx] = np.minimum(bga[ys_line[on_y], xx], vals)
    bg = Image.fromarray(np.rint(bga).astype(np.uint8), "L").convert("RGB")
    dr = ImageDraw.Draw(bg)
    # thin black axes on the panel's left and bottom edges, outward ticks
    ax_x, ax_y = panel["x0"], panel["y1"]
    dr.rectangle([ax_x - AXIS_W + 1, panel["y0"], ax_x, ax_y], fill=TEXT)
    dr.rectangle([ax_x - AXIS_W + 1, ax_y, panel["x1"], ax_y + AXIS_W - 1], fill=TEXT)
    for yc in y_ticks:
        y = round(yc)
        dr.rectangle([ax_x - TICK_LEN, y - AXIS_W // 2, ax_x, y - AXIS_W // 2 + AXIS_W - 1], fill=TEXT)
    for xc in x_ticks:
        x = round(xc)
        dr.rectangle([x - AXIS_W // 2, ax_y, x - AXIS_W // 2 + AXIS_W - 1, ax_y + TICK_LEN], fill=TEXT)

    f_title = ImageFont.truetype(FONT_REG, 40)
    f_sub = ImageFont.truetype(FONT_REG, 32)
    f_axis = ImageFont.truetype(FONT_REG, 33)
    f_tick = ImageFont.truetype(FONT_REG, 30)
    f_note = ImageFont.truetype(FONT_REG, 26)
    boxes = {}

    def text(key, xy, s, font, fill, anchor):
        dr.text(xy, s, font=font, fill=fill, anchor=anchor)
        boxes[key] = list(dr.textbbox(xy, s, font=font, anchor=anchor))

    text("title", (W / 2, 58), TITLE, f_title, TEXT, "ms")
    text("subtitle", (W / 2, 100), SUBTITLE_TXT, f_sub, SUBTITLE, "ms")
    for v, yc in zip(Y_TICKS, y_ticks):
        text(f"ytick_{v}", (ax_x - TICK_LEN - 8, yc), fmt(v), f_tick, TEXT, "rm")
    for v, xc in zip(X_TICKS, x_ticks):
        text(f"xtick_{v}", (xc, ax_y + TICK_LEN + 5), fmt(v), f_tick, TEXT, "mt")
    text("xlab", ((panel["x0"] + panel["x1"]) / 2, ax_y + TICK_LEN + 40), XLAB, f_axis, TEXT, "mt")
    text("note", (panel["x0"], ax_y + TICK_LEN + 80), NOTE, f_note, CAPTION, "lt")
    # rotated y label, centred on the panel
    tw = int(dr.textlength(YLAB, font=f_axis)) + 20
    lab = Image.new("L", (tw, 50), 0)
    ImageDraw.Draw(lab).text((tw / 2, 25), YLAB, font=f_axis, fill=255, anchor="mm")
    lab = lab.rotate(90, expand=True)
    cx, cy = 40, (panel["y0"] + panel["y1"]) / 2
    ox, oy = round(cx - lab.width / 2), round(cy - lab.height / 2)
    bg.paste(Image.new("RGB", lab.size, TEXT), (ox, oy), lab)
    lb = np.nonzero(np.asarray(lab) > 0)
    boxes["ylab"] = [ox + int(lb[1].min()), oy + int(lb[0].min()),
                     ox + int(lb[1].max()) + 1, oy + int(lb[0].max()) + 1]

    bg_arr = np.asarray(bg).astype(np.int32)

    # --- 4. composite: grey statistical layer over knocked-out white -----------
    out = bg_arr.copy()
    region = S | Hh
    grey = np.rint(255.0 - k * (255 - MARK_GREY) / D).astype(np.int32)
    out[region] = grey[region][:, None]
    out_img = Image.fromarray(out.astype(np.uint8), "RGB")

    # --- 5. verification -------------------------------------------------------
    o = np.asarray(out_img).astype(np.int32)
    assert o.shape == (H, W, 3)
    assert (o[..., 0] == o[..., 1]).all() and (o[..., 1] == o[..., 2]).all(), "output not neutral"
    og = o[..., 0]
    differs = (o != bg_arr).any(-1)
    k_after = np.where(differs, np.rint((255 - og) * D / (255 - MARK_GREY)), 0).astype(np.int32)
    k_after = np.clip(k_after, 0, D)
    assert (k_after == k).all(), "per-pixel coverage level changed"
    S_after = k_after >= 1
    assert (S_after == S).all(), "support mask changed"
    H_after = hollow_interiors(S_after)
    assert (H_after == Hh).all(), "hollow-marker interiors changed"
    assert (og[Hh] == 255).all(), "hollow interiors not white"
    cc_b = components(S, k)
    cc_a = components(S_after, k_after)
    assert cc_b == cc_a, "support components differ"
    core_b = components(k >= (D + 1) // 2, k)
    core_a = components(k_after >= (D + 1) // 2, k_after)
    assert core_b == core_a, "core (alpha>=0.5) components differ"
    hole_b = components(Hh); hole_a = components(H_after)
    assert hole_b == hole_a
    # no text/axes inside the statistical region's neighbourhood, nothing clipped
    for key, (x0, y0, x1, y1) in boxes.items():
        assert 0 <= x0 and 0 <= y0 and x1 <= W and y1 <= H, f"{key} clipped {boxes[key]}"
        inside = not (x1 <= panel["x0"] - AXIS_W or x0 >= panel["x1"] or
                      y1 <= panel["y0"] or y0 >= panel["y1"] + AXIS_W)
        assert not inside, f"{key} overlaps panel {boxes[key]}"
    keys = sorted(boxes, key=lambda q: boxes[q][1])
    for i, k1 in enumerate(keys):
        for k2 in keys[i + 1:]:
            A, B = boxes[k1], boxes[k2]
            assert A[2] <= B[0] or B[2] <= A[0] or A[3] <= B[1] or B[3] <= A[1], f"{k1}/{k2} overlap"
    dil = region.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            dil |= np.roll(np.roll(region, dy, 0), dx, 1)
    axes_px = (bg_arr[..., 0] == 0)
    assert not (axes_px & dil).any(), "axes touch statistical marks"

    # --- 6. write outputs ------------------------------------------------------
    out_img.save(OUT, format="PNG", optimize=False)
    Image.fromarray((S * 255).astype(np.uint8), "L").save(DATA / "wage_geometry_support_mask.png")
    Image.fromarray(k.astype(np.uint8), "L").save(DATA / "wage_geometry_alpha.png")
    Image.fromarray((Hh * 255).astype(np.uint8), "L").save(DATA / "wage_geometry_hollow_mask.png")
    hollow_cols = sorted({int(round((c["bbox_x0y0x1y1"][0] + c["bbox_x0y0x1y1"][2]) / 2))
                          for c in hole_b})
    nearest = lambda x: X_TICKS[int(np.argmin([abs(x - t) for t in x_ticks]))]
    report = {
        "source": str(SRC.relative_to(ROOT)),
        "source_sha256": SRC_SHA256,
        "source_origin": "img/crime_monthly_earnings_large.png at immutable baseline commit 3c33d79aab0943ff209224029cf80dce9b9f3363 (last changed in 2310c86)",
        "output": str(OUT.relative_to(ROOT)),
        "output_sha256": sha256(OUT),
        "size": [W, H],
        "method": ("coverage level k = clip(B - R, 0, 139) of #2166AC over neutral background; "
                   "support S = {k>=1}; hollow interiors = enclosed non-S; output on S u holes = "
                   "round(255 - k*(255-89)/139); all other pixels redrawn. No values inferred."),
        "mark_grey": MARK_GREY,
        "panel_bounds_px": panel,
        "statistical_bbox_px": stat_bbox,
        "x_tick_centres_px": dict(zip(map(str, X_TICKS), [round(v, 3) for v in x_ticks])),
        "y_tick_centres_px": dict(zip(map(str, Y_TICKS), [round(v, 3) for v in y_ticks])),
        "zero_line_rows_profile": dict(zip(map(str, zr), [round(float(v), 4) for v in zw])),
        "onset_line_cols_profile": dict(zip(map(str, oc), [round(float(v), 4) for v in ow])),
        "support_pixels": int(S.sum()),
        "ringing_pixels_excluded": int(ringing.sum()),
        "hollow_interior_pixels": int(Hh.sum()),
        "hollow_markers_at_event_time": [nearest(x) for x in hollow_cols],
        "text_bboxes_px": boxes,
        "checks": {
            "source_sha256_matches": True,
            "output_size_1600x1050": True,
            "output_neutral_grey": True,
            "per_pixel_coverage_level_identical": True,
            "support_mask_identical": True,
            "hollow_interior_mask_identical_and_white": True,
            "support_components_identical": True,
            "core_alpha_ge_0.5_components_identical": True,
            "text_inside_canvas_outside_panel_no_overlap": True,
            "axes_do_not_touch_marks": True,
        },
        "support_components": cc_b,
        "core_components": core_b,
        "hollow_components": hole_b,
    }
    (DATA / "wage_geometry.json").write_text(json.dumps(report, indent=1) + "\n")
    print(f"ok: {len(cc_b)} support components, {len(hole_b)} hollow interiors, "
          f"output sha256 {report['output_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
