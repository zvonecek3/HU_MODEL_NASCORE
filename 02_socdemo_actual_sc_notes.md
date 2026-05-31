STEP 2: hu_socdemo_actual_sc

Účel:
Doplňuje ke klientům sociodemografické atributy, příjem, adresu, zaměstnání, e-client flag, mail/phone flagy a informaci o posledním rejectionu.

Test:
AS_OF_DATE = 2026-04-01
Vstup = 1000 klientů z basic_sample

Výstup:
rows_total = 968
clients_distinct = 968
duplicate_rows = 0
coverage = 96.8 %

Očekávaný grain:
1 řádek na klienta.

Ověřený grain:
Potvrzeno po aplikaci filtru poradi_app = 1.

Ztráta klientů:
32 klientů bylo vyřazeno filtrem name_first not like '%*%'.
Nutno potvrdit, zda je tento business filtr stále validní.

Null hodnoty:
- name_municipality: 33 / 3.41 %
- name_employer: 102 / 10.54 %
- date_employment_from: 102 / 10.54 %
- date_employment_to: 114 / 11.78 %
- adresní atributy: cca 276 / 28.51 %
- months_last_rejection: 836 / 86.36 %

Poznámky:
- Původní procedura používá sysdate, v audit verzi nahrazeno as_of_date.
- Některé zdroje jsou aktuální/current tabulky, takže krok nemusí být plně historický snapshot.
- DATE_EMPLOYMENT_FROM a DATE_EMPLOYMENT_TO nejsou datumy, ale počet měsíců.
- amt_income_total převádí missing hodnoty na 0.
- flag_phone_verified = 0 může znamenat buď neověřený telefon, nebo žádný telefon.
- row_number() může maskovat násobení řádků z left joinů; nutné ověřit socdemo_pre před poradi_app = 1.

Doporučení:
- Ověřit násobení před poradi_app = 1.
- Ověřit zdroje násobení: application, eclient, employer, person_ad, geography.
- Potvrdit business validitu filtru na hvězdičku ve jméně.
- Zdokumentovat employment sloupce nebo navrhnout jejich přejmenování.
- Zvážit doplnění flag_income_missing.







new:

STEP 2: hu_socdemo_actual_sc

Účel:
Doplňuje ke klientům sociodemografické atributy, příjem z application, počet dětí, adresu, obec, zaměstnavatele, e-client flag, mail/phone flagy a informaci o posledním rejectionu.

Zdrojová logika:
Výstup se tvoří z klienta z HU_model_basic_sc / basic_sample a následných joinů na:
- owner_dwh.dc_client
- owner_dwh.dc_client_demography
- owner_dwh.f_application_detail_tt
- owner_dwh.dc_eclient_account
- owner_dwh.f_client_address_tt + owner_dwh.dh_address
- dm_campaign.cl_cmp_geography
- owner_dwh.f_client_employer_tt
- dm_campaign.f_person_ad

Testovací nastavení:
AS_OF_DATE = 2026-04-01
Audit verze nahrazuje sysdate fixním as_of_date.
Testováno na vzorku 1000 klientů pro základní null profil a na vzorku 5000 klientů pro detailní kontrolu násobení.

Základní výstup na vzorku 1000:
input_clients = 1000
rows_total = 968
clients_distinct = 968
duplicate_rows = 0
coverage = 96.8 %

Očekávaný grain:
1 řádek na klienta.

Ověřený grain:
Finální výstup má 1 řádek na klienta po aplikaci filtru poradi_app = 1.

Ztráta klientů:
Na vzorku 1000 bylo 32 klientů vyřazeno filtrem c.name_first not like '%*%'.
Na vzorku 5000 bylo stejným filtrem vyřazeno 143 klientů.
Nutno potvrdit, zda je tento business filtr stále validní.

Null profil na vzorku 1000:
- name_municipality: 33 / 3.41 %
- name_employer: 102 / 10.54 %
- date_employment_from: 102 / 10.54 %
- date_employment_to: 114 / 11.78 %
- adresní atributy name_street / name_town / text_street_number: cca 276 / 28.51 %
- months_last_rejection: 836 / 86.36 %

Kontrola násobení před poradi_app = 1:
Na vzorku 1000:
- rows_before_rn_filter = 3282
- clients_distinct = 968
- extra_rows_before_rn_filter = 2314
- max_rows_per_client = 60

Na vzorku 5000:
- valid clients after business filter = 4857
- rows before final row_number filter = 15919
- extra rows = 11062
- max rows per client = 96

Interpretace:
Krok finálně vrací 1 řádek na klienta, ale před finálním filtrem vytváří významné násobení.
Finální grain je tedy dosažen až dodatečně přes row_number, ne řízeným 1:1 joinem jednotlivých zdrojů.

Zdroj násobení:
1. f_application_detail_tt
   - 4830 klientů má application záznam
   - 2880 klientů má více application záznamů
   - total_source_rows = 14323
   - avg_rows_if_present = 2.97
   - max_rows_per_client = 57
   - hlavní zdroj násobení

2. dc_eclient_account
   - 1445 klientů má eclient záznam
   - 143 klientů má více eclient záznamů
   - max_rows_per_client = 7
   - výstupní flag_eclient je stabilní, ale join zbytečně násobí řádky

3. f_client_employer_tt
   - 3476 klientů má employer záznam
   - 99 klientů má více employer záznamů
   - max_rows_per_client = 2
   - u 73 klientů se liší name_employer / months_employment_from
   - obsahově rizikové, protože současný row_number neobsahuje business pravidlo výběru zaměstnavatele

4. address
   - ve zdroji existuje více adresních kandidátů, ale subquery vybírá rn = 1
   - po address joinu už řádky nepřibývají
   - není hlavní zdroj problému

5. geography
   - po vybrané adrese 1:1
   - nezpůsobuje násobení

6. person_ad
   - na vzorku 1:1
   - nezpůsobuje násobení
   - flag_mail / flag_phone / flag_phone_verified jsou stabilní

Application tie kontrola:
Na vzorku 5000:
- clients_with_latest_app = 4830
- clients_with_latest_app_tie = 166
- max_latest_rows_per_client = 4

U klientů s více latest application kandidáty:
- clients_diff_amt_income = 32
- clients_diff_amt_income_total = 43
- clients_diff_cnt_children = 7

Interpretace application tie:
166 klientů má více application záznamů se stejným nejnovějším date_decision.
U části z nich se liší hodnoty příjmu nebo počet dětí.
Současný order by a.date_decision desc tedy není vždy dostatečný pro jednoznačný výběr application záznamu.

Rizika:
- row_number je aplikovaný až po všech joinech, takže maskuje násobení řádků
- application výběr není vždy deterministický při stejném date_decision
- employer výběr není řízený business pravidlem
- eclient join zbytečně násobí řádky, i když výstupem je jen flag
- původní procedura používá sysdate, audit verze používá as_of_date
- některé zdroje jsou current tabulky, takže STEP 2 nemusí být plně historický snapshot
- DATE_EMPLOYMENT_FROM a DATE_EMPLOYMENT_TO obsahují počet měsíců, ne datum
- amt_income_total převádí missing hodnoty na 0

Doporučení:
- Nepřepisovat produkční proceduru bez potvrzení.
- V auditní dokumentaci označit STEP 2 jako WARN / ISSUE LOGGED.
- Pro budoucí refactoring připravit zdroje na grain 1 řádek na klienta před hlavním joinem:
  - application_last
  - eclient_flag
  - address_one
  - employer_one
  - person_ad_flags
- Najít stabilní tie-breaker pro application při stejném date_decision.
- Definovat business pravidlo pro výběr employer záznamu.
- Potvrdit business validitu filtru c.name_first not like '%*%'.
- Zdokumentovat nebo přejmenovat employment sloupce.


