STEP 1: HU_model_basic_sc

Účel:
Definuje základní klientskou populaci pro měsíční nápočet prediktorového datamartu.

Zdroj:
AP_CRM_MODEL.sdm_person_history

Produkční logika:
Bere distinct skp_client pro month_inserted = trunc(sysdate, 'mm').

Testovací úprava:
sysdate nahrazeno fixním parametrem as_of_date.
Testováno pro AS_OF_DATE = 2026-04-01.

Výsledek:
FULL:
rows_total = 1 867 984
clients_distinct = 1 867 984
duplicate_rows = 0

SAMPLE:
rows_total = 1000
clients_distinct = 1000
duplicate_rows = 0

Očekávaný grain:
1 řádek na klienta.

Ověřený grain:
Potvrzeno. rows_total = clients_distinct.

Časová logika:
Původní procedura používá trunc(sysdate, 'mm').
Pokud v sdm_person_history ještě neexistuje snapshot pro aktuální měsíc spuštění, krok vrátí 0 klientů.

Anomálie:
Snapshot 2025-09-01 má pouze 11 555 klientů, zatímco okolní měsíce mají cca 1,8M klientů.
Nutno ověřit, zda jde o nekompletní snapshot, změnu zdroje, nebo datový incident.

Poznámka ke kódu:
LEFT JOIN na hu_model_score_history aktuálně nemá funkční efekt, protože se z tabulky b nic nevybírá a podmínka b.skp_client is null je zakomentovaná.
Nutno vyjasnit, zda měl join původně sloužit k vyřazení již skórovaných klientů.

Doporučení:
1. Parametrizovat as_of_date místo sysdate.
2. Zvážit fallback na poslední dostupný month_inserted <= as_of_date.
3. Vyjasnit účel joinu na hu_model_score_history.
4. Nechat krok zatím beze změny v produkci, pouze zdokumentovat rizika.

Status:
OK s poznámkou.
