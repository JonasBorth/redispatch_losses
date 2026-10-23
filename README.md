# redispatch_losses

Berechnung der Energieverluste durch Redispatch-Abregelung (§ 13a EnWG) von Wind- und
Solaranlagen in den Netzgebieten dreier Verteilnetzbetreiber.

Die Pipeline verbindet Anlagenstammdaten aus dem Marktstammdatenregister mit gemeldeten
Redispatch-Maßnahmen und mit Wettermessdaten des DWD. Für jedes 10-Minuten-Intervall einer
Abregelung wird die Energie geschätzt, die die Anlage ohne Eingriff erzeugt hätte, und der
tatsächlich zugelassenen Einspeisung gegenübergestellt.

Repository zur Masterarbeit.

---

## Aufbau

Das Projekt ist eine **Abfolge aus SQL-Skripten und Jupyter-Notebooks**, die gemeinsam eine
PostgreSQL/PostGIS-Datenbank aufbauen. Die Datenbank ist der gemeinsame Zustand: Jeder Schritt
liest Tabellen der vorherigen Schritte und schreibt neue.

Die Nummerierung von Ordnern und Dateien gibt die Ausführungsreihenfolge vor.
**Ordner 01 bis 08 nacheinander abarbeiten, innerhalb eines Ordners nach Dateinummer.**
Überspringen funktioniert nicht, weil jeder Schritt Tabellen des vorherigen voraussetzt.

| # | Ordner | Was passiert | Typ |
|---|---|---|---|
| 01 | `01_create_scheme` | Extensions (PostGIS, FDW) und Schemata anlegen | SQL |
| 02 | `02_create_table_msr` | MaStR herunterladen, Anlagenstammdaten aufbereiten | Notebook + SQL |
| 03 | `03_create_table_redispatch` | Redispatch-Maßnahmen je Netzbetreiber laden und mit Anlagen verknüpfen | SQL + Notebooks |
| 04 | `04_create_table_roughness_clc18` | Landbedeckung (CLC5) per WFS beziehen, Rauigkeitslängen hinterlegen | SQL |
| 05 | `05_dwd` | DWD-Wind- und Strahlungsmessungen laden, Rauigkeit je Station berechnen | Notebooks + SQL |
| 06 | `06_interpolation` | Messwerte räumlich auf die Anlagenstandorte interpolieren | SQL |
| 07 | `07_energy_calculation` | Potenzialenergie, Abregelung und Verlust berechnen | SQL |
| 08 | `08_analysis` | Auswertung und Visualisierung | Notebooks |

---

## Ablauf im Detail

### 01 – Schemata

[`12_create_scheme.sql`](01_create_scheme/12_create_scheme.sql) legt die Extensions `postgis`,
`postgres_fdw` und `ogr_fdw` sowie die Schemata `msr`, `redispatch`, `dwd` und `fdw_clc5` an.
Einmalig in einer leeren Datenbank ausführen.

### 02 – Anlagenstammdaten (MaStR)

1. [`21_get_msr.ipynb`](02_create_table_msr/21_get_msr.ipynb) lädt per `open-mastr` den
   Gesamtdatenbestand für Wind und Solar aus dem Marktstammdatenregister in das Schema `public`.
   Der Bulk-Download ist mehrere GB groß und dauert eine gute Stunde.
2. [`22_create_table_msr.sql`](02_create_table_msr/22_create_table_msr.sql) baut daraus
   `msr.msr` (Standortgeometrie in EPSG:25832, Nabenhöhe, Rotorradius, Modulzahl, Ausrichtung)
   und verknüpft in `msr.msr_eeg` den EEG-Anlagenschlüssel samt installierter Leistung.

### 03 – Redispatch-Maßnahmen

1. Die drei `31_create_table_redispatch_*.sql` legen je Netzbetreiber die Zieltabelle
   `redispatch.raw_data_*` an. **Vor** den Notebooks ausführen.
2. Die drei `32_get_redispatch_data_*.ipynb` holen die gemeldeten Maßnahmen tageweise über die
   Redispatch-API und schreiben sie in diese Tabellen.
3. Anschließend den zweiten Teil der `31_*.sql` ausführen: Er joint die Maßnahmen über den
   EEG-Anlagenschlüssel auf `msr.msr_eeg` und erzeugt `redispatch.redispatch_eeg_*` — die
   zentrale Ereignistabelle mit Zeitraum, Abregelungsstufe, Anlagentechnik und Geometrie.

### 04 – Landbedeckung und Rauigkeit

1. [`41_create_table_roughness_values.sql`](04_create_table_roughness_clc18/41_create_table_roughness_values.sql)
   legt die Zuordnung von CLC-Nomenklaturklassen zu Rauigkeitslängen z₀ an (Werte nach EMD
   WindPRO, zum Vergleich DTU).
2. [`42_fdw_clc5_2018.sql`](04_create_table_roughness_clc18/42_fdw_clc5_2018.sql) bindet den
   CLC5-WFS des BKG per `ogr_fdw` ein und materialisiert die Polygone nach `dwd.clc_2018`.
   Deutschlandweit sind das einige hunderttausend Flächen — der Abruf läuft entsprechend lange.

### 05 – Wetterdaten

1. [`52_dwd_solar.ipynb`](05_dwd/52_dwd_solar.ipynb) und
   [`53_dwd_wind.ipynb`](05_dwd/53_dwd_wind.ipynb) laden per `wetterdienst` die
   10-Minuten-Messreihen der DWD-Stationen (Globalstrahlung bzw. Windgeschwindigkeit in 10 m)
   und die Stationsmetadaten. Die Tabellen werden dabei direkt aus den DataFrames erzeugt;
   Geometriespalte, Primärschlüssel und Indizes legen die Notebooks selbst an.
2. [`54_calculate_roughness_wind_stations.sql`](05_dwd/54_calculate_roughness_wind_stations.sql)
   verschneidet einen 3-km-Puffer um jede Windstation mit `dwd.clc_2018` und schreibt die
   flächengewichtete mittlere Rauigkeitslänge nach `dwd.wind_stations_2025.roughness`.

[`51_tryout.ipynb`](05_dwd/51_tryout.ipynb) ist explorativ und für die Pipeline nicht nötig.

### 06 – Räumliche Interpolation

Je Netzbetreiber ein Wind- und ein Solarskript.

**Wind:** Für jedes Ereignis werden die drei nächstgelegenen Stationen gesucht. Deren
10-m-Messwert wird mit dem Hellmann-Potenzgesetz auf die Nabenhöhe der Anlage gebracht,

$$u_h = u_{10}\left(\frac{h}{10}\right)^{\alpha},\qquad \alpha = \frac{1}{\ln\!\left(\sqrt{10\,h}\,/\,z_0\right)}$$

wobei $z_0$ die Rauigkeitslänge **am Standort der Messstation** ist. Die drei Stationswerte
werden anschließend per inverser Distanzwichtung ($1/d^2$) zum Wert am Anlagenstandort
kombiniert.

**Solar:** Analog mit den vier nächstgelegenen Strahlungsstationen, ohne Höhenkorrektur.

### 07 – Energieberechnung

**Wind:** generische kubische Leistungskurve mit $v_{ci}=3$, $v_r=12$, $v_{co}=25$ m/s und
Systemwirkungsgrad $\eta = 0{,}90$.

**Solar:** $E = P_{inst} \cdot PR \cdot G/360$ mit Performance Ratio $PR = 0{,}85$, gedeckelt
auf die Nennleistung.

Daraus ergibt sich je 10-Minuten-Intervall:

- `energy_kwh_10min` — Energie ohne Eingriff
- `abregelung` — bei der gemeldeten Abregelungsstufe zulässige Einspeisung
- `verlust` — Differenz, auf null begrenzt

Die Summe je Ereignis wird nach `redispatch.redispatch_eeg_*.verlust` zurückgeschrieben.

### 08 – Auswertung

Die drei `81_analysis_*.ipynb` aggregieren die Verluste je Netzanschlusspunkt und Zeitraum und
erzeugen Zeitreihen und Kennzahlen. Der Unterordner `tests and tryouts with the data` enthält
Zwischenstände und ist nicht Teil der Pipeline.

---

## Voraussetzungen

- **PostgreSQL** mit **PostGIS**
- **`ogr_fdw`** für den CLC5-WFS-Abruf
  (Windows: im PostGIS-Bundle enthalten, Debian/Ubuntu: `postgresql-<version>-ogr-fdw`)
- **Python 3.11+**

## Einrichtung

```bash
python -m venv .venv
.venv\Scripts\activate        # Linux/macOS: source .venv/bin/activate
pip install -r requirements.txt
```

Datenbank anlegen und das Schema-Skript ausführen:

```bash
createdb redispatch_losses
psql -d redispatch_losses -f 01_create_scheme/12_create_scheme.sql
```

Die Notebooks verbinden sich mit `postgresql://postgres:postgres@localhost:5432/redispatch_losses`.
Weichen deine Zugangsdaten ab, müssen sie in den Verbindungszellen angepasst werden.

SQL-Skripte lassen sich mit `psql -d redispatch_losses -f <datei>.sql` oder in pgAdmin ausführen.
Mehrere Skripte laufen lange und setzen deshalb `statement_timeout = 0`.

---

## Datenquellen

| Quelle | Inhalt | Lizenz |
|---|---|---|
| [Marktstammdatenregister](https://www.marktstammdatenregister.de/) (via `open-mastr`) | Anlagenstammdaten, EEG-Schlüssel | dl-de/by-2-0 |
| [Deutscher Wetterdienst](https://opendata.dwd.de/) (via `wetterdienst`) | Windgeschwindigkeit 10 m, Globalstrahlung, 10-min | GeoNutzV, © Deutscher Wetterdienst |
| [BKG Geodatenzentrum](https://gdz.bkg.bund.de/), CLC5 2018 (WFS) | Landbedeckung 5 ha für die Rauigkeitslängen | dl-de/by-2-0, © Bundesamt für Kartographie und Geodäsie |
| Redispatch-API der Verteilnetzbetreiber | gemeldete Maßnahmen nach § 13a EnWG | siehe Betreiber |

---

## Hinweise und Einschränkungen

- Anlagenspezifische Leistungskurven liegen nicht vor; die generische kubische Näherung bzw.
  das konstante Performance Ratio sind die wesentliche Unsicherheitsquelle der Abschätzung.
- Die Rauigkeitskorrektur erfolgt an den **Messstationen**, nicht am Anlagenstandort. Eine
  Mikroskalierung auf die Standortrauigkeit ist bewusst nicht enthalten.
- Abschattung im Windpark, Vereisung, Anlagenverfügbarkeit und Netzverluste bleiben
  unberücksichtigt.
- Die Zugangsdaten in den Notebooks sind lokale Standardwerte (`postgres`/`postgres`) und
  keine echten Geheimnisse.
