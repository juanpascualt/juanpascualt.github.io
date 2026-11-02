#!/usr/bin/env python3
"""Copy the exact saved aggregate estimates behind three website figures.

No estimation happens here. Rows are copied *verbatim* (string fields, no
re-formatting) from saved project outputs into scripts/figures/data/, and the
SHA-256 of every source file is recorded in data/provenance.json.

Sources (read-only; outside this repository):
  * Crime gap  : Vocational 5_Package/2_Out/_baseline_tables_2026-07-30/
                 4_ddd/01_did_validation/es_leads_lags_ddd.csv  (estimator == csdid_nt)
                 + anticipation_ddd.tex (post-average ATT / p / pre-test, quoted text)
  * Reshuffling: Pla de Xoc Data/Temp/idescat_onsite/mirror_staging/Package/Out/
                 Tables/06_JP_continuous_did/published_quotas/
                 02_eventstudy_number_inf1_bysign.csv          (sign_group == UP)
                 03_eventstudy_number_inf1_up_by_school_type.csv

Run only when the sources are reachable (Dropbox). The committed CSVs are the
operational plotting inputs; 03_verify.py re-checks them against the sources.
"""
import csv
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "data")

# Dropbox root is machine-specific; override with FIG_DROPBOX_ROOT.
DROPBOX = os.environ.get("FIG_DROPBOX_ROOT",
                         os.path.expanduser("~/Library/CloudStorage/Dropbox"))
VOC = os.path.join(DROPBOX, "Vocational/5_Package/2_Out/_baseline_tables_2026-07-30/4_ddd/01_did_validation")
PDX = os.path.join(DROPBOX, "Pla de Xoc/Data/Temp/idescat_onsite/mirror_staging/Package/Out/"
                   "Tables/06_JP_continuous_did/published_quotas")

SOURCES = {
    "crime_gap_es": os.path.join(VOC, "es_leads_lags_ddd.csv"),
    "crime_gap_agg": os.path.join(VOC, "anticipation_ddd.tex"),
    "reshuffling_up": os.path.join(PDX, "02_eventstudy_number_inf1_bysign.csv"),
    "reshuffling_by_type": os.path.join(PDX, "03_eventstudy_number_inf1_up_by_school_type.csv"),
}

# (source key, output file, row filter, columns kept verbatim)
EXTRACTS = [
    ("crime_gap_es", "crime_gap_es.csv",
     lambda r: r["estimator"] == "csdid_nt" and -6 <= int(r["event_time"]) <= 3,
     ["event_time", "att", "se", "ci_lower", "ci_upper", "estimator"]),
    ("reshuffling_up", "reshuffling_up_es.csv",
     lambda r: r["sign_group"] == "UP",
     ["year", "est", "se", "pval", "ci_lo", "ci_hi", "sign_group", "n_schools"]),
    ("reshuffling_by_type", "reshuffling_by_type_es.csv",
     lambda r: True,
     ["year", "school_type", "est", "se", "pval", "ci_lo", "ci_hi", "n_schools"]),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    missing = [p for p in SOURCES.values() if not os.path.exists(p)]
    if missing:
        sys.exit("Source not reachable: " + "; ".join(missing))
    os.makedirs(OUT, exist_ok=True)
    prov = {"generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "note": "Rows copied verbatim from saved outputs; no estimation.",
            "sources": {}, "extracts": {}}
    for key, path in SOURCES.items():
        st = os.stat(path)
        prov["sources"][key] = {
            "path": "<Dropbox>/" + os.path.relpath(path, DROPBOX), "sha256": sha256(path), "bytes": st.st_size,
            "mtime_local": datetime.fromtimestamp(st.st_mtime).isoformat(timespec="seconds")}
    for key, fname, keep, cols in EXTRACTS:
        with open(SOURCES[key], newline="", encoding="utf-8") as f:
            rows = [r for r in csv.DictReader(f) if keep(r)]
        out = os.path.join(OUT, fname)
        with open(out, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f, lineterminator="\n")
            w.writerow(cols)
            for r in rows:
                w.writerow([r[c] for c in cols])
        prov["extracts"][fname] = {"source": key, "n_rows": len(rows), "columns": cols,
                                   "sha256": sha256(out)}
        print(f"{fname}: {len(rows)} rows from {key}")
    # Post-period average ATT / p / pre-test for the crime gap: the
    # "Anticipation = 0" column of anticipation_ddd.tex, copied as printed.
    tex = open(SOURCES["crime_gap_agg"], encoding="utf-8").read()
    m_att = re.search(r"ATT \(post average\) & (-?[0-9.]+)\**\s*\(([0-9.]+)\)", tex)
    m_p = re.search(r"\$p\$-value & \$([0-9.]+)\$", tex)
    m_pre = re.search(r"Joint pre-test \(Wald\) \$p\$ & \$([0-9.]+)\$", tex)
    if not (m_att and m_p and m_pre):
        sys.exit("Could not parse anticipation_ddd.tex")
    agg = {"post_avg_att": m_att.group(1), "post_avg_se": m_att.group(2),
           "post_avg_p": m_p.group(1), "pretest_wald_p": m_pre.group(1),
           "source": "crime_gap_agg", "column": "Anticipation = 0"}
    agg_path = os.path.join(OUT, "crime_gap_aggregate.json")
    with open(agg_path, "w", encoding="utf-8") as f:
        json.dump(agg, f, indent=2)
        f.write("\n")
    prov["extracts"]["crime_gap_aggregate.json"] = {"source": "crime_gap_agg",
                                                    "sha256": sha256(agg_path)}
    print("crime_gap_aggregate.json:", agg)
    with open(os.path.join(OUT, "provenance.json"), "w", encoding="utf-8") as f:
        json.dump(prov, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
