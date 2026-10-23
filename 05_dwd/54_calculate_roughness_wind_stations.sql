 -- Optional: Spalte hinzufügen, falls sie noch nicht existiert
ALTER TABLE dwd.wind_stations_2025 ADD COLUMN IF NOT EXISTS roughness FLOAT;

-- Einfaches Update für alle Stationen (da nur ~400 Einträge)
WITH wind_buffers AS (
    SELECT 
        station_id, 
        ST_Buffer(geom, 3000) AS geom_buffer
    FROM dwd.wind_stations_2025
),
intersections AS (
    SELECT
        wb.station_id,
        ST_Area(ST_Intersection(wb.geom_buffer, clc.geom)) AS area_part,
        r.z0_emd_m
    FROM wind_buffers wb
    JOIN dwd.clc_2018 clc 
        ON ST_Intersects(wb.geom_buffer, clc.geom)
    LEFT JOIN dwd.clc2018_roughness r 
        ON r.clc_code::INTEGER = clc.code::INTEGER
),
aggregated_roughness AS (
    SELECT
        station_id,
        SUM(area_part * COALESCE(z0_emd_m, 0.05)) / NULLIF(SUM(area_part), 0) AS roughness_avg
    FROM intersections
    GROUP BY station_id
)
UPDATE dwd.wind_stations_2025 s
SET roughness = ar.roughness_avg
FROM aggregated_roughness ar
WHERE s.station_id = ar.station_id;
