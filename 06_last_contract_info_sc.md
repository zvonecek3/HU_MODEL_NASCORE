# STEP 6 – `HU_model_last_con_info_sc`

## Účel kroku

STEP 6 rozšiřuje poslední smlouvu klienta vybranou v kroku STEP 5 o detailní informace o smlouvě, produktu, distribučním kanálu, prodejci, segmentaci a dalších odvozených ukazatelích.

### Vstup

```text
HU_model_last_con_sc
```

### Výstup

```text
HU_model_last_con_info_sc
```

### Očekávaný grain

```text
1 řádek na klienta
```

---

## Hlavní logika

Krok připojuje k poslední smlouvě klienta informace z tabulek:

- `f_contract_ad`
- `cl_credit_status`
- `dc_credit_segmentation`
- `dc_product`
- `dc_salesroom`
- `dc_seller`
- `f_credit_status_tt`
- subquery s benefit / turbo příznaky

Současně vytváří několik odvozených atributů:

- aktuální status smlouvy
- produktové atributy
- distribuční kanál
- profit group
- segmentaci
- obchodní značku smlouvy (`contract_brand`)
- MOB (Months On Book)
- benefit / turbo příznak
- podíl nesplacené jistiny (`zbyva_doplatit`)
- počet nezaplacených splátek

---

## Ověření grainu

Audit potvrdil:

```text
1 klient = 1 řádek
```

Provedené kontroly:

- počet řádků = počet unikátních klientů
- nebyly nalezeny duplicitní klientské záznamy
- žádný join nemultiplikuje data
- žádný join neztrácí data

---

## Kontrola joinů

Byla provedena postupná kontrola všech povinných joinů.

| Krok | Počet řádků | Počet klientů |
|--------|-----------:|-------------:|
| 01_base_step5 | 1 627 070 | 1 627 070 |
| 02_with_contract_ad | 1 627 070 | 1 627 070 |
| 03_with_credit_status | 1 627 070 | 1 627 070 |
| 04_with_segmentation | 1 627 070 | 1 627 070 |
| 05_with_product | 1 627 070 | 1 627 070 |
| 06_with_salesroom | 1 627 070 | 1 627 070 |
| 07_with_seller | 1 627 070 | 1 627 070 |

### Závěr

```text
Žádný z povinných joinů nezpůsobuje ztrátu dat.
Žádný z povinných joinů nezpůsobuje vznik duplicit.
```

---

## Kontrola použití DISTINCT

Produkční kód používá:

```sql
select distinct ...
```

Byla provedena kontrola počtu řádků před a po aplikaci `DISTINCT`.

### Výsledek

```text
Počet řádků před DISTINCT = počet řádků po DISTINCT
```

### Závěr

```text
DISTINCT je pro aktuální datovou populaci nadbytečný.
```

Nemění výsledky ani neopravuje žádný problém s duplicitami.

Jeho odstranění by nemělo změnit výstup kroku.

---

## Logika statusu smlouvy

Krok primárně používá aktuální status z:

```text
f_credit_status_tt
```

Pokud aktuální status není k dispozici, použije se náhradní status uložený ve:

```text
f_contract_ad
```

### Výsledky auditu

| Použit fallback | Počet řádků |
|---------------|------------:|
| Ne | 1 605 759 |
| Ano | 21 311 |

Podíl fallbacku:

```text
21 311 / 1 627 070 = 1,31 %
```

### Závěr

Fallback mechanismus je využíván pouze u malé části záznamů a nevykazuje známky problému.

---

## Benefit / Turbo příznak

Benefit atribut je získáván pomocí analytické funkce:

```sql
row_number() over (
    partition by skp_credit_case
    order by dtime_valid_to desc
)
```

Audit ukázal:

- přibližně 1 600 kreditních případů má dvě hodnoty na posledním datu
- 23 kreditních případů mají tři hodnoty na posledním datu

To znamená, že výběr benefitu nemusí být v těchto případech zcela deterministický.

### Dopad

```text
cca 0,1 % všech záznamů
```

### Závěr

Jedná se o velmi malý objem dat bez dopadu na grain tabulky nebo počet klientů.

---

## Závislost na STEP 5

STEP 6 využívá jako vstup výstup z kroku STEP 5.

Aktuální produkční tabulka STEP 5 obsahuje:

```text
1 627 070 klientů
```

Auditní varianta STEP 5 s validním filtrem na `f_credit_status_tt` obsahovala pouze:

```text
388 451 klientů
```

Tento rozdíl vzniká logikou STEP 5 a není způsoben krokem STEP 6.

---

## Zjištění

### Zjištění 1

Nebyl nalezen žádný problém s joiny.

### Zjištění 2

Nebyly nalezeny duplicity klientů.

### Zjištění 3

DISTINCT je nadbytečný, ale neškodný.

### Zjištění 4

Výběr benefit příznaku může být v malém počtu případů nedeterministický.

### Zjištění 5

STEP 6 přebírá případné problémy z populace vytvořené ve STEP 5.

---

## Finální závěr

STEP 6 korektně rozšiřuje poslední smlouvu klienta o produktové, segmentační a smluvní informace.

Audit potvrdil:

- stabilní grain (1 klient = 1 řádek)
- žádné ztráty dat při joinování
- žádné multiplikace dat
- žádné duplicitní klienty

Nebyla identifikována žádná chyba vyžadující úpravu logiky.

### Status

```text
Technicky validováno.
Pro reprodukci původní logiky nejsou potřeba žádné změny.
```
