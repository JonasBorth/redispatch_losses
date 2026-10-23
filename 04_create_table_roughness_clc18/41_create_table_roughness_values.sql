
-- Tabelle für CLC-2018 Rauhigkeitslängen (Quelle: EMD Lookup / WindPRO; DTU Vergleich) [help.emd.dk]
-- Geeignet für PostgreSQL, MySQL, SQL Server (ANSI SQL-Datentypwahl)

CREATE TABLE dwd.clc2018_roughness (
    clc_code INTEGER PRIMARY KEY,           -- z.B. '1.1.1'
    clc_name VARCHAR(100) NOT NULL,             -- Beschreibung
    z0_emd_m DECIMAL(10,5) NOT NULL,            -- Rauhigkeitslänge nach EMD (m)
    z0_dtu_m DECIMAL(10,5),                     -- Vergleichswert DTU (m), falls verfügbar
    note TEXT                                   -- ggf. Anmerkungen
);

INSERT INTO dwd.clc2018_roughness (clc_code, clc_name, z0_emd_m, z0_dtu_m, note) VALUES
('111','Continuous urban fabric',0.50000,1.00000,NULL),
('112','Discontinuous urban fabric',0.40000,0.80000,NULL),
('121','Industrial or commercial units',0.70000,0.70000,NULL),
('122','Road and rail networks and associated land',0.10000,0.10000,NULL),
('123','Port areas',0.50000,0.50000,NULL),
('124','Airports',0.03000,0.01000,NULL),
('131','Mineral extraction sites',0.10000,0.05000,NULL),
('132','Dump sites',0.10000,0.05000,NULL),
('133','Construction sites',0.30000,0.30000,NULL),
('141','Green urban areas',0.40000,0.80000,NULL),
('142','Sport and leisure facilities',0.50000,0.20000,NULL),

('211','Non-irrigated arable land',0.05600,0.05000,NULL),
('212','Permanently irrigated land',0.05600,0.03000,NULL),
('213','Rice fields',0.01840,0.03000,NULL),

('221','Vineyards',0.30000,0.30000,NULL),
('222','Fruit trees and berry plantations',0.40000,0.40000,NULL),
('223','Olive groves',0.40000,0.40000,NULL),

('231','Pastures',0.03600,0.03000,NULL),

('241','Annual crops associated with permanent crops',0.05600,0.10000,NULL),
('242','Complex cultivation patterns',0.05600,0.15000,NULL),
('243','Agriculture with significant natural vegetation',0.05600,0.20000,NULL),
('244','Agro-forestry areas',0.50000,0.50000,NULL),

('311','Broad-leaved forest',0.50000,1.00000,NULL),
('312','Coniferous forest',0.50000,1.20000,NULL),
('313','Mixed forest',0.50000,1.10000,NULL),

('321','Natural grassland',0.05600,0.03000,NULL),
('322','Moors and heathland',0.06000,0.05000,NULL),
('323','Sclerophyllous vegetation',0.05600,0.07000,NULL),
('324','Transitional woodland-scrub',0.40000,0.40000,NULL),

('331','Beaches, dunes, and sand plains',0.01000,0.00300,NULL),
('332','Bare rock',0.05000,0.05000,NULL),
('333','Sparsely vegetated areas',0.20000,0.03000,NULL),
('334','Burnt areas',0.20000,0.20000,NULL),
('335','Glaciers and perpetual snow',0.00500,0.00500,'Wert vor 2020: 0.20000'),

('411','Inland marshes',0.05000,0.05000,NULL),
('412','Peat bogs',0.01840,0.03000,NULL),

('421','Salt marshes',0.03480,0.02000,NULL),
('422','Salines',0.03000,0.00500,NULL),
('423','Intertidal flats',0.00050,0.00000,NULL),

('511','River',0.00000,0.00000,NULL),
('512','Lake',0.00000,0.00000,NULL),

('521','Coastal lagoons',0.00000,0.00000,NULL),
('522','Estuaries',0.00000,0.00000,NULL),
('523','Sea and ocean',0.00000,0.00000,NULL),

('NO DATA','No data',-1.00000,NULL,'Platzhalter für fehlende Werte');


-- Values for roughness length classification of Corine Land Cover classes can be found in the following publication:
-- https://www.researchgate.net/publication/228474930_Roughness_length_classification_of_Corine_Land_Cover_classes
