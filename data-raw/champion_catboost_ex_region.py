"""Train the CatBoost champion excluding region, and write out-of-fold /
in-sample / test predictions.

Copy of champion_catboost.py with one change: region is dropped from the
feature set. Hyperparameters, fold scheme, loss, weight and output contract are
identical, so the two champions are comparable and the difference between them
is the value of region alone.

Why: the sibling script already excludes dereg and source as the
deregistered-aircraft data-source leak. Region carries the same information
another way. Where the source file leaves region blank it is filled with "X",
and those are the dereg-file rows, which are far claim-heavier than the rest.
An "X" region is therefore a provenance marker rather than a location, and a
tree splits on it to read the outcome. Excluding dereg while keeping region
guards the front door and leaves the back one open.

This is the champion for the Guided Reading chapters whose GLM also drops
region. A GLM without the leak, compared against a champion that still has it,
would flatter the black box for the wrong reason.

Expect a LOWER holdout pseudo-R2 than champion_catboost.py, whose published
values are 0.1653 in-sample and 0.1775 on fold 99. That drop is the leak being
given up, and is the purpose of this variant rather than a regression.

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

Training performance is computed here and shipped in the metadata beside the
predictions. It cannot be recovered downstream: the prediction published for a
design row is the out-of-fold one, so nothing that consumes this file can score
the design model on the rows it was actually fitted to. The held-out figure is
recomputed alongside it as a check against the value published in the catalogue.

Output (one row per sample row -- the champion-import contract):
  var_u      = unique_id_line
  prediction = a single prediction whose meaning is fold-dependent: the
               out-of-fold (CV) prediction on the design folds (1-7), and the
               design-model prediction on the held-out test fold (99). The
               GLMStudio importer routes it onto the preds-table diagonal
               (design -> pred_oob, test -> pred_test). No in-sample column is
               emitted -- a black-box champion has no in-fold/out-of-fold split.

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
                 "us_acft_faa_ntsb_freq_v1_champion_catboost_ex_region.parquet"),
)

NUMERIC = ["nu_registered", "faa_acft_no_seats", "faa_acft_speed", "acft_age"]
# Region excluded here, which takes the feature set from 19 to 18. See the
# module docstring for why it is a leak and not a location.
CATEGORICAL = [
    "type_registrant", "street2_ind", "co_ownership", "airworthiness",
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
# Region is that same leak reached another way, so it is asserted too: without
# this, someone reading the comment above could conclude the leak is handled
# and add region back.
assert "region" not in FEATURES

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


def pseudo_r2(y: np.ndarray, w: np.ndarray, mu: np.ndarray) -> float:
    """Exposure-weighted Poisson pseudo-R2 against the weighted-mean null, the
    metric the monograph reports for this dataset."""
    keep = w > 0
    y, w, mu = y[keep], w[keep], np.clip(mu[keep], 1e-12, None)

    def deviance(m: np.ndarray) -> float:
        term = np.where(y > 0, y * np.log(np.where(y > 0, y, 1.0) / m), 0.0)
        return 2.0 * float(np.sum(w * (term - (y - m))))

    null = np.full_like(y, float(np.sum(w * y) / np.sum(w)))
    return 1.0 - deviance(mu) / deviance(null)


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

    # Single prediction column (the champion-import contract). Its meaning is
    # fold-dependent: the out-of-fold prediction on the design folds, and the
    # design-model prediction on the held-out test fold. The GLMStudio importer
    # routes it onto the preds-table diagonal (design -> pred_oob, test ->
    # pred_test); no in-sample column is emitted.
    prediction = pred_test.copy()                  # test fold (99): design-model prediction
    for f in range(1, 8):
        sel = (df["fold"] == f).to_numpy()
        prediction[sel] = fold_pred[f][sel]        # design folds (1-7): out-of-fold prediction
    out = pd.DataFrame({
        "var_u": df["unique_id_line"].to_numpy(),
        "prediction": prediction,
    })

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.to_parquet(OUT, index=False)
    print(f"[{time.time()-t0:5.0f}s] wrote {OUT} ({len(out):,} rows)")

    # Champion provenance metadata, shipped next to the predictions. GLMStudio
    # surfaces this on the champion's review page (model type, features, target).
    import json
    from datetime import datetime, timezone
    # Scored on the rows the design model was fitted to, which is what "training
    # performance" means and what no consumer of the predictions can recompute.
    train_pr2 = pseudo_r2(yd.to_numpy(), wd.to_numpy(), md.predict(Xd))
    test_rows = df["fold"] == 99
    held_out_pr2 = pseudo_r2(
        df.loc[test_rows, "freq_cl"].to_numpy(),
        df.loc[test_rows, "ex"].to_numpy(),
        md.predict(df.loc[test_rows, FEATURES]),
    )
    print(f"[{time.time()-t0:5.0f}s] pseudo-R2: training {train_pr2:.5f}, held out {held_out_pr2:.5f}")

    meta = {
        "model_type": "CatBoost GBM",
        "metric": "pseudo-R2, Poisson deviance, exposure-weighted",
        "pseudo_r2_train": train_pr2,
        "pseudo_r2_held_out": held_out_pr2,
        "loss": PARAMS["loss_function"],
        "target": "freq_cl",
        "features": FEATURES,
        "n_features": len(FEATURES),
        "n_rows": int(len(out)),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    meta_path = OUT.replace(".parquet", "_meta.json")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"[{time.time()-t0:5.0f}s] wrote {meta_path}")


if __name__ == "__main__":
    main()
