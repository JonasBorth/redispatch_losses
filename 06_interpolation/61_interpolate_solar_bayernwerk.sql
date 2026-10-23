-- Tabelle für Solar-Interpolation erstellen (Alle Daten, mit Fortschrittsanzeige)
-- Hinweis: Wir nutzen hier einen 'DO' Block, um Statusmeldungen ausgeben zu können.

-- 1. Tabelle initialisieren
DROP TABLE IF EXISTS dwd.solar_bayernwerk_2025_interpolated;

CREATE TABLE dwd.solar_bayernwerk_2025_interpolated (
    eventnummer integer,
    timestamp timestamp,
    interpolated_radiation numeric,
    stations_count bigint,
    used_stations text
);

-- 2. Verarbeitung mit Fortschrittsanzeige
SET statement_timeout = 0; 
DO $$
DECLARE
    -- Cursor für die Events (wir holen alle Events einzeln)
    cur_events CURSOR FOR 
        SELECT eventnummer, geom, star, ende 
        FROM redispatch.redispatch_eeg_bayernwerk
        WHERE star >= '2025-01-01' AND ende <= '2025-12-31'
        AND geom IS NOT NULL
        AND energie = 'Solare Strahlungsenergie';
        
    rec RECORD;
    counter INTEGER := 0;
    total_rows INTEGER;
BEGIN
    -- Gesamtzahl ermitteln (für schönen Fortschrittsbalken)
    SELECT count(*) INTO total_rows 
    FROM redispatch.redispatch_eeg_bayernwerk
    WHERE star >= '2025-01-01' AND ende <= '2025-12-31'
    AND geom IS NOT NULL
    AND energie = 'Solare Strahlungsenergie';

    RAISE NOTICE 'Starte Solar-Interpolation für % Events...', total_rows;

    -- Schleife über alle Events
    FOR rec IN cur_events LOOP
        counter := counter + 1;
        
        -- Fortschritt alle 50 Events melden
        IF MOD(counter, 50) = 0 THEN
            RAISE NOTICE 'Fortschritt: % von % Events verarbeitet (%.2f%%)', 
                counter, total_rows, (counter::numeric / total_rows::numeric) * 100;
        END IF;

        -- Einfügen der interpolierten Daten für DIESES EINE Event
        INSERT INTO dwd.solar_bayernwerk_2025_interpolated
        WITH event_times AS (
            -- Intervalle
            SELECT 
                rec.eventnummer,
                rec.geom,
                date_bin('10 minutes', ts, TIMESTAMP '2000-01-01') as timestamp_rounded
            FROM 
                generate_series(rec.star, rec.ende, interval '10 minutes') as ts
        ),
        candidates_pool AS (
            -- Kandidaten
            SELECT
                et.eventnummer,
                et.timestamp_rounded,
                s.station_id,
                ST_Distance(et.geom, s.geom) as dist
            FROM
                event_times et
            CROSS JOIN LATERAL (
                SELECT station_id, geom
                FROM dwd.solar_stations_2025 s 
                ORDER BY et.geom <-> s.geom
                LIMIT 10 
            ) s
        ),
        stations_with_data_ranked AS (
            -- Daten & Ranking
            SELECT 
                cp.eventnummer,
                cp.timestamp_rounded,
                cp.station_id,
                cp.dist,
                d.radiation_global_joule_per_sqcm, 
                ROW_NUMBER() OVER (
                    PARTITION BY cp.eventnummer, cp.timestamp_rounded 
                    ORDER BY cp.dist ASC
                ) as rn
            FROM 
                candidates_pool cp
            JOIN 
                dwd.solar_radiation_2025 d 
                ON cp.station_id = d.station_id 
                AND d.timestamp = cp.timestamp_rounded
            WHERE 
                d.radiation_global_joule_per_sqcm IS NOT NULL
        )
        -- Finale Aggregation
        SELECT
            r.eventnummer,
            r.timestamp_rounded as timestamp,
            SUM(r.radiation_global_joule_per_sqcm * (1.0 / POWER(GREATEST(r.dist, 1), 2))) / 
            NULLIF(SUM(1.0 / POWER(GREATEST(r.dist, 1), 2)), 0) AS interpolated_radiation,
            COUNT(*) as stations_count,
            STRING_AGG(
                r.station_id || ' (' || ROUND(r.dist::numeric, 0) || 'm)', 
                ', ' ORDER BY r.dist
            ) AS used_stations
        FROM
            stations_with_data_ranked r
        WHERE
            r.rn <= 4 
        GROUP BY
            r.eventnummer,
            r.timestamp_rounded;
            
    END LOOP;
    
    RAISE NOTICE 'Fertig! % Events verarbeitet.', counter;
END $$;

-- Indizes für schnelle Abfragen erstellen
CREATE INDEX idx_solar_bayernwerk_2025_interpolated_event ON dwd.solar_bayernwerk_2025_interpolated(eventnummer);
CREATE INDEX idx_solar_bayernwerk_2025_interpolated_time ON dwd.solar_bayernwerk_2025_interpolated(timestamp);