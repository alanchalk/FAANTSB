"""Black-box diagnostics for the region-free CatBoost champion.

Chapter 9 of the monograph compares an explainable GLM against a GBM benchmark
using model-agnostic methods. Three of its four exhibits need the GBM itself,
not its stored predictions:

* permutation feature importance, so the GLM's ranking can be compared with the
  GBM's (Table 08b_01b) - this is the chapter's central method, and without the
  GBM side there is nothing to compare;
* partial dependence, so the GBM's fitted shape for a feature can be set against
  the GLM's relativities (Figure 08f_pdp), plus the histogram of per-row ratios
  behind that average (Figure 08f_03ratios);
* pairwise interaction strength, pl_A + pl_B - pl_AB (Table 08d_01pfictb). This
  belongs on the GBM: the point is to find interactions the GBM carries and the
  GLM lacks. Computed on a GLM with no interaction terms the measure is close to
  zero by construction, and says nothing;
* train against cross-validated performance as trees are added (Figure 08c_01),
  which is the chapter's own evidence that the GBM carries high variance;
* SHAP contributions for a handful of individual policies. Every other method in
  the chapter is global, and the chapter's own caveat on partial dependence is
  that a global average may describe no policy in the book. A local method is
  the answer to that caveat. CatBoost computes exact TreeSHAP, and because the
  contributions are on the link scale, exponentiating them gives multiplicative
  factors - the same form an actuary reads off a GLM.

GLMStudio imports champions as predictions only, so it can do none of these. It
is a product gap, filed. Until it closes, these are computed here, next to the
script that trains the champion, and written to a JSON snapshot that Guided
Reading renders deterministically. Nothing here runs in the application.

Method follows the monograph. Importance is permutation-based, computed for each
cross-validation model on the fold held out from it and averaged over folds
(section 9.5), measured in pseudo-R2 so it is the same metric as the rest of the
chapter. Partial dependence sets the feature to a fixed value for every row,
re-scores, and takes the ratio of mean predictions to an anchor value.

Usage (from the package root, needs the env with catboost + pyarrow + pandas):
  python data-raw/champion_diagnostics_ex_region.py
Override paths with FAANTSB_PARQUET / DIAGNOSTICS_OUT.
"""
from __future__ import annotations

import json
import os
import time

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from catboost import CatBoostRegressor, Pool

from champion_catboost_ex_region import CATEGORICAL, FEATURES, NUMERIC, PARAMS

HERE = os.path.dirname(os.path.abspath(__file__))
PARQUET = os.environ.get(
    "FAANTSB_PARQUET",
    os.path.join(HERE, "..", "inst", "extdata", "us_acft_faa_ntsb_freq_v1.parquet"),
)
OUT = os.environ.get(
    "DIAGNOSTICS_OUT",
    os.path.join(HERE, "..", "inst", "extdata",
                 "us_acft_faa_ntsb_freq_v1_champion_diagnostics_ex_region.json"),
)

DESIGN_FOLDS = range(1, 8)
SEED = 2025
# Tree counts for the variance curve. Dense early, where the gap opens.
TREE_COUNTS = [10, 25, 50, 100, 150, 200, 300, 400, 500, 650, 800, 1000]
# Partial dependence is computed for every numeric feature, so the renderer can
# choose the one the importance comparison flags without a second fit.
PDP_MAX_POINTS = 30
RATIO_BINS = 40
# Policies to explain locally, chosen by predicted-frequency quantile so the
# selection is deterministic and spans the book rather than cherry-picking.
SHAP_QUANTILES = [0.05, 0.50, 0.95]
SHAP_TOP_FEATURES = 8
# Pairwise interaction strength is quadratic in features, so it is computed over
# the strongest main effects rather than all 153 pairs. The chapter only ever
# inspects the top few candidates.
PAIRWISE_TOP_N = 10


def pseudo_r2(y: np.ndarray, w: np.ndarray, mu: np.ndarray) -> float:
    """Exposure-weighted Poisson pseudo-R2 against the weighted-mean null."""
    keep = w > 0
    y, w, mu = y[keep], w[keep], np.clip(mu[keep], 1e-12, None)

    def deviance(m: np.ndarray) -> float:
        term = np.where(y > 0, y * np.log(np.where(y > 0, y, 1.0) / m), 0.0)
        return 2.0 * float(np.sum(w * (term - (y - m))))

    null = np.full_like(y, float(np.sum(w * y) / np.sum(w)))
    return 1.0 - deviance(mu) / deviance(null)


def _grid(values: np.ndarray) -> list[float]:
    """Feature values to score at: every distinct value when there are few,
    otherwise quantiles, which keeps sparse tails from dominating the axis."""
    uniq = np.unique(values[~np.isnan(values)])
    if len(uniq) <= PDP_MAX_POINTS:
        return [float(v) for v in uniq]
    qs = np.linspace(0.0, 0.99, PDP_MAX_POINTS)
    return [float(v) for v in np.unique(np.quantile(uniq, qs))]


def main() -> None:
    t0 = time.time()
    df = pq.read_table(PARQUET).to_pandas()
    for c in CATEGORICAL:
        df[c] = df[c].astype("string").fillna("NA").astype(str)
    for c in NUMERIC:
        df[c] = df[c].astype(float)
    print(f"[{time.time()-t0:5.0f}s] loaded {len(df):,} rows, {len(FEATURES)} features")

    design = df["fold"].isin(DESIGN_FOLDS)
    Xd, yd = df.loc[design, FEATURES], df.loc[design, "freq_cl"]
    wd, fd = df.loc[design, "ex"], df.loc[design, "fold"]

    rng = np.random.default_rng(SEED)
    fold_models: list[tuple[int, CatBoostRegressor, float]] = []
    per_fold_importance: dict[str, list[float]] = {f: [] for f in FEATURES}
    variance_curve = {"trees": [], "train": [], "cv": []}
    curve_train: dict[int, list[float]] = {k: [] for k in TREE_COUNTS}
    curve_cv: dict[int, list[float]] = {k: [] for k in TREE_COUNTS}

    for fold in DESIGN_FOLDS:
        tr, va = (fd != fold), (fd == fold)
        model = CatBoostRegressor(**PARAMS)
        model.fit(
            Pool(Xd[tr], yd[tr], cat_features=CATEGORICAL, weight=wd[tr]),
            eval_set=Pool(Xd[va], yd[va], cat_features=CATEGORICAL, weight=wd[va]),
            use_best_model=True,
        )

        # Importance on the fold this model never saw, in pseudo-R2 units.
        Xva, yva, wva = Xd[va], yd[va].to_numpy(), wd[va].to_numpy()
        base = pseudo_r2(yva, wva, model.predict(Xva))
        for feature in FEATURES:
            shuffled = Xva.copy()
            shuffled[feature] = rng.permutation(shuffled[feature].to_numpy())
            per_fold_importance[feature].append(base - pseudo_r2(yva, wva, model.predict(shuffled)))

        fold_models.append((fold, model, base))
        print(f"[{time.time()-t0:5.0f}s] fold {fold}: trees={model.tree_count_} base_pr2={base:.5f}")

    # The variance curve needs its own fits. The models above stop at their best
    # iteration, which differs by fold, so scoring them at 800 trees would average
    # only the folds that got that far - a curve whose points are not comparable.
    # These run the full path instead, so every point averages all seven folds.
    for fold in DESIGN_FOLDS:
        tr, va = (fd != fold), (fd == fold)
        full = CatBoostRegressor(**PARAMS)
        full.fit(Pool(Xd[tr], yd[tr], cat_features=CATEGORICAL, weight=wd[tr]), use_best_model=False)
        Xtr, ytr, wtr = Xd[tr], yd[tr].to_numpy(), wd[tr].to_numpy()
        Xva, yva, wva = Xd[va], yd[va].to_numpy(), wd[va].to_numpy()
        for k in TREE_COUNTS:
            if k > full.tree_count_:
                continue
            curve_train[k].append(pseudo_r2(ytr, wtr, full.predict(Xtr, ntree_end=k)))
            curve_cv[k].append(pseudo_r2(yva, wva, full.predict(Xva, ntree_end=k)))
        print(f"[{time.time()-t0:5.0f}s] curve fold {fold}: trees={full.tree_count_}")

    for k in TREE_COUNTS:
        if len(curve_cv[k]) == len(list(DESIGN_FOLDS)):
            variance_curve["trees"].append(k)
            variance_curve["train"].append(float(np.mean(curve_train[k])))
            variance_curve["cv"].append(float(np.mean(curve_cv[k])))
    variance_curve["folds_per_point"] = len(list(DESIGN_FOLDS))

    importance = sorted(
        (
            {
                "feature": f,
                "importance": float(np.mean(v)),
                "se": float(np.std(v, ddof=1) / np.sqrt(len(v))),
            }
            for f, v in per_fold_importance.items()
        ),
        key=lambda r: -r["importance"],
    )
    print(f"[{time.time()-t0:5.0f}s] importance done; top: {importance[0]['feature']}")

    # Pairwise interaction strength on the GBM, reusing the fold models. For a
    # pair that does not interact, permuting both costs what permuting each
    # costs separately, so the measure is zero; a positive value means the pair
    # interacts with each other or with a common third feature.
    candidates = [r["feature"] for r in importance[:PAIRWISE_TOP_N]]
    pair_scores: dict[tuple[str, str], list[float]] = {}
    for fold, model, base in fold_models:
        va = (fd == fold)
        Xva, yva, wva = Xd[va], yd[va].to_numpy(), wd[va].to_numpy()
        single = {f: per_fold_importance[f][fold - 1] for f in candidates}
        for i, a in enumerate(candidates):
            for b in candidates[i + 1:]:
                both = Xva.copy()
                both[a] = rng.permutation(both[a].to_numpy())
                both[b] = rng.permutation(both[b].to_numpy())
                pl_ab = base - pseudo_r2(yva, wva, model.predict(both))
                pair_scores.setdefault((a, b), []).append(single[a] + single[b] - pl_ab)
        print(f"[{time.time()-t0:5.0f}s] pairs fold {fold} done")

    interactions = sorted(
        (
            {
                "feature_a": a, "feature_b": b,
                "strength": float(np.mean(v)),
                "se": float(np.std(v, ddof=1) / np.sqrt(len(v))),
            }
            for (a, b), v in pair_scores.items()
        ),
        key=lambda r: -r["strength"],
    )
    print(f"[{time.time()-t0:5.0f}s] top pair: {interactions[0]['feature_a']} x {interactions[0]['feature_b']}")

    # Partial dependence uses the design model, which is the one whose
    # predictions were published as the champion.
    design_model = CatBoostRegressor(**PARAMS)
    design_model.fit(Pool(Xd, yd, cat_features=CATEGORICAL, weight=wd), use_best_model=False)
    print(f"[{time.time()-t0:5.0f}s] design model: trees={design_model.tree_count_}")

    pdp: dict[str, dict] = {}
    ratios: dict[str, dict] = {}
    for feature in NUMERIC:
        grid = _grid(Xd[feature].to_numpy())
        anchor = grid[0]
        means = []
        preds_at: dict[float, np.ndarray] = {}
        for value in grid:
            probe = Xd.copy()
            probe[feature] = value
            p = design_model.predict(probe)
            preds_at[value] = p
            means.append(float(np.mean(p)))
        base_mean = means[0]
        pdp[feature] = {
            "x": grid,
            "relativity": [float(m / base_mean) for m in means],
            "anchor": anchor,
            "mean_prediction": means,
        }

        # The spread behind the average: per-row ratios between two values,
        # which is what the partial-dependence average conceals. The comparison
        # point is the grid value nearest the feature's 90th percentile - high
        # enough to be interesting, common enough that the ratios describe real
        # policies rather than a sparse tail.
        target = float(np.quantile(Xd[feature].to_numpy(), 0.90))
        high = min((g for g in grid if g > anchor), key=lambda g: abs(g - target), default=grid[-1])
        row_ratio = preds_at[high] / np.clip(preds_at[anchor], 1e-12, None)
        counts, edges = np.histogram(row_ratio, bins=RATIO_BINS)
        ratios[feature] = {
            "low": anchor,
            "high": high,
            "bin_edges": [float(e) for e in edges],
            "counts": [int(c) for c in counts],
            "mean_prediction_ratio": float(np.mean(preds_at[high]) / np.mean(preds_at[anchor])),
            "row_ratio_min": float(np.min(row_ratio)),
            "row_ratio_max": float(np.max(row_ratio)),
        }
        print(f"[{time.time()-t0:5.0f}s] pdp {feature}: {len(grid)} points")

    # Local explanations. Shapley contributions are on the link scale and sum,
    # with the base value, to the raw prediction; exponentiating a contribution
    # turns it into a multiplicative factor.
    design_pred = design_model.predict(Xd)
    # Order matters: each pick is labelled with the quantile that chose it, so
    # the list must stay parallel to SHAP_QUANTILES.
    picks = [int(np.argmin(np.abs(design_pred - np.quantile(design_pred, q)))) for q in SHAP_QUANTILES]
    sample = Xd.iloc[picks]
    shap_raw = design_model.get_feature_importance(
        Pool(sample, cat_features=CATEGORICAL), type="ShapValues"
    )
    base_value = float(shap_raw[0, -1])
    shap_rows = []
    for i, (q, row_idx) in enumerate(zip(SHAP_QUANTILES, picks)):
        contributions = shap_raw[i, :-1]
        order = np.argsort(-np.abs(contributions))[:SHAP_TOP_FEATURES]
        shap_rows.append({
            "quantile": q,
            "prediction": float(design_pred[row_idx]),
            "base_value": base_value,
            "base_factor": float(np.exp(base_value)),
            "contributions": [
                {
                    "feature": FEATURES[j],
                    "value": (
                        float(sample.iloc[i, j]) if FEATURES[j] in NUMERIC else str(sample.iloc[i, j])
                    ),
                    "contribution": float(contributions[j]),
                    "factor": float(np.exp(contributions[j])),
                }
                for j in order
            ],
            "other_contribution": float(np.sum(np.delete(contributions, order))),
        })
    print(f"[{time.time()-t0:5.0f}s] shap: {len(shap_rows)} policies explained")

    snapshot = {
        "schema_version": 1,
        "generated_by": "FAANTSB data-raw/champion_diagnostics_ex_region.py",
        "champion": "champion:catboost_ex_region",
        "dataset": "us_acft_faa_ntsb_freq_v1",
        "features": FEATURES,
        "metric": "pseudo-R2, Poisson deviance, exposure-weighted",
        "folds": {"design": list(DESIGN_FOLDS), "test": [99]},
        "importance": {
            "method": (
                "permutation, computed for each cross-validation model on the fold "
                "held out from it and averaged over the folds"
            ),
            "seed": SEED,
            "features": importance,
        },
        "interactions": {
            "method": (
                "pl_A + pl_B - pl_AB per fold on the held-out fold, averaged over folds, "
                "over the strongest main effects"
            ),
            "candidates": PAIRWISE_TOP_N,
            "pairs": interactions,
        },
        "partial_dependence": {
            "method": "feature set to each grid value for every design row, mean prediction, ratio to the anchor",
            "features": pdp,
        },
        "row_ratios": {
            "method": "per-row ratio of predictions between two feature values, binned",
            "features": ratios,
        },
        "local_explanations": {
            "method": (
                "exact TreeSHAP on the design model for policies at fixed predicted-frequency "
                "quantiles; contributions are on the link scale and exponentiate to factors"
            ),
            "quantiles": SHAP_QUANTILES,
            "policies": shap_rows,
        },
        "variance_curve": {
            "method": "seven fold models fitted over the full tree path, scored at each tree count on their own held-out fold and on their training rows, averaged over all seven",
            **variance_curve,
        },
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(snapshot, fh, indent=2, allow_nan=False)
    print(f"[{time.time()-t0:5.0f}s] wrote {OUT}")


if __name__ == "__main__":
    main()
