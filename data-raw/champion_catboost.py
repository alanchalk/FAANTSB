"""Train the CatBoost champion (black-box benchmark) on the published FAA-NTSB
dataset and write out-of-fold / in-sample / test predictions.

This RUNS the model -- it does not copy stored predictions. It reproduces the
monograph's gradient-boosting benchmark: Poisson loss, the dataset's own fold
scheme, and the exact hyperparameters baked into the original .cbm models.
Predictions correlate ~0.98 with the monograph's stored predictions; the
residual is CatBoost-version drift plus the published dataset carrying raw
numerics where the monograph used winsorised `_tt` columns (negligible for a
tree model, which is near-invariant to monotone transforms).

Feature set: the 21 features of the monograph champion mapped to the published
columns. The four `_tt` numerics become their raw equivalents; `yrs_since_cert`
(~ acft_age) and `year_mfr_m` (a missing-value indicator) are dropped -- neither
is in the published dataset, and both are near-redundant for the tree.

Output (one row per sample row -- the champion-import contract):
  var_u      = unique_id_line
  pred_oob   = out-of-fold (CV) prediction
  pred_ib    = in-sample prediction (mean of the other folds' models)
  pred_test  = design-model prediction (all CV folds)

Usage (from the package root, needs python with catboost + pyarrow + pandas):
  python data-raw/champion_catboost.py
Override paths with FAANTSB_PARQUET / CHAMPION_OUT.
"""
from __future__ import annotations

import os
import time

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from catboost import CatBoostRegressor, Pool

HERE = os.path.dirname(os.path.abspath(__file__))
PARQUET = os.environ.get(
    "FAANTSB_PARQUET",
    os.path.join(HERE, "..", "inst", "extdata", "us_acft_faa_ntsb_freq_v1.parquet"),
)
OUT = os.environ.get(
    "CHAMPION_OUT",
    os.path.join(HERE, "..", "inst", "extdata",
                 "us_acft_faa_ntsb_freq_v1_champion_catboost.parquet"),
)

NUMERIC = ["nu_registered", "faa_acft_no_seats", "faa_acft_speed", "acft_age"]
CATEGORICAL = [
    "type_registrant", "region", "street2_ind", "co_ownership", "airworthiness",
    "operation", "kit_indyn", "faa_acft_type_acft", "faa_acft_type_eng",
    "faa_acft_ac_cat", "faa_acft_build_cert_ind", "faa_acft_no_eng",
    "faa_acft_ac_weight", "faa_eng_hp_char", "faa_eng_thrust_char",
]
FEATURES = NUMERIC + CATEGORICAL

# Deliberately EXCLUDED: `dereg` (and `source`) -- the deregistered-aircraft
# data-source leak. It is a student trap in the published dataset (it predicts
# well but is not a legitimate rating variable). The champion benchmark must not
# use it, so it is never added to FEATURES.
assert "dereg" not in FEATURES and "source" not in FEATURES

# Exact hyperparameters from the stored 04a_ctb_*.cbm (flat_params + tree/boost
# options), so a fresh CatBoost reproduces the monograph model regardless of the
# installed version's defaults -- the learning rate especially is auto-selected
# unless pinned.
PARAMS = dict(
    iterations=1000, learning_rate=0.03, depth=6, l2_leaf_reg=3,
    random_strength=1, border_count=254, one_hot_max_size=2,
    max_ctr_complexity=4, leaf_estimation_iterations=10,
    bootstrap_type="MVS", subsample=0.8,
    loss_function="Poisson", eval_metric="Poisson", random_seed=2024,
    thread_count=-1, verbose=False,
)


def main() -> None:
    t0 = time.time()
    df = pq.read_table(PARQUET).to_pandas()
    for c in CATEGORICAL:
        df[c] = df[c].astype("string").fillna("NA").astype(str)
    for c in NUMERIC:
        df[c] = df[c].astype(float)
    print(f"[{time.time()-t0:5.0f}s] loaded {len(df):,} rows from {os.path.basename(PARQUET)}")

    X_all = df[FEATURES]
    design = df["fold"].isin(range(1, 8))
    Xd = df.loc[design, FEATURES]
    yd = df.loc[design, "freq_cl"]
    wd = df.loc[design, "ex"]
    fd = df.loc[design, "fold"]

    # one model per CV fold, predicting on every row
    fold_pred: dict[int, np.ndarray] = {}
    for f in range(1, 8):
        tr, va = (fd != f), (fd == f)
        m = CatBoostRegressor(**PARAMS)
        m.fit(
            Pool(Xd[tr], yd[tr], cat_features=CATEGORICAL, weight=wd[tr]),
            eval_set=Pool(Xd[va], yd[va], cat_features=CATEGORICAL, weight=wd[va]),
            use_best_model=True,
        )
        fold_pred[f] = m.predict(X_all)
        print(f"[{time.time()-t0:5.0f}s] fold {f}: trees={m.tree_count_}")

    # design model trained on all CV folds (1..7)
    md = CatBoostRegressor(**PARAMS)
    md.fit(Pool(Xd, yd, cat_features=CATEGORICAL, weight=wd), use_best_model=False)
    pred_test = md.predict(X_all)
    print(f"[{time.time()-t0:5.0f}s] design model: trees={md.tree_count_}")

    out = pd.DataFrame({"var_u": df["unique_id_line"].to_numpy()})
    out["pred_oob"] = np.nan
    out["pred_ib"] = np.nan
    for f in range(1, 8):
        sel = (df["fold"] == f).to_numpy()
        others = [fold_pred[i][sel] for i in range(1, 8) if i != f]
        out.loc[sel, "pred_oob"] = fold_pred[f][sel]
        out.loc[sel, "pred_ib"] = np.mean(others, axis=0)
    out["pred_test"] = pred_test

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.to_parquet(OUT, index=False)
    print(f"[{time.time()-t0:5.0f}s] wrote {OUT} ({len(out):,} rows)")


if __name__ == "__main__":
    main()
