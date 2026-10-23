-- Grundgerüst der Datenbank: Extensions und Schemata
-- Muss als Erstes in einer leeren Datenbank ausgeführt werden.

-- Geometrietypen, ST_Buffer, ST_Intersection, GIST-Indizes
CREATE EXTENSION IF NOT EXISTS postgis;

-- Foreign Data Wrapper für den Zugriff auf eine externe Quelldatenbank
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Foreign Data Wrapper für OGR-Quellen (WFS, GeoPackage, Shapefile)
CREATE EXTENSION IF NOT EXISTS ogr_fdw;


-- Quelldaten
-- Die MaStR-Tabellen (wind_extended, solar_extended, *_eeg) schreibt open-mastr nach public.

CREATE SCHEMA IF NOT EXISTS fdw_clc5;     -- CLC5-2018-Fremdtabelle vom BKG-WFS

-- Aufbereitete Anlagenstammdaten
CREATE SCHEMA IF NOT EXISTS msr;          -- msr.msr, msr.msr_eeg

-- Redispatch-Events der Verteilnetzbetreiber
CREATE SCHEMA IF NOT EXISTS redispatch;   -- raw_data_*, redispatch_eeg_*

-- Wetterdaten, Rauigkeit, Interpolation und Energieberechnung
CREATE SCHEMA IF NOT EXISTS dwd;          -- wind_*/solar_* Stationen und Messwerte, clc_2018, clc2018_roughness
