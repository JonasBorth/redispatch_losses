
------------------------------------Avacon------------------------------------------------
--------------------------------------------------------------------------------------------





DROP TABLE IF EXISTS redispatch.raw_data_avacon;
CREATE TABLE IF NOT EXISTS redispatch.raw_data_avacon (
    eventnummer SERIAL PRIMARY KEY,
    id TEXT,
    operationid TEXT,
    srid TEXT,
    star TIMESTAMP,
    ende TIMESTAMP,
    duration NUMERIC,
    location TEXT,
    locationbottleneck TEXT,
    controlstage TEXT,
    reason TEXT,
    reasontwo TEXT,
    assetkey TEXT,
    requestor TEXT,
    liabilityofcompensation TEXT,
    dsokey TEXT,
    inducingno TEXT,
    kalkid TEXT,
    verlust NUMERIC
);


----------------- Insert the redispatch data for with ipynb file now -----------------


-------------------------------combine with msr_eeg--------------------------------


DROP TABLE IF EXISTS redispatch.redispatch_eeg_avacon;
CREATE TABLE redispatch.redispatch_eeg_avacon AS
SELECT
  brj.*,
  eeg.msr_nr,
  eeg.energie,
  eeg.installierte_leistung,  
  eeg.modulzahl,
  eeg.hauptausrichtung,
  eeg.rotor_r_m,
  eeg.naben_h_m,
  eeg.netzanschluss,
  eeg.geom
FROM redispatch.raw_data_avacon brj
LEFT JOIN msr.msr_eeg eeg
  ON brj.assetKey = eeg.anlagenschluessel_eeg
WHERE brj.reason LIKE '%Netzengpass%' AND eeg.geom IS NOT NULL;


ALTER TABLE redispatch.redispatch_eeg_avacon
ADD COLUMN startpunkt DATE,
ADD COLUMN endpunkt TIME;

UPDATE redispatch.redispatch_eeg_avacon
SET 
  startpunkt= (star::TIMESTAMPTZ),
  endpunkt = (ende::TIMESTAMPTZ);



CREATE INDEX idx_redispatch_eeg_avacon_eventnummer ON redispatch.redispatch_eeg_avacon(eventnummer);




