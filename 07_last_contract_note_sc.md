# STEP 7 – `HU_model_last_con_note_sc`

## Účel kroku

STEP 7 doplňuje k poslední smlouvě klienta informace o:

- poznámkách na smlouvě,
- retenčních benefitech,
- typu výpisu.

Krok je rozdělený na dvě části:

```text
STEP 7.1 – vytvoření retenční pomocné tabulky
STEP 7.2 – vytvoření klientského souhrnu poznámek, retencí a výpisu
```

---

## STEP 7.1 – `ft_tmp_contract_ad_ret_benefit`

### Účel

Pomocná tabulka `ft_tmp_contract_ad_ret_benefit` agreguje retenční akce z:

```text
owner_dwh.f_credit_action_tt
owner_dwh.cl_credit_action_type
```

na úroveň:

```text
SKP_CREDIT_CASE × SKP_CREDIT_TYPE × DATE_DECISION
```

Pro každý typ retenční akce se ukládá poslední datum jejího výskytu.

---

## Výstupní retenční atributy

| Sloupec | Logika |
|---|---|
| `date_ret_interest` | retenční úrokové akce `RET%`, kromě `RET_ATM_12`, a také `RE0,99%12M` |
| `date_ret_20kc` | `RE20KcPopl` |
| `date_ret_cb` | kódy začínající `RE10%` |
| `date_ret_account_free` | `RE12m_bezP`, `RE12m_novy`, `RE0KcPopl` |
| `date_ret_atm` | `RET_ATM_12` |
| `date_ret_cb_12_sik` | `CB1_12_SIK` |
| `date_ret_cb_12_kar` | `CB2_12_KAR` |
| `date_ret_turbo_25_k` | `Turbo_25_K` |

---

## Grain validace STEP 7.1

Audit potvrdil:

| Metrika | Hodnota |
|---|---:|
| Row count | 20 447 |
| Distinct keys | 20 447 |

Závěr:

```text
Pomocná retenční tabulka má správný grain.
Nebyly nalezeny duplicity na úrovni SKP_CREDIT_CASE × SKP_CREDIT_TYPE × DATE_DECISION.
```

---

## STEP 7.2 – `HU_model_last_con_note_sc`

### Účel

STEP 7.2 vytváří klientský souhrn nad poslední smlouvou klienta.

Vstupní tabulky:

- `HU_model_last_con_sc`
- `HU_model_basic_sc`
- `f_business_note_tt`
- `cl_note_type`
- `ft_tmp_contract_ad_ret_benefit`
- `f_contract_service_tt`
- `dc_service_type`

Výstupní tabulka:

```text
HU_model_last_con_note_sc
```

Očekávaný grain:

```text
1 řádek na klienta
```

---

## Výstupní atributy

### Poznámky

Krok sleduje typy poznámek:

| Kód poznámky | Význam v proceduře |
|---|---|
| `JD00` | společně s `VS00` vstupuje do `dtime_jd_vs` a `cnt_months_jd_vs` |
| `VS00` | společně s `JD00` vstupuje do `dtime_jd_vs` a `cnt_months_jd_vs` |
| `PSL1` | vstupuje do `dtime_psl` a `cnt_months_psl` |

Výstupní sloupce:

- `dtime_jd_vs`
- `cnt_months_jd_vs`
- `dtime_psl`
- `cnt_months_psl`

---

### Retenční benefity

Z pomocné tabulky `ft_tmp_contract_ad_ret_benefit` se vytvářejí binární příznaky:

| Sloupec | Logika |
|---|---|
| `ret_account_free` | `date_ret_account_free is not null` |
| `ret_interest` | `date_ret_interest is not null` |
| `ret_atm` | `date_ret_atm is not null` |
| `ret_cb` | `date_ret_cb`, `date_ret_cb_12_kar` nebo `date_ret_cb_12_sik` není null |
| `ret_25_turbo` | `date_ret_turbo_25_k is not null` |
| `ret_20` | `date_ret_20kc is not null` |

---

### Typ výpisu

Krok sleduje služby:

| Kód služby | Význam |
|---|---|
| `E_STATEMENT` | e-výpis |
| `PAPER_STATEMENT` | papírový výpis |

Výstupní hodnota `vypis`:

| Podmínka | Hodnota |
|---|---|
| existuje `E_STATEMENT` i `PAPER_STATEMENT` | `obojí` |
| existuje jen `E_STATEMENT` | `e-výpis přes Copy General` |
| existuje jen `PAPER_STATEMENT` | `papírový výpis` |
| neexistuje žádná služba | `null` |

---

## Grain validace STEP 7.2

Audit potvrdil:

```text
počet řádků = počet klientů
počet klientů s více než jedním řádkem = 0
```

Závěr:

```text
HU_model_last_con_note_sc má správný grain 1 řádek na klienta.
```

---

## Validace používaných kódů poznámek

Cílená kontrola potvrdila, že všechny používané kódy poznámek existují a mají významný objem:

| CODE_NOTE_TYPE | NOTE_CNT |
|---|---:|
| `JD00` | 5 693 111 |
| `PSL1` | 66 865 |
| `VS00` | 722 395 |

Závěr:

```text
Kódy poznámek používané ve STEP 7.2 jsou aktuálně přítomné v datech.
```

---

## Validace používaných služeb výpisu

Cílená kontrola potvrdila, že oba používané typy služeb existují:

| CODE_SERVICE_TYPE | SERVICE_CNT |
|---|---:|
| `E_STATEMENT` | 3 066 169 |
| `PAPER_STATEMENT` | 3 798 937 |

Závěr:

```text
Kódy služeb používané pro výpočet atributu vypis jsou aktuálně přítomné v datech.
```

---

## Validace retenčních action typů

Cílená kontrola potvrdila, že v datech existují retenční akce používané nebo podobné těm, které mapuje STEP 7.1.

Příklady:

| CODE_CREDIT_ACTION_TYPE | ACTION_CNT |
|---|---:|
| `RE12m_bezP` | 13 085 |
| `RETOKcPop` | 4 257 |
| `RE12m_novy` | 1 377 |
| `RE0KcPopl` | 1 275 |
| `RETCB2%12` | 1 209 |
| `RE20KcPopl` | 738 |
| `RETCB2%_f` | 680 |
| `RETCB2%_12` | 417 |
| `RE0,99%12M` | 247 |
| `Turbo_25_K` | 137 |
| `RE10%K5/16` | 97 |
| `RE10%K1/16` | 73 |
| `RE10%K8/16` | 54 |

Závěr:

```text
Retenční akce v datech existují. Mapování ale obsahuje drobné riziko nekompletního pokrytí některých kódů.
```

---

## Hlavní finding: `RE10%` ve WHERE části

V produkčním kódu je ve `WHERE` části použito:

```sql
ActTp.code_credit_action_type in (..., 'RE10%', ...)
```

V podmínce `IN` se ale hodnota `'RE10%'` nechová jako wildcard. Je vyhodnocena jako přesný text.

Současně výpočet `date_ret_cb` používá:

```sql
ActTp.code_credit_action_type like 'RE10%'
```

To znamená, že kódy jako:

```text
RE10%K5/16
RE10%K1/16
RE10%K8/16
RE10%11/15
```

se nemusí dostat do vstupní množiny, pokud nejsou zachycené jinou částí `WHERE`.

### Doporučení

Ve `WHERE` části nahradit:

```sql
or ActTp.code_credit_action_type in (..., 'RE10%', ...)
```

za explicitní podmínku:

```sql
or ActTp.code_credit_action_type like 'RE10%'
```

Tento nález může způsobovat podhodnocení atributu:

```text
date_ret_cb / ret_cb
```

---

## Další poznámka: podobné názvy retenčních kódů

V datech existují podobné názvy, které nejsou plně totožné s mapovanými kódy.

Příklady:

```text
RETOKcPop
RE0KcPopl

RET20kPopl
RE20KcPopl
```

Bez business potvrzení nelze říct, zda jde o stejný typ retenční akce, historickou variantu názvu, nebo odlišnou akci.

Doporučení:

```text
Provést business review retenčního mapování, hlavně pro podobné historické názvy kódů.
```

---

## Rizika

### 1. Nereprodukovatelnost kvůli `SYSDATE`

STEP 7 používá `SYSDATE` ve více místech:

- výpočet měsíců od poznámky,
- filtr poznámek,
- validita služeb výpisu.

Pro audit a backtest je vhodné používat fixní `AS_OF_DATE`.

---

### 2. Potenciálně nekompletní retenční mapování

Kvůli použití `'RE10%'` v `IN` části může být část `RE10%...` kódů vynechána.

---

### 3. Podobné historické názvy retenčních akcí

Některé kódy jsou podobné, ale ne identické. Je potřeba potvrdit, zda mají být mapované stejně.

---

## Finální závěr

STEP 7 je technicky validní.

Audit potvrdil:

- správný grain pomocné retenční tabulky,
- správný grain finální klientské tabulky,
- žádné duplicity klientů,
- existenci používaných note typů,
- existenci používaných service typů,
- existenci retenčních action typů.

Hlavní technický nález je použití `'RE10%'` v `IN` podmínce, kde nefunguje jako wildcard.

### Status

```text
Technicky validováno.
Doporučena drobná oprava WHERE podmínky pro RE10% retenční kódy.
Business review doporučen pro podobné historické retenční kódy.
```
