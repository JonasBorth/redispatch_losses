

-- Tabelle für Windgeschwindigkeiten an den nächstgelegenen Stationen (Hochgerechnet auf Nabenhöhe)
-- Keine Interpolation! Nur Zuweisung und Höhenprofil-Korrektur.



-- 1. Tabelle initialisieren
DROP TABLE IF EXISTS dwd.wind_values_bayernwerk;

CREATE TABLE dwd.wind_values_bayernwerk (
    eventnummer integer,      -- Referenz zum Redispatch-Event
    station_id char(5),       -- ID der DWD-Windstation
    timestamp timestamp,      -- Zeitpunkt (alle 10 Minuten während des Events)
    dist_m numeric,           -- Entfernung WEA <-> Station
    wind_speed_hub numeric,   -- Berechnete Windgeschwindigkeit auf Nabenhöhe (m/s)
    wind_speed_10m numeric,   -- Gemessene Windgeschwindigkeit auf 10m (m/s)
    hub_height numeric,       -- Verwendete Nabenhöhe der WEA
    roughness_station numeric -- Verwendete Rauigkeit der Station
);

-- 2. Verarbeitung mit Fortschrittsanzeige
SET statement_timeout = 0;
DO $$
DECLARE
    cur_events CURSOR FOR 
        SELECT eventnummer, geom, star, ende, naben_h_m
        FROM redispatch.redispatch_eeg_bayernwerk
        WHERE energie ILIKE '%Wind%'
        AND geom IS NOT NULL;
        
    rec RECORD;
    counter INTEGER := 0;
    total_rows INTEGER;
BEGIN
    SELECT count(*) INTO total_rows 
    FROM redispatch.redispatch_eeg_bayernwerk
    WHERE energie ILIKE '%Wind%'
    AND geom IS NOT NULL;

    RAISE NOTICE 'Starte Wind-Berechnung für % Events...', total_rows;

    FOR rec IN cur_events LOOP
        counter := counter + 1;
        
        IF MOD(counter, 50) = 0 THEN
            RAISE NOTICE 'Fortschritt: % von % Events verarbeitet (%.2f%%)', 
                counter, total_rows, (counter::numeric / total_rows::numeric) * 100;
        END IF;

        INSERT INTO dwd.wind_values_bayernwerk
        WITH event_times AS (
            SELECT 
                rec.eventnummer AS eventnummer,
                rec.geom AS geom,
                date_bin('10 minutes', ts, TIMESTAMP '2000-01-01') AS timestamp_rounded
            FROM 
                generate_series(rec.star, rec.ende, interval '10 minutes') AS ts
        ),
        candidates_pool AS (
            SELECT
                et.eventnummer,
                et.timestamp_rounded,
                s.station_id,
                s.roughness,
                ST_Distance(et.geom, s.geom) AS dist
            FROM
                event_times et
            CROSS JOIN LATERAL (
                SELECT station_id, roughness, geom
                FROM dwd.wind_stations_2025 s
                ORDER BY et.geom <-> s.geom
                LIMIT 3
            ) s
        )
        SELECT
            cp.eventnummer,
            cp.station_id,
            cp.timestamp_rounded,
            ROUND(cp.dist::numeric, 2) AS dist_m,
            -- Hellmann-Potenzgesetz: u_h = u_10 * (h/10)^alpha  mit  alpha = 1 / ln(sqrt(h*10) / z0)
            ROUND(
                (d.wind_speed_ms * POWER(
                    GREATEST(10, COALESCE(rec.naben_h_m, 100)) / 10.0,
                    1.0 / LN(SQRT(GREATEST(10, COALESCE(rec.naben_h_m, 100)) * 10.0)
                             / GREATEST(0.0001, COALESCE(cp.roughness, 0.03)))
                ))::numeric,
            2) AS wind_speed_hub,
            d.wind_speed_ms AS wind_speed_10m,
            GREATEST(10, COALESCE(rec.naben_h_m, 100)) AS hub_height,
            GREATEST(0.0001, COALESCE(cp.roughness, 0.03)) AS roughness_station
        FROM
            candidates_pool cp
        JOIN dwd.wind_speed_2025 d 
            ON cp.station_id = d.station_id 
            AND d.timestamp = cp.timestamp_rounded
        WHERE
            d.wind_speed_ms IS NOT NULL;

    END LOOP;
    
    RAISE NOTICE 'Fertig! % Events verarbeitet.', counter;
END $$;



-- Indizes für schnelle Abfragen
CREATE INDEX IF NOT EXISTS idx_wind_calc_byw_event ON dwd.wind_values_bayernwerk(eventnummer);
CREATE INDEX IF NOT EXISTS idx_wind_calc_byw_station ON dwd.wind_values_bayernwerk(station_id);
CREATE INDEX IF NOT EXISTS idx_wind_calc_byw_time ON dwd.wind_values_bayernwerk(timestamp);


-- =================================================================================================
-- INTERPOLATION: IDW-gewichtete Windgeschwindigkeit pro Event und Zeitpunkt
-- =================================================================================================

-- 1. Tabelle initialisieren
DROP TABLE IF EXISTS dwd.wind_bayernwerk_2025_interpolated;

CREATE TABLE dwd.wind_bayernwerk_2025_interpolated (
    eventnummer integer,
    timestamp timestamp,
    interpolated_wind_speed numeric,
    used_stations text
);


-- 2. IDW-Interpolation aus wind_event_values
INSERT INTO dwd.wind_bayernwerk_2025_interpolated (
    eventnummer,
    timestamp,
    interpolated_wind_speed,
    used_stations
)
SELECT
    v.eventnummer,
    v.timestamp,
    -- IDW-Interpolation: Σ(u_i / d_i²) / Σ(1 / d_i²)
    ROUND(
        (SUM(v.wind_speed_hub * (1.0 / POWER(GREATEST(v.dist_m, 1), 2))) 
        / NULLIF(SUM(1.0 / POWER(GREATEST(v.dist_m, 1), 2)), 0))::numeric,
    2) AS interpolated_wind_speed,
    STRING_AGG(
        v.station_id || ' (' || ROUND(v.dist_m, 0) || 'm)',
        ', ' ORDER BY v.dist_m
    ) AS used_stations
FROM dwd.wind_values_bayernwerk v
GROUP BY v.eventnummer, v.timestamp;

-- Indizes
CREATE INDEX idx_wind_interpolated_event_byw ON dwd.wind_bayernwerk_2025_interpolated(eventnummer);
CREATE INDEX idx_wind_interpolated_time_byw ON dwd.wind_bayernwerk_2025_interpolated(timestamp);




