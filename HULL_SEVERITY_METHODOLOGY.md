# Simulated hull-severity methodology

`us_acft_faa_ntsb_sev_v1` contains one NTSB aircraft occurrence for each claim counted in the seed-2024 frequency-v2 sample. The 2,725 severity rows therefore reconcile exactly to the aggregate frequency claim count. The population includes the incidents and blank or unknown damage records already counted by frequency v2.

Each occurrence is matched to exactly one FAA aircraft-year row. A row containing the event date is preferred; otherwise the nearest eligible row within 730 days is used. Remaining ties are resolved by `unique_id_line`. The severity record inherits the matched frequency row's fold.

## Aircraft value

The expected value is synthetic. It combines:

- a base value of $180,000, $1.4 million or $9 million for FAA weight classes 1–3;
- factors for engine type, engine count, seats and cruise speed;
- a depreciation factor of `0.32 + 0.68 × exp(-age / 22)`;
- lognormal value uncertainty with sigma 0.40.

Age is measured from manufacture year at the occurrence date where possible. The published frequency-v2 aircraft age is the fallback.

## Damage and claim cost

The NTSB damage class controls a hidden total-loss probability: 95% for destroyed aircraft, 3% for substantial damage, 0.1% for minor damage and 1% when damage is blank or unknown. This prevents the published rating factors from revealing the severity of the accident.

Total-loss costs rise with aircraft value with an elasticity of 0.78. A broad claim-specific factor represents differences in coverage, salvage and recovery. Partial repairs start from a damage-class cost level, have only a small aircraft-value effect, and include lognormal repair-cost uncertainty with sigma 0.80. Every loss is positive and capped at the uncertain aircraft value.

Claim amounts are converted to their accident-date price level using two US Bureau of Labor Statistics Producer Price Index series: `WPU142`, Aircraft and aircraft equipment, for total losses; and `WPU5541`, Aircraft repair and maintenance, for partial repairs. Each is rebased to its latest frozen observation. The repair series begins in April 2009, so the earlier 2008–March 2009 values are backcast using `WPU142`, anchored to the first repair observation. The published `accident_date` allows losses to be restated to another common price level; `accident_year` is the corresponding numeric modelling feature.

A fixed Gamma/log reference GLM fitted only to published pre-event factors has a held-out PR-squared of about 0.25. Thus aircraft characteristics provide a useful pricing signal without making the simulated claim cost nearly deterministic.

Aircraft value, damage ratio, damage class and the total-loss indicator remain in the local audit object and are excluded from the published modelling data. Stable hashes of the aircraft or claim identifier generate every random draw, so repeated builds are identical.
