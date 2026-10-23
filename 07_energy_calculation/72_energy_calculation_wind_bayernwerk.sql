-- =================================================================================================
-- WIND-ENERGIEBERECHNUNG: Generisches Modell (kubische Leistungskurve)
-- =================================================================================================
-- Modell:  P(v) = P_rated * ((v - v_ci) / (v_r - v_ci))^3   für v_ci <= v <= v_r
--          P(v) = P_rated                                     für v_r  <  v <= v_co
--          P(v) = 0                                           sonst
--
-- Parameter (typisch für moderne Onshore-WEA):
--   v_ci  =  3 m/s   (Cut-in)
--   v_r   = 12 m/s   (Nennwindgeschwindigkeit)
--   v_co  = 25 m/s   (Cut-out)
--   eta   = 0.90     (Systemwirkungsgrad: Verfügbarkeit, elektr. Verluste, etc.)
--
-- Energie pro 10-min-Intervall:  E = P(v) * eta / 6  [kWh]
-- =================================================================================================

-- 1) Spalten anlegen
ALTER TABLE dwd.wind_bayernwerk_2025_interpolated
ADD COLUMN IF NOT EXISTS energy_kwh_10min numeric(18,6),
ADD COLUMN IF NOT EXISTS abregelung numeric(18,6),
ADD COLUMN IF NOT EXISTS verlust numeric(18,6);

-- 2) Energieberechnung
WITH params AS (
  SELECT
    3.0::numeric   AS v_ci,     -- Cut-in Windgeschwindigkeit (m/s)
    12.0::numeric  AS v_r,      -- Nennwindgeschwindigkeit (m/s)
    25.0::numeric  AS v_co,     -- Cut-out Windgeschwindigkeit (m/s)
    0.90::numeric  AS eta       -- Systemwirkungsgrad
)
UPDATE dwd.wind_bayernwerk_2025_interpolated m
SET energy_kwh_10min =
  CASE
    -- Unter Cut-in oder über Cut-out → 0
    WHEN COALESCE(m.interpolated_wind_speed, 0) < p.v_ci
      OR COALESCE(m.interpolated_wind_speed, 0) > p.v_co
    THEN 0

    -- Zwischen Cut-in und Nennwind → kubische Approximation
    WHEN COALESCE(m.interpolated_wind_speed, 0) <= p.v_r
    THEN LEAST(
           COALESCE(mod.installierte_leistung, 0)   -- kW (Nennleistung)
           * p.eta
           * POWER(
               (COALESCE(m.interpolated_wind_speed, 0) - p.v_ci)
               / (p.v_r - p.v_ci),
             3)
           / 6.0,                                    -- kWh pro 10 min
           COALESCE(mod.installierte_leistung, 0) / 6.0  -- Deckel
         )

    -- Zwischen Nennwind und Cut-out → volle Leistung
    ELSE
      COALESCE(mod.installierte_leistung, 0)         -- kW
      * p.eta
      / 6.0                                          -- kWh pro 10 min
  END
FROM redispatch.redispatch_eeg_bayernwerk mod, params p
WHERE mod.eventnummer = m.eventnummer;

-- 3) Abregelung
UPDATE dwd.wind_bayernwerk_2025_interpolated m
SET abregelung = ((r.controlstage::double precision / 100) * r.installierte_leistung::double precision) / 6
FROM redispatch.redispatch_eeg_bayernwerk r
WHERE r.eventnummer = m.eventnummer;

-- 4) Verlust (nicht negativ)
UPDATE dwd.wind_bayernwerk_2025_interpolated
SET verlust = GREATEST(COALESCE(energy_kwh_10min, 0) - COALESCE(abregelung, 0), 0);

-- 5) Aggregierten Verlust zurückschreiben
UPDATE redispatch.redispatch_eeg_bayernwerk r
SET verlust = COALESCE(agg.sum_verlust, 0)
FROM (
  SELECT eventnummer, SUM(COALESCE(verlust, 0)) AS sum_verlust
  FROM dwd.wind_bayernwerk_2025_interpolated
  GROUP BY eventnummer
) agg
WHERE r.eventnummer = agg.eventnummer;



REFRESH MATERIALIZED VIEW headless_qgis.qgis_projects_all_db;
