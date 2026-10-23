-- Anlagenstammdaten aus dem Marktstammdatenregister.
-- Quelle: public.wind_extended / public.solar_extended, geladen von 21_get_msr.ipynb.

DROP TABLE IF EXISTS msr.msr;
CREATE TABLE msr.msr AS
SELECT
    w."EinheitMastrNummer"                AS msr_nr,
    'Wind'::text                          AS energie,
    NULL::integer                         AS modulzahl,
    NULL::text                            AS hauptausrichtung,
    w."Rotordurchmesser" / 2.0            AS rotor_r_m,
    w."Nabenhoehe"                        AS naben_h_m,
    w."LokationMastrNummer"               AS netzanschluss,
    ST_Transform(ST_SetSRID(ST_MakePoint(w."Laengengrad", w."Breitengrad"), 4326), 25832)::geometry(Point, 25832) AS geom
FROM public.wind_extended w
WHERE w."Laengengrad" IS NOT NULL
  AND w."Breitengrad" IS NOT NULL

UNION ALL

SELECT
    s."EinheitMastrNummer",
    'Solare Strahlungsenergie'::text,
    s."AnzahlModule",
    s."Hauptausrichtung",
    NULL::double precision,
    NULL::double precision,
    s."LokationMastrNummer",
    ST_Transform(ST_SetSRID(ST_MakePoint(s."Laengengrad", s."Breitengrad"), 4326), 25832)::geometry(Point, 25832)
FROM public.solar_extended s
WHERE s."Laengengrad" IS NOT NULL
  AND s."Breitengrad" IS NOT NULL;

CREATE INDEX idx_msr_geom ON msr.msr USING GIST (geom);
CREATE INDEX idx_msr_nr ON msr.msr (msr_nr);


-- Tabelle die MSR-Daten mit EEG-Daten verknüpft

DROP TABLE IF EXISTS msr.msr_eeg;
CREATE TABLE msr.msr_eeg AS
SELECT
    msr.*,
    COALESCE(wind."AnlagenschluesselEeg", solar."AnlagenschluesselEeg") AS anlagenschluessel_eeg,
    COALESCE(wind."InstallierteLeistung", solar."InstallierteLeistung") AS installierte_leistung
FROM msr.msr msr
LEFT JOIN public.wind_eeg wind ON msr.msr_nr = wind."VerknuepfteEinheit"
LEFT JOIN public.solar_eeg solar ON msr.msr_nr = solar."VerknuepfteEinheit";

CREATE INDEX idx_msr_eeg_anlagenschluessel ON msr.msr_eeg (anlagenschluessel_eeg);