-- CORINE Land Cover 5 ha (CLC5), Stand 2018 - BKG Geodatenzentrum
-- Bezug per WFS über den OGR Foreign Data Wrapper.
-- Lizenz: dl-de/by-2-0, Quellenvermerk "© Bundesamt für Kartographie und Geodäsie <Jahr>"
--
-- Voraussetzung: PostGIS-Installation mit ogr_fdw (Windows: im PostGIS-Bundle enthalten,
-- Debian/Ubuntu: postgresql-<version>-ogr-fdw). Extension und Schema fdw_clc5 werden
-- in 01_create_scheme/12_create_scheme.sql angelegt.

DROP SERVER IF EXISTS svr_clc5_2018 CASCADE;

CREATE SERVER svr_clc5_2018
  FOREIGN DATA WRAPPER ogr_fdw
  OPTIONS (
    datasource 'WFS:https://sgx.geodatenzentrum.de/wfs_clc5_2018',
    format 'WFS',
    -- Ohne Paging liefert der Dienst nur die erste Seite zurück.
    config_options 'OGR_WFS_PAGING_ALLOWED=ON OGR_WFS_PAGE_SIZE=10000'
  );

-- Legt die Fremdtabelle fdw_clc5.clc5_2018_clc5 an (Feature-Type clc5_2018:clc5).
IMPORT FOREIGN SCHEMA ogr_all
  FROM SERVER svr_clc5_2018
  INTO fdw_clc5;


-- Materialisieren: Deutschlandweit ~1 Mio. Polygone, der Download dauert entsprechend.
SET statement_timeout = 0;

DROP TABLE IF EXISTS dwd.clc_2018;

CREATE TABLE dwd.clc_2018 AS
SELECT
    row_number() OVER ()                          AS gid,
    clc18                                         AS code,
    ST_Multi(ST_Transform(geom, 25832))::geometry(MultiPolygon, 25832) AS geom
FROM fdw_clc5.clc5_2018_clc5
WHERE geom IS NOT NULL;

ALTER TABLE dwd.clc_2018 ADD PRIMARY KEY (gid);

CREATE INDEX idx_clc_2018_geom ON dwd.clc_2018 USING GIST (geom);
CREATE INDEX idx_clc_2018_code ON dwd.clc_2018 (code);

ANALYZE dwd.clc_2018;
