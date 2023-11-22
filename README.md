# FAA Aircraft Data Analysis

In the USA, the Federal Aviation Authority (FAA) maintains records of all registered aircraft and the National Transportation Safety Board (NTSB) maintains and database
of all incidents (accidents, near misses) involving aircraft.

This R package contains a dataset consisting of all aircraft from the FAA records with a flag added where an aircraft matches to an incident on the  NTSB.

NTSB accidents since 2008 are used and only aircraft with ongoing active registration since that year are included.

## Data Sources

The data in this repository has been compiled from the following sources:

- **FAA**: The official FAA dataset includes registration numbers, certification dates, and expiration dates for registered aircraft. The full dataset can be downloaded from the [FAA website](https://www.faa.gov/licenses_certificates/aircraft_certification/aircraft_registry/releasable_aircraft_download).

- **NTSB**: The National Transportation Safety Board maintains detailed records of aviation incidents. The complete Access database (`avall.zip`) and database structure (`codman.pdf`) are available for download from the [NTSB Data Portal](https://data.ntsb.gov/avdata/FileDirectory/DownloadFile?fileID=C%3A%5Cavdata%5Cavall.zip) and [here](https://data.ntsb.gov/avdata/FileDirectory/DownloadFile?fileID=C%3A%5Cavdata%5Ccodman.pdf).

## Dataset Format

The main dataset, `dt_faa_ntsb_clean`, is structured as a data frame with the following characteristics:

- **Rows**: 2,696,313
- **Columns**: 49

Each row represents a unique record with various attributes such as `unique_id_line`, `n_number`, `serial_number`, and `region`. The dataset includes detailed categorical codes with descriptions, for instance, regions and types of registered owners.

There is one line per year per aircraft.  For example an aircraft registered from 2008 and 2017 will have 10 records in the R dataset.

Each row in the data contains `nu_cl` - the number of NTSB claims matched to that row, and `ex` - the proportion of the year for which the aircraft was registered.

## Usage

This data has been prepared for use in case studies demonstrating building of predictive models using generalised linear models and other techniques.

## Contributing

Contributions to this project are welcome. The data preparation of the existing dataset can be improved and in addition further datasets could be prepared using the same data sources.

## License

This project is licensed under [License Name]. Please refer to the `LICENSE` file for more details.
