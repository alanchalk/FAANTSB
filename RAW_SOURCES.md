# Raw source manifest

Raw source files are stored under ignored `rawdata/` paths. They are not distributed with the package.

| Local file | Source | Source date | SHA-256 |
|---|---|---:|---|
| `rawdata/NTSB/migration-export.sqlite` | [NTSB Aviation Data](https://data.ntsb.gov/avdata) | 2023-11-17 | `2550780c545380c3fa8003045470444063c36b02d64f14ba4554b09ae5c5a37a` |
| `rawdata/ReleasableAircraft/MASTER.txt` | [FAA Releasable Aircraft database](https://www.faa.gov/licenses_certificates/aircraft_certification/aircraft_registry/releasable_aircraft_download) | 2023-09-26 | `b0e20822981c372298f78de7e1379c6a12253fa7564589473eae42092c1bdeb0` |
| `rawdata/ReleasableAircraft/DEREG.txt` | FAA Releasable Aircraft database | 2023-09-26 | `225fbe0d4ae2792cc657a3864d76c464340ef092e3c5bc65201c8e51ff928005` |
| `rawdata/ReleasableAircraft/ACFTREF.txt` | FAA Releasable Aircraft database | 2023-09-26 | `14cbc4a5c32dd5ed7200f42eb9f5f368908ed68fb44fb2e972a620f713df98d6` |
| `rawdata/ReleasableAircraft/ENGINE.txt` | FAA Releasable Aircraft database | 2023-09-26 | `b90e744b0e145430cd7f0df2c244170c4990248cabea44ea1a8b9a36fe4febfd` |
| `rawdata/ZIP/us_zip_codes_2013.csv` | US ZIP Codes from 2013 Government Data | 2013-12-09 | `0e163eba47c7d3e36fe9aa36cbd982a6edd53f116f605cbbf56cb5b201874286` |
| `rawdata/BLS/WPU142.csv` | [BLS Aircraft and aircraft equipment PPI via FRED](https://fred.stlouisfed.org/series/WPU142) | retrieved 2026-11-05 | `8073f9ba2c494ff5f699e687c05a72300fd57ceece2753f9b91d2306a5652424` |
| `rawdata/BLS/WPU5541.csv` | [BLS Aircraft repair and maintenance PPI via FRED](https://fred.stlouisfed.org/series/WPU5541) | retrieved 2026-11-05 | `bee751f20a0d402b4a5197a92d29c1862316686a87bcfd9e32aacf1001e087ff` |

The severity build uses the cleaned FAA package data, the NTSB database, the published frequency-v2 Parquet file and the two frozen PPI series. The FAA text and ZIP files are retained locally so the upstream frequency preparation no longer depends on machine-specific Dropbox paths.
