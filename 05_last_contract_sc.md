# STEP 5 – `HU_model_last_con_sc`

## Účel kroku

STEP 5 vybírá poslední smlouvu klienta z kontraktové historie.

Do tabulky `HU_model_last_con_sc` se ukládá:

* `SKP_CLIENT`
* `CREDIT_CASE_AKV`
* `CREDIT_TYPE_AKV`
* `DADE_AKV`

Výběr je omezen pouze na smlouvy se statusem:

* `a` = Aktivní
* `s` = Schválená smlouva

Výstupní grain má být:

```text
1 řádek na SKP_CLIENT
```

Pouze pro klienty, kteří mají alespoň jednu smlouvu ve statusu `a` nebo `s`.

---

## Produkční logika

Produkční kód používá:

```sql
row_number() over (
    partition by b.skp_client
    order by c.date_decision desc
) as poradi
```

a následně vybírá:

```sql
where poradi = 1
```

Tím se pro každého klienta vybere smlouva s nejnovějším `DATE_DECISION`.

---

## Důležité pozorování

Názvy sloupců obsahují příponu `_akv`:

* `credit_case_akv`
* `credit_type_akv`
* `dade_akv`

V SQL ale není žádná podmínka na:

```sql
credit_segment = 'akv'
```

Krok tedy nevybírá poslední akviziční smlouvu, ale poslední smlouvu se statusem `a` nebo `s`.

Název sloupců je proto zavádějící.

---

## Auditní výsledky

### Počet eligible smluv

Audit s fixním `AS_OF_DATE = DATE '2026-04-01'` ukázal:

| Metrika                        | Hodnota |
| ------------------------------ | ------: |
| Eligible contract rows         | 431 288 |
| Clients with eligible contract | 388 451 |
| Eligible credit cases          | 431 288 |

Eligible smlouvy jsou definované jako smlouvy klientů z `HU_model_basic_sc`, které mají k auditnímu datu validní status `a` nebo `s`.

---

## Join na segmentaci

STEP 5 připojuje:

```sql
owner_dwh.dc_credit_segmentation
```

ale žádný sloupec ze segmentace se neukládá do výsledné tabulky.

Audit ukázal:

| Step                   | Row count | Client count | Credit case count |
| ---------------------- | --------: | -----------: | ----------------: |
| `01_eligible_status`   |   431 288 |      388 451 |           431 288 |
| `02_with_segmentation` |   431 288 |      388 451 |           431 288 |

Závěr:

* join na segmentaci v auditní populaci nic nezahazuje,
* zároveň není použitý pro výsledný výstup,
* funguje pouze jako implicitní filtr existence segmentace.

---

## Hlavní finding: chybějící validita statusu

Produkční STEP 5 joinuje `f_credit_status_tt`, ale nepoužívá filtr validity:

```sql
sysdate between s.dtime_valid_from and s.dtime_valid_to
```

Na rozdíl od STEP 3 zde tedy může dojít k připojení více historických statusových řádků pro jeden kontrakt.

Audit bez validity ukázal, že `f_credit_status_tt` obsahuje více statusových řádků pro většinu kontraktů.

Příklady:

| STATUS_ROWS | CONTRACT_CNT |
| ----------: | -----------: |
|           1 |           29 |
|           2 |        9 360 |
|           3 |      657 986 |
|           4 |    2 051 046 |
|           5 |      714 767 |
|           6 |      317 209 |
|           7 |       92 786 |
|           8 |        4 513 |
|           9 |        2 503 |
|          10 |          442 |

Závěr:

```text
f_credit_status_tt je historizovaná tabulka.
Bez filtru validity STEP 5 pracuje s historickými verzemi statusů.
```

To je hlavní technické riziko tohoto kroku.

Doporučená auditní / opravená logika:

```sql
where p.as_of_date between s.dtime_valid_from and s.dtime_valid_to
```

---

## Finding: nedeterministický výběr poslední smlouvy

Produkční `row_number()` řadí pouze podle:

```sql
order by c.date_decision desc
```

Pokud má klient více eligible smluv se stejným nejnovějším `DATE_DECISION`, výběr konkrétního `SKP_CREDIT_CASE` není deterministický.

Audit ukázal:

| Metrika                                                            |     Hodnota |
| ------------------------------------------------------------------ | ----------: |
| Clients with eligible `a/s` contract                               |     388 451 |
| Clients with multiple eligible contracts on latest `DATE_DECISION` |         284 |
| Affected share                                                     | cca 0.073 % |

Závěr:

Dopad je objemově nízký, ale u těchto 284 klientů nemusí být vybraný `CREDIT_CASE_AKV` stabilní mezi běhy.

Doporučený stabilní tie-breaker:

```sql
order by
    c.date_decision desc,
    c.skp_credit_case desc,
    c.skp_credit_type desc
```

---

## Rizika

### 1. Chybějící validita `f_credit_status_tt`

Bez validity se joinuje více historických statusových záznamů pro jeden kontrakt. To může ovlivnit výběr poslední smlouvy a způsobit nekonzistenci proti STEP 3.

### 2. Nedeterministické řazení

Při shodném `DATE_DECISION` není určeno, který kontrakt má být vybrán.

### 3. Zavádějící názvy sloupců

Sloupce s příponou `_akv` neznamenají, že smlouva je akviziční. V kódu není filtr na `credit_segment = 'akv'`.

### 4. `SYSDATE`

Produkční kód používá:

```sql
c.date_decision < sysdate
```

Pro audit a backtest je vhodnější fixní `AS_OF_DATE`.

---

## Doporučení

Pro audit a případnou opravu logiky používat:

```sql
p.as_of_date between s.dtime_valid_from and s.dtime_valid_to
and c.date_decision < p.as_of_date
```

a stabilní výběr poslední smlouvy:

```sql
row_number() over (
    partition by b.skp_client
    order by
        c.date_decision desc,
        c.skp_credit_case desc,
        c.skp_credit_type desc
) as poradi
```

---

## Finální závěr

STEP 5 je technicky srozumitelný krok, který vybírá poslední smlouvu klienta se statusem `a` nebo `s`.

Výstup má mít 1 řádek na klienta.

Hlavní problém je chybějící validita na `f_credit_status_tt`. Audit ukázal, že bez tohoto filtru se připojuje více historických statusových řádků pro jeden kontrakt.

Druhé riziko je nedeterministický výběr při shodném `DATE_DECISION`, ale tento problém se týká jen 284 klientů, tedy cca 0.073 % eligible klientů.

Status:

```text
Technically understandable, but status validity filter should be reviewed.
Recommended fix: add valid-time filter and deterministic tie-breaker.
```
