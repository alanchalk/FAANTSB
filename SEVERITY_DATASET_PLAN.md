# FAA/NTSB hull-severity dataset plan

## Objective

Create a simulated aircraft hull-severity dataset paired with `us_acft_faa_ntsb_freq_v2`. It will support a frequency–severity case study and, later, GLMStudio Combine.

The target represents aircraft physical-damage cost. It is not an observed insurance payment and excludes passenger injury, liability and other third-party losses.

Proposed published name: `us_acft_faa_ntsb_sev_v1`.

## Repository layout

Keep this plan at the repository root. Keep the build in the existing `data-raw/` pipeline so that frequency and severity share the same FAA/NTSB preparation.

```text
FAANTSB/
├── SEVERITY_DATASET_PLAN.md
├── rawdata/
│   ├── ReleasableAircraft/          # existing FAA source convention
│   ├── NTSB/                        # frozen NTSB database/export
│   └── HullSeverity/                # optional calibration material
├── data-raw/
│   ├── 01a_read_data.R
│   ├── 01b_clean1.R
│   ├── 02a_build_hull_claims.R
│   ├── 02b_build_synthetic_values.R
│   ├── 02c_simulate_hull_losses.R
│   ├── derived/                     # ignored private audit and build outputs
│   └── us_acft_faa_ntsb_sev_v1.R   # final dataset build, following package convention
├── data/                            # existing packaged FAA clean data
└── inst/extdata/                    # published Parquet dataset
```

The numbered scripts prepare the reusable inputs. The dataset-named script performs final selection and publication, matching the existing frequency-build convention.

Add `rawdata/` to `.gitignore` and `.Rbuildignore`. Raw files must not be committed unless redistribution is permitted. The build must use frozen local inputs rather than live websites. Freeze the ZIP-code input currently referenced through a machine-specific Dropbox path as part of this work.

## Published and audit data

### Student-facing modelling dataset

The published Parquet file contains one row per in-scope NTSB aircraft occurrence, not merely one row per event. Its stable key is the NTSB event identifier plus the NTSB aircraft key or sequence.

It contains:

- the simulated hull-loss target;
- simulated hull value at the accident-date price level;
- hull loss as a proportion of that value, as an alternative target;
- the matched frequency-v2 row identifier and inherited fold;
- only pre-event FAA rating factors;
- the same names, types, category cleaning and levels as the corresponding frequency-v2 columns.

It must not publish NTSB damage class as a modelling column. Deregistration-derived fields must also be excluded because destruction can itself cause deregistration. Hull value is known before the loss and is published with the corresponding loss ratio so students can compare monetary severity and loss-ratio models. The amount and ratio are alternative targets and must not be used to predict each other.

### Audit dataset

A separate, unpublished audit object under ignored `data-raw/derived/` retains:

- the event-aircraft key and selected FAA registration line;
- NTSB event type and damage class;
- synthetic aircraft value and its components;
- sampled value uncertainty;
- hidden total-loss indicator and claim-cost components;
- resulting damage ratio;
- final simulated loss;
- match diagnostics and exclusion reason.

This separation makes the simulation reproducible without giving students target leakage.

## Population and matching

### Population

- Pair severity with the seed-2024, 24% aircraft-year population published as frequency v2.
- Use frequency v2 because it fixes the deregistered-aircraft region leak in v1.
- Include every NTSB occurrence counted in frequency v2 so that the aggregate frequency count and number of severity records agree exactly.
- This includes the small number of incidents and occurrences with blank or unknown damage that the existing frequency target counts as claims.
- Assign blank or unknown damage a broad low-to-moderate damage distribution rather than dropping the claim. Keep event type and damage class in the audit data only.

### One deterministic FAA match per aircraft occurrence

The existing many-to-many N-number merge cannot be used directly at event grain. For each NTSB aircraft occurrence:

1. consider FAA registration lines with the same N-number and compatible make;
2. prefer a registration interval containing the event date;
3. otherwise choose the permitted candidate nearest to the event date;
4. resolve any remaining tie deterministically using the FAA registration-line identifier;
5. retain the candidate count, match rule and date distance in the audit table.

Exactly one FAA registration line may be selected. Ambiguous or unmatched occurrences must be reported rather than duplicated.

The severity row then joins to the corresponding frequency-v2 aircraft-year row. It inherits that row's `unique_id_line` and `fold`; it must not calculate a new fold. This keeps the paired datasets aligned with the existing convention. Changing both datasets to N-number-level folds is a possible later revision, not part of severity v1.

## Build steps

### 02a — Build the event-aircraft claims table

1. Put a current frozen NTSB database or export under `rawdata/NTSB/`.
2. Remove the machine-specific NTSB source path.
3. Retain the NTSB event and aircraft keys, event type, event date and damage class.
4. Apply the deterministic FAA matching rule above.
5. Join each selected match to the corresponding frequency-v2 sample row and inherit its fold.
6. Reconcile source aircraft occurrences, matched occurrences, frequency-v2 sample matches and each exclusion category.

Avoid copying the current matching block. Either make `01a_read_data.R` save the event-level match as an additional intermediate object or extract only the shared matching operation into one small function.

### 02b — Build synthetic aircraft values

Use a documented synthetic value formula by default. It should use pre-event FAA information such as aircraft type, engine type, engine count, seats, cruise speed and age at the occurrence. Calculate valuation age from manufacture year where available, with the published frequency-v2 `acft_age` as the documented fallback.

The formula should contain:

- a base value by broad aircraft class;
- transparent multipliers for capacity and performance;
- a monotonic depreciation curve by age;
- stable random value uncertainty within otherwise similar aircraft.

Any public price sources are calibration evidence only. They may inform broad levels but are not required inputs and are not redistributed. Record any calibration sources and retrieval dates in the methodology.

Use a stable hash of the aircraft occurrence or aircraft identifier for random draws so rebuilding gives the same value.

### 02c — Simulate hull losses

Use the NTSB damage class only to set a hidden total-loss probability and a partial-repair cost level. Total losses should respond to aircraft value, coverage, salvage and recovery. Partial repairs should respond only weakly to full aircraft value and include broad component and labour uncertainty. This makes accident severity important without publishing post-event information.

Fit a fixed Gamma/log reference GLM using only published pre-event factors. Its rebased held-out PR-squared should be 20–32%, with the remaining variation arising from hidden accident severity, value, coverage and repair uncertainty. Record the achieved result in the validation output.

Use stable hashed random draws. Calculate:

```text
simulated hull loss = total-loss cost or partial-repair cost, capped at aircraft value
```

Keep the components only in the audit data. Publish only the final target.

### Final dataset build

`us_acft_faa_ntsb_sev_v1.R` should:

1. start from the matched frequency-v2 rows rather than rebuilding its columns independently;
2. reuse the frequency-v2 column selection and cleaning for every shared rating factor;
3. add the accident date, numeric accident year, severity target and stable event-aircraft identifier;
4. remove leakage and audit-only fields;
5. write `inst/extdata/us_acft_faa_ntsb_sev_v1.parquet`;
6. produce a reconciliation and simulation-quality report.

## GLMStudio catalogue publication

Publishing the package Parquet file is not sufficient. Add the corresponding assets to the `datasets` repository:

- `schemas/us_acft_faa_ntsb_sev_v1.json`, including a Gamma model with log link and no weight in `modeling_configs`;
- `docs/us_acft_faa_ntsb_sev_v1.md`;
- a fetch/build script beside the existing FAA/NTSB frequency scripts;
- entries in `build_manifest.py` and `upload_to_s3.py`.

The catalogue documentation must identify the target as simulated and explain its relationship to frequency v2.

## Validation and acceptance criteria

- Every frequency-v2 claim has one published severity row, one event-aircraft key and exactly one selected FAA registration line.
- The build reports all source, match, sampling and exclusion counts.
- Every row maps to a frequency-v2 sample row and inherits its fold unchanged.
- Every row publishes its NTSB accident date. Total losses use the aircraft-and-equipment PPI and partial repairs use the aircraft-repair PPI to express costs at the accident-date price level.
- Shared feature names, data types, category levels and missing-value treatment match frequency v2 exactly.
- Damage class and deregistration-derived information are absent from modelling features. Hull loss amount and ratio are declared as alternative targets.
- Synthetic values decline sensibly with age within comparable aircraft classes.
- Loss amounts overlap substantially within and between aircraft classes rather than being recoverable from the published predictors.
- The fixed reference Gamma model's held-out PR-squared is within the chosen 20–32% range.
- Loss ratios and loss amounts are plausible by audit-only damage class and aircraft category.
- Re-running from the same frozen sources produces identical rows, folds and simulated losses.
- GLMStudio imports the catalogue dataset with the intended Gamma/log/no-weight configuration.

## Out of scope

- observed paid or incurred claim amounts;
- passenger injury, bodily injury and liability losses;
- proprietary aircraft valuation data;
- exposing post-event damage information as a pricing factor;
- changing the folds in the existing frequency datasets;
- GLMStudio Combine implementation itself;
- elaborate catastrophe or claims-development modelling.

## Deliverables

1. frozen FAA, NTSB and ZIP inputs under ignored `rawdata/` paths;
2. the `02a`–`02c` preparation scripts and dataset-named final build script;
3. unpublished event-match and loss-construction audit objects;
4. `inst/extdata/us_acft_faa_ntsb_sev_v1.parquet`;
5. package data dictionary, methodology and reconciliation report;
6. complete `datasets` repository schema, documentation, build and upload entries;
7. an end-to-end catalogue import check in GLMStudio.
