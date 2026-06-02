# STEP 4 – `HU_model_sum_con_sc`

## Účel kroku

STEP 4 agreguje historii smluv z tabulky `HU_model_con_sc` na úroveň klienta.

Vstupní tabulka `HU_model_con_sc` má více řádků na klienta, protože obsahuje kontraktovou historii rozpadnutou podle:

* `SKP_CLIENT`
* `SKP_CREDIT_TYPE`
* `CODE_CREDIT_STATUS`
* `CREDIT_SEGMENT`
* segmentačních atributů smlouvy

Výstupní tabulka `HU_model_sum_con_sc` má být klientský souhrn:

```text
1 řádek na SKP_CLIENT
```

STEP 4 tedy funguje jako pivot / agregace z dlouhého formátu do širokého klientského formátu.

---

## Produkční logika

Krok počítá počty smluv podle typu produktu, statusu a segmentu:

### `su_*`

Počty pro:

```text
SKP_CREDIT_TYPE = 1
```

Sloupce:

```text
su_a, su_k, su_z, su_o, su_s, su_t, su_u
```

---

### `hu_akv_*`

Počty pro:

```text
SKP_CREDIT_TYPE = 2
CREDIT_SEGMENT = 'akv'
```

Sloupce:

```text
hu_akv_a, hu_akv_k, hu_akv_z, hu_akv_o, hu_akv_s, hu_akv_t, hu_akv_u
```

---

### `hu_x_*`

Počty pro:

```text
SKP_CREDIT_TYPE = 2
CREDIT_SEGMENT = 'x-sell'
```

Sloupce:

```text
hu_x_a, hu_x_k, hu_x_z, hu_x_o, hu_x_s, hu_x_t, hu_x_u
```

Poznámka ze STEP 3: aktuální logika `credit_segment` nevytvořila žádné `x-sell` řádky, proto se očekává, že tyto sloupce budou nulové.

---

### `ru_akv_*`

Počty pro:

```text
SKP_CREDIT_TYPE = 3
CREDIT_SEGMENT = 'akv'
```

Sloupce:

```text
ru_akv_a, ru_akv_k, ru_akv_z, ru_akv_o, ru_akv_s, ru_akv_t, ru_akv_u
```

---

### `ru_x_*`

Počty pro:

```text
SKP_CREDIT_TYPE = 3
CREDIT_SEGMENT = 'x-sell'
```

Sloupce:

```text
ru_x_a, ru_x_k, ru_x_z, ru_x_o, ru_x_s, ru_x_t, ru_x_u
```

Poznámka ze STEP 3: protože nebyly nalezeny žádné `x-sell` řádky, očekává se, že i tyto sloupce budou nulové.

---

### `cc_loc_rl_poc_a`

Speciální souhrnný sloupec:

```sql
sum(case when skp_credit_type = 3 and code_credit_status = 'a' then pocet_cnt else 0 end) as cc_loc_rl_poc_a
```

Tento sloupec počítá všechny aktivní smlouvy pro `SKP_CREDIT_TYPE = 3` bez rozlišení `credit_segment`.

Očekávaný vztah:

```text
cc_loc_rl_poc_a = ru_akv_a + ru_x_a
```

V aktuálním běhu, kde `x-sell` neexistuje:

```text
cc_loc_rl_poc_a = ru_akv_a
```

---

## Očekávaný grain

Výstupní grain tabulky `HU_model_sum_con_sc`:

```text
1 řádek na SKP_CLIENT
```

Kontrola:

```sql
select
    count(*) as row_cnt,
    count(distinct skp_client) as distinct_client_cnt
from HU_model_sum_con_sc;
```

Očekávání:

```text
ROW_CNT = DISTINCT_CLIENT_CNT
```

---

## Auditní výsledky

### Pokrytí kontraktových počtů

Audit ukázal:

| Metrika                              |   Hodnota |
| ------------------------------------ | --------: |
| STEP3 total contracts                | 3 874 708 |
| Covered by STEP4 defined columns     | 3 519 626 |
| Not covered by STEP4 defined columns |   355 082 |

Nepokrytý podíl:

```text
355 082 / 3 874 708 = cca 9.16 %
```

To znamená, že přibližně 9.16 % kontraktových záznamů ze STEP 3 se nedostává do žádného výstupního sloupce ve STEP 4.

---

## Mapované statusy

STEP 4 explicitně mapuje pouze tyto statusy:

| Status | Význam                     |
| ------ | -------------------------- |
| `a`    | Aktivní                    |
| `k`    | Ukončená smlouva           |
| `z`    | Pozastavená smlouva        |
| `o`    | Odeslaný návrh             |
| `s`    | Schválená smlouva          |
| `t`    | Stornovaná smlouva         |
| `u`    | Předčasně ukončená smlouva |

Status `o = Odeslaný návrh` existuje v číselníku, ale v aktuální populaci `HU_model_con_sc` nebyl nalezen. Sloupce s příponou `_o` tedy budou v aktuálním běhu nulové.

---

## Nemapované statusy

V datech existují další statusy, které STEP 4 nepřenáší do žádného výstupního sloupce:

| Status | Význam              | Client count | Contract count |
| ------ | ------------------- | -----------: | -------------: |
| `d`    | Odmítnutý návrh     |            7 |              7 |
| `h`    | Odepsaná pohledávka |      211 733 |        285 475 |
| `l`    | Zesplatněná         |       40 628 |         53 513 |
| `y`    | Vypovězená          |          739 |            803 |

Nejvýznamnější nemapovaný status je:

```text
h = Odepsaná pohledávka
```

Týká se:

```text
211 733 klientů
285 475 kontraktů
```

Druhý významný status je:

```text
l = Zesplatněná
```

Týká se:

```text
40 628 klientů
53 513 kontraktů
```

Tyto statusy jsou pravděpodobně významné z pohledu kreditního rizika a neměly by být ignorované bez business potvrzení.

---

## Kontrola historického rozložení nemapovaných statusů

### `d = Odmítnutý návrh`

Status `d` je marginální a historický.

Výskyt:

```text
celkem 7 kontraktů
poslední výskyt v roce 2013
```

---

### `h = Odepsaná pohledávka`

Status `h` má vysoký celkový objem, hlavně v historických letech.

Pozorování:

```text
status je výrazně zastoupený hlavně v letech 2000–2016
po roce 2020 už má nízké objemy
```

Přesto jde o důležitý historický risk signál.

---

### `l = Zesplatněná`

Status `l` je významný i v novějších letech.

Vybrané roky:

|  Rok | Contract count |
| ---: | -------------: |
| 2020 |          3 236 |
| 2021 |          4 007 |
| 2022 |          6 335 |
| 2023 |          5 313 |
| 2024 |          3 867 |
| 2025 |          1 027 |

Závěr:

```text
l = Zesplatněná je stále aktuálně používaný status a STEP 4 ho kompletně ignoruje.
```

---

### `y = Vypovězená`

Status `y` má nižší objem, ale v novějších letech se stále vyskytuje.

Vybrané roky:

|  Rok | Contract count |
| ---: | -------------: |
| 2021 |             43 |
| 2022 |             70 |
| 2023 |             89 |
| 2024 |             98 |
| 2025 |            251 |
| 2026 |             15 |

Závěr:

```text
y = Vypovězená je objemově menší, ale stále aktuální status.
```

---

## Nepokryté credit typy

STEP 4 pokrývá pouze:

```text
SKP_CREDIT_TYPE in (1, 2, 3)
```

Ve STEP 3 se ale vyskytují také:

```text
SKP_CREDIT_TYPE = 6
SKP_CREDIT_TYPE = 7
```

Tyto typy nejsou ve STEP 4 mapované. Je potřeba potvrdit, zda mají být z modelových feature záměrně vyloučené.

---

## Hlavní zjištění

STEP 4 je technicky správná agregace/pivot z `HU_model_con_sc` do klientského formátu.

Nebyla zde identifikována join multiplikace, protože krok neobsahuje žádné joiny. Hlavní riziko není technické, ale businessové:

```text
mapování statusů je nekompletní nebo zastaralé
```

Aktuální logika nepokrývá statusy:

```text
d, h, l, y
```

Dopad je významný:

```text
355 082 kontraktových záznamů není mapováno do žádné výstupní feature
```

Nejvýznamnější nemapované statusy:

```text
h = Odepsaná pohledávka
l = Zesplatněná
```

---

## Doporučení

### Varianta 1 – pouze reprodukovat původní proceduru

Pokud je cílem pouze reprodukovat původní produkční logiku, STEP 4 lze technicky považovat za validovaný, ale s výhradou:

```text
Status mapping is incomplete. Approximately 9.16% of STEP 3 contract counts are not mapped into STEP 4 output columns.
```

Tuto ztrátu je nutné zdokumentovat.

---

### Varianta 2 – business úprava feature setu

Pokud je cílem vytvořit aktuální a úplnější modelové featury, doporučuje se businessově zvážit doplnění statusů:

```text
h = Odepsaná pohledávka
l = Zesplatněná
y = Vypovězená
```

Možné doplnění:

```text
su_h, su_l, su_y
hu_akv_h, hu_akv_l, hu_akv_y
hu_x_h, hu_x_l, hu_x_y
ru_akv_h, ru_akv_l, ru_akv_y
ru_x_h, ru_x_l, ru_x_y
```

Status `d = Odmítnutý návrh` je marginální a historický. Lze jej buď doplnit pro úplnost, nebo pouze zdokumentovat jako záměrně ignorovaný.

---

### Varianta 3 – agregované bad-status featury

Alternativně lze vytvořit souhrnné rizikové proměnné:

```text
bad_status_cnt = h + l + y
written_off_cnt = h
accelerated_cnt = l
terminated_cnt = y
```

Případně podle produktu:

```text
su_bad_cnt
hu_bad_cnt
ru_bad_cnt
```

Toto už by byla změna business logiky a neměla by být provedena bez schválení.

---

## Finální závěr

STEP 4 je technicky validní jako pivot/agregace na úroveň klienta.

Výstupní tabulka má být unikátní podle `SKP_CLIENT`.

Hlavní problém je nekompletní coverage statusů. Aktuální STEP 4 mapuje jen část statusů a ignoruje přibližně 9.16 % kontraktových záznamů ze STEP 3.

Největší otevřený bod:

```text
Mají být statusy h = Odepsaná pohledávka a l = Zesplatněná zahrnuty do modelových featur?
```

Status:

```text
Technically OK as original logic reproduction.
Business review required for credit status mapping.
```
