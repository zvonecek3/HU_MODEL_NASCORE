Cíl:
Read-only analýza procedury HU_model_nascore.

Zásady:
- nespouštět CREATE OR REPLACE PROCEDURE,
- nespouštět TRUNCATE,
- nespouštět INSERT do produkčních tabulek,
- veškeré testy dělat přes CTE,
- sysdate nahrazovat fixním as_of_date,
- sample držet deterministicky přes ora_hash(skp_client).
