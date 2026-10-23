------------------------------------Bayernwerk------------------------------------------------
--------------------------------------------------------------------------------------------



-- 1) Spalte anlegen
ALTER TABLE dwd.solar_bayernwerk_2025_interpolated
ADD COLUMN energy_kwh_10min numeric(18,6),
ADD COLUMN abregelung NUMERIC(18,6),
ADD COLUMN verlust NUMERIC(18,6);

-- 2) UPDATE mit Konstanten (hier als CTE)

WITH params AS (
  SELECT
    0.85::numeric AS perf_ratio           -- Performance Ratio (Systemverluste)
)
UPDATE dwd.solar_bayernwerk_2025_interpolated m
SET energy_kwh_10min =
  LEAST(
    -- Theorie auf Leistungsbasis:
    -- H (kWh/m²) = radiation_global / 360
    -- E_theo = P_inst (kW) * PR * H
    COALESCE(mod.installierte_leistung, 0)            -- kW
    * p.perf_ratio                                    -- PR
    * GREATEST(0, (m.interpolated_radiation / 360.0)),      -- kWh/m²
    -- Deckel: max. Energie in 10 Minuten bei Nennleistung
    COALESCE(mod.installierte_leistung, 0) / 6.0      -- kWh
  )
FROM redispatch.redispatch_eeg_bayernwerk mod, params p
WHERE mod.eventnummer = m.eventnummer;

-- Abregelung (wie von dir gewünscht beibehalten)
UPDATE dwd.solar_bayernwerk_2025_interpolated m
SET abregelung = ((r.controlstage::double precision / 100) * r.installierte_leistung::double precision) / 6
FROM redispatch.redispatch_eeg_bayernwerk r
WHERE r.eventnummer = m.eventnummer;


-- Verlust (nicht negativ)
UPDATE dwd.solar_bayernwerk_2025_interpolated
SET verlust = GREATEST(COALESCE(energy_kwh_10min, 0) - COALESCE(abregelung, 0), 0);




-- Variante 1: Alles auf einmal (schnell, wenn Indizes passen)

UPDATE redispatch.redispatch_eeg_bayernwerk r
SET verlust = COALESCE(agg.sum_verlust, 0)
FROM (
  SELECT eventnummer, SUM(COALESCE(verlust, 0)) AS sum_verlust
  FROM dwd.solar_bayernwerk_2025_interpolated
  GROUP BY eventnummer
) agg
WHERE r.eventnummer = agg.eventnummer;




