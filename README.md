# redispatch_losses

Estimating the energy lost to redispatch curtailment of wind and solar plants in
the grid areas of three German distribution system operators.

The pipeline combines plant master data from the German Market Master Data Register (MaStR)
with reported curtailment measures and with weather observations from the German Weather
Service (DWD). For every 10-minute interval of a curtailment event it estimates the energy the
plant would have produced without the intervention, and compares it against the feed-in that
was actually permitted.

Repository accompanying a master's thesis.

---

## How it works

The project is a **sequence of SQL scripts and Jupyter notebooks** that together build a
PostgreSQL/PostGIS database. The database is the shared state: every step reads tables written
by earlier steps and writes new ones.

Folder and file numbering defines the execution order.
**Run folders 01 through 08 one after another, and within each folder follow the file numbers.**
Steps cannot be skipped, because each one depends on tables created by the previous one.

| # | Folder | What it does | Type |
|---|---|---|---|
| 01 | `01_create_scheme` | Create extensions (PostGIS, FDW) and schemas | SQL |
| 02 | `02_create_table_msr` | Download MaStR, build plant master data | Notebook + SQL |
| 03 | `03_create_table_redispatch` | Load curtailment measures per DSO and link them to plants | SQL + Notebooks |
| 04 | `04_create_table_roughness_clc18` | Fetch land cover (CLC5) via WFS, store roughness lengths | SQL |
| 05 | `05_dwd` | Load DWD wind and radiation observations, derive roughness per station | Notebooks + SQL |
| 06 | `06_interpolation` | Interpolate observations onto plant locations | SQL |
| 07 | `07_energy_calculation` | Compute potential energy, permitted feed-in and loss | SQL |
| 08 | `08_analysis` | Aggregation and visualisation | Notebooks |

---

## Step by step

### 01 – Schemas

[`11_create_scheme.sql`](01_create_scheme/11_create_scheme.sql) creates the `postgis`,
`postgres_fdw` and `ogr_fdw` extensions and the `msr`, `redispatch`, `dwd` and `fdw_clc5`
schemas. Run once against an empty database.

### 02 – Plant master data (MaStR)

1. [`21_get_msr.ipynb`](02_create_table_msr/21_get_msr.ipynb) uses `open-mastr` to bulk-download
   the full wind and solar dataset from the Market Master Data Register into the `public` schema.
   The download is several gigabytes and takes roughly an hour.
2. [`22_create_table_msr.sql`](02_create_table_msr/22_create_table_msr.sql) derives `msr.msr`
   from it (site geometry in EPSG:25832, hub height, rotor radius, module count, orientation)
   and joins the EEG plant key together with the installed capacity into `msr.msr_eeg`.

### 03 – Curtailment measures

1. The three `31_create_table_redispatch_*.sql` scripts create the target table
   `redispatch.raw_data_*` for each DSO. Run these **before** the notebooks.
2. The three `32_get_redispatch_data_*.ipynb` notebooks fetch the reported measures day by day
   from the redispatch API and write them into those tables.
3. Then run the second part of the `31_*.sql` scripts: it joins the measures onto `msr.msr_eeg`
   via the EEG plant key and produces `redispatch.redispatch_eeg_*` — the central event table
   holding the time window, curtailment stage, plant technology and geometry.

### 04 – Land cover and roughness

1. [`41_create_table_roughness_values.sql`](04_create_table_roughness_clc18/41_create_table_roughness_values.sql)
   stores the mapping from CLC nomenclature classes to surface roughness lengths (values after
   EMD WindPRO, with DTU values for comparison).
2. [`42_fdw_clc5_2018.sql`](04_create_table_roughness_clc18/42_fdw_clc5_2018.sql) attaches the
   BKG CLC5 WFS through `ogr_fdw` and materialises the polygons into `dwd.clc_2018`. That is
   several hundred thousand features for all of Germany, so the download takes a while.

### 05 – Weather data

1. [`52_dwd_solar.ipynb`](05_dwd/52_dwd_solar.ipynb) and
   [`53_dwd_wind.ipynb`](05_dwd/53_dwd_wind.ipynb) use `wetterdienst` to load the 10-minute
   series of the DWD stations (global radiation and 10 m wind speed respectively) plus the
   station metadata. The tables are created straight from the DataFrames; the notebooks add the
   geometry column, primary key and indexes themselves.
2. [`54_calculate_roughness_wind_stations.sql`](05_dwd/54_calculate_roughness_wind_stations.sql)
   intersects a 3 km buffer around each wind station with `dwd.clc_2018` and writes the
   area-weighted mean roughness length to `dwd.wind_stations_2025.roughness`.

[`51_tryout.ipynb`](05_dwd/51_tryout.ipynb) is exploratory and not required for the pipeline.

### 06 – Spatial interpolation

One wind and one solar script per DSO.

**Wind:** for each event the three nearest stations are selected. Their 10 m measurement is
extrapolated to the plant's hub height using the Hellmann power law, where the exponent is
derived from the roughness length **at the measuring station**, not at the plant site. The three
station values are then combined into a single value at the plant location by inverse distance
weighting with the squared distance.

**Solar:** the same approach with the four nearest radiation stations, without any height
correction.

### 07 – Energy calculation

**Wind:** a generic cubic power curve with a cut-in speed of 3 m/s, rated speed of 12 m/s,
cut-out speed of 25 m/s and a system efficiency of 0.90.

**Solar:** installed capacity multiplied by a constant performance ratio of 0.85 and the
interpolated irradiation, capped at rated power.

This yields three values per 10-minute interval:

- `energy_kwh_10min` — energy the plant would have produced without the intervention
- `abregelung` — feed-in still permitted at the reported curtailment stage
- `verlust` — the difference, floored at zero

The per-event sum is written back to `redispatch.redispatch_eeg_*.verlust`.

### 08 – Analysis

The three `81_analysis_*.ipynb` notebooks aggregate the losses by grid connection point and
time period and produce time series and summary figures. The `tests and tryouts with the data`
subfolder contains intermediate work and is not part of the pipeline.

---

## Requirements

- **PostgreSQL** with **PostGIS**
- **`ogr_fdw`** for the CLC5 WFS access
  (Windows: bundled with PostGIS, Debian/Ubuntu: `postgresql-<version>-ogr-fdw`)
- **Python 3.11+**

## Setup

```bash
python -m venv .venv
.venv\Scripts\activate        # Linux/macOS: source .venv/bin/activate
pip install -r requirements.txt
```

Create the database and run the schema script:

```bash
createdb redispatch_losses
psql -d redispatch_losses -f 01_create_scheme/11_create_scheme.sql
```

The notebooks connect to `postgresql://postgres:postgres@localhost:5432/redispatch_losses`.
Adjust the connection cells if your credentials differ.

SQL scripts can be run with `psql -d redispatch_losses -f <file>.sql` or in pgAdmin. Several of
them are long-running and therefore set `statement_timeout = 0`.

---

## Data sources

| Source | Content | Licence |
|---|---|---|
| [Marktstammdatenregister](https://www.marktstammdatenregister.de/) (via `open-mastr`) | Plant master data, EEG plant keys | dl-de/by-2-0 |
| [Deutscher Wetterdienst](https://opendata.dwd.de/) (via `wetterdienst`) | 10 m wind speed, global radiation, 10-minute resolution | GeoNutzV, © Deutscher Wetterdienst |
| [BKG Geodatenzentrum](https://gdz.bkg.bund.de/), CLC5 2018 (WFS) | 5 ha land cover used for roughness lengths | dl-de/by-2-0, © Bundesamt für Kartographie und Geodäsie |
| Redispatch API of the distribution system operators | Measures reported under § 13a EnWG | see operators |

---

## Notes and limitations

- Plant-specific power curves are not available; the generic cubic approximation and the
  constant performance ratio are the main source of uncertainty in the estimate.
- The roughness correction is applied at the **measuring stations**, not at the plant site.
  Micro-scaling to the local site roughness is deliberately not included.
- Wake effects within wind farms, icing, plant availability and grid losses are not accounted
  for.
- The credentials in the notebooks are local defaults (`postgres`/`postgres`) and not real
  secrets.

---

## AI assistance

Parts of the code in this repository were written with the help of AI coding assistants. Every
generated section was reviewed, adapted and tested before being included. Responsibility for
the methodology, the results and their interpretation lies entirely with the author.
