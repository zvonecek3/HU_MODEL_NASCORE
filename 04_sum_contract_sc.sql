```sql
/* ============================================================================
   STEP 4 AUDIT – HU_model_sum_con_sc
   ----------------------------------------------------------------------------
   Úèel:
   Ovìøit krok 4 procedury, který pøevádí kontraktovou historii z tabulky
   HU_model_con_sc do klientského souhrnu HU_model_sum_con_sc.

   Vstup:
   - HU_model_con_sc
     Grain: více øádkù na klienta podle credit type, statusu, credit segmentu
     a dalších segmentaèních atributù.

   Výstup:
   - HU_model_sum_con_sc
     Oèekávaný grain: 1 øádek na SKP_CLIENT.

   Hlavní auditní otázky:
   1. Má výstup opravdu 1 øádek na klienta?
   2. Odpovídá poèet klientù ve STEP 4 poètu klientù ve STEP 3?
   3. Kolik kontraktových poètù ze STEP 3 je pokryto sloupci STEP 4?
   4. Které statusy a credit typy nejsou mapované?
   5. Jsou x-sell sloupce nulové kvùli logice ze STEP 3?
   6. Je cc_loc_rl_poc_a konzistentní s ru_akv_a + ru_x_a?
   ============================================================================ */


/* ============================================================================
   1) Read-only reprodukce STEP 4 pøes CTE
   ----------------------------------------------------------------------------
   Cíl:
   Reprodukovat produkèní insert bez zápisu do HU_model_sum_con_sc.

   Poznámka:
   Tento dotaz ovìøí poèet výsledných øádkù a poèet distinct klientù.
   Oèekávání:
   FINAL_ROWS = DISTINCT_CLIENTS
   ============================================================================ */

with step4_sc as (
    select 
        skp_client,

        /* SKP_CREDIT_TYPE = 1 */
        sum(case when skp_credit_type = 1 and code_credit_status = 'a' then pocet_cnt else 0 end) as su_a,
        sum(case when skp_credit_type = 1 and code_credit_status = 'k' then pocet_cnt else 0 end) as su_k,
        sum(case when skp_credit_type = 1 and code_credit_status = 'z' then pocet_cnt else 0 end) as su_z,
        sum(case when skp_credit_type = 1 and code_credit_status = 'o' then pocet_cnt else 0 end) as su_o,
        sum(case when skp_credit_type = 1 and code_credit_status = 's' then pocet_cnt else 0 end) as su_s,
        sum(case when skp_credit_type = 1 and code_credit_status = 't' then pocet_cnt else 0 end) as su_t,
        sum(case when skp_credit_type = 1 and code_credit_status = 'u' then pocet_cnt else 0 end) as su_u,

        /* SKP_CREDIT_TYPE = 2, akv */
        sum(case when skp_credit_type = 2 and credit_segment = 'akv' and code_credit_status = 'a' then pocet_cnt else 0 end) as hu_akv_a,
        sum(case when skp_credit_type = 2 and credit_segment = 'akv' and code_credit_status = 'k' then pocet_cnt else 0 end) as hu_akv_k,
        sum(case when skp_credit_type = 2 and credit_segment = 'akv' and code_credit_status = 'z' then pocet_cnt else 0 end) as hu_akv_z,
        sum(case when skp_credit_type = 2 and credit_segment = 'akv' and code_credit_status = 'o' then pocet_cnt else 0 end) as hu_akv_o,
        sum(case when skp_credit_type = 2 and credit_segment = 'akv' and code_credit_status = 's' then pocet_cnt else 0 end) as hu_akv_s,
        sum(case when skp_credit_type = 2 and credit_segment = 'akv' and code_credit_status = 't' then pocet_cnt else 0 end) as hu_akv_t,
        sum(case when skp_credit_type = 2 and credit_segment = 'akv' and code_credit_status = 'u' then pocet_cnt else 0 end) as hu_akv_u,

        /* SKP_CREDIT_TYPE = 2, x-sell */
        sum(case when skp_credit_type = 2 and credit_segment = 'x-sell' and code_credit_status = 'a' then pocet_cnt else 0 end) as hu_x_a,
        sum(case when skp_credit_type = 2 and credit_segment = 'x-sell' and code_credit_status = 'k' then pocet_cnt else 0 end) as hu_x_k,
        sum(case when skp_credit_type = 2 and credit_segment = 'x-sell' and code_credit_status = 'z' then pocet_cnt else 0 end) as hu_x_z,
        sum(case when skp_credit_type = 2 and credit_segment = 'x-sell' and code_credit_status = 'o' then pocet_cnt else 0 end) as hu_x_o,
        sum(case when skp_credit_type = 2 and credit_segment = 'x-sell' and code_credit_status = 's' then pocet_cnt else 0 end) as hu_x_s,
        sum(case when skp_credit_type = 2 and credit_segment = 'x-sell' and code_credit_status = 't' then pocet_cnt else 0 end) as hu_x_t,
        sum(case when skp_credit_type = 2 and credit_segment = 'x-sell' and code_credit_status = 'u' then pocet_cnt else 0 end) as hu_x_u,

        /* SKP_CREDIT_TYPE = 3, akv */
        sum(case when skp_credit_type = 3 and credit_segment = 'akv' and code_credit_status = 'a' then pocet_cnt else 0 end) as ru_akv_a,
        sum(case when skp_credit_type = 3 and credit_segment = 'akv' and code_credit_status = 'k' then pocet_cnt else 0 end) as ru_akv_k,
        sum(case when skp_credit_type = 3 and credit_segment = 'akv' and code_credit_status = 'z' then pocet_cnt else 0 end) as ru_akv_z,
        sum(case when skp_credit_type = 3 and credit_segment = 'akv' and code_credit_status = 'o' then pocet_cnt else 0 end) as ru_akv_o,
        sum(case when skp_credit_type = 3 and credit_segment = 'akv' and code_credit_status = 's' then pocet_cnt else 0 end) as ru_akv_s,
        sum(case when skp_credit_type = 3 and credit_segment = 'akv' and code_credit_status = 't' then pocet_cnt else 0 end) as ru_akv_t,
        sum(case when skp_credit_type = 3 and credit_segment = 'akv' and code_credit_status = 'u' then pocet_cnt else 0 end) as ru_akv_u,

        /* SKP_CREDIT_TYPE = 3, x-sell */
        sum(case when skp_credit_type = 3 and credit_segment = 'x-sell' and code_credit_status = 'a' then pocet_cnt else 0 end) as ru_x_a,
        sum(case when skp_credit_type = 3 and credit_segment = 'x-sell' and code_credit_status = 'k' then pocet_cnt else 0 end) as ru_x_k,
        sum(case when skp_credit_type = 3 and credit_segment = 'x-sell' and code_credit_status = 'z' then pocet_cnt else 0 end) as ru_x_z,
        sum(case when skp_credit_type = 3 and credit_segment = 'x-sell' and code_credit_status = 'o' then pocet_cnt else 0 end) as ru_x_o,
        sum(case when skp_credit_type = 3 and credit_segment = 'x-sell' and code_credit_status = 's' then pocet_cnt else 0 end) as ru_x_s,
        sum(case when skp_credit_type = 3 and credit_segment = 'x-sell' and code_credit_status = 't' then pocet_cnt else 0 end) as ru_x_t,
        sum(case when skp_credit_type = 3 and credit_segment = 'x-sell' and code_credit_status = 'u' then pocet_cnt else 0 end) as ru_x_u,

        /* Pøekryvný souhrnný sloupec pro aktivní SKP_CREDIT_TYPE = 3 */
        sum(case when skp_credit_type = 3 and code_credit_status = 'a' then pocet_cnt else 0 end) as cc_loc_rl_poc_a

    from HU_model_con_sc
    group by skp_client
)

select
    count(*) as final_rows,
    count(distinct skp_client) as distinct_clients
from step4_sc;


/* ============================================================================
   2) Kontrola fyzické tabulky HU_model_sum_con_sc
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, že fyzická výstupní tabulka má 1 øádek na klienta.

   Oèekávání:
   ROW_CNT = DISTINCT_CLIENT_CNT
   ============================================================================ */

select
    count(*) as row_cnt,
    count(distinct skp_client) as distinct_client_cnt
from HU_model_sum_con_sc;


/* ============================================================================
   3) Kontrola duplicit klientù ve fyzické tabulce
   ----------------------------------------------------------------------------
   Cíl:
   Najít klienty, kteøí jsou v HU_model_sum_con_sc více než jednou.

   Oèekávání:
   Dotaz vrátí 0 øádkù.
   ============================================================================ */

select
    skp_client,
    count(*) as cnt
from HU_model_sum_con_sc
group by skp_client
having count(*) > 1;


/* ============================================================================
   4) Kontrola poètu klientù proti STEP 3
   ----------------------------------------------------------------------------
   Cíl:
   STEP 4 dìlá group by SKP_CLIENT nad HU_model_con_sc.
   Poèet øádkù ve STEP 4 má tedy odpovídat poètu distinct klientù ve STEP 3.
   ============================================================================ */

select
    (select count(distinct skp_client) from HU_model_con_sc) as clients_in_step3,
    (select count(*) from HU_model_sum_con_sc) as rows_in_step4
from dual;


/* ============================================================================
   5) Kontrola celkového pokrytí podle pøesné logiky STEP 4
   ----------------------------------------------------------------------------
   Cíl:
   Zjistit, kolik kontraktových poètù ze STEP 3 je pokryto výstupními sloupci
   ve STEP 4 a kolik jich není namapováno vùbec.

   Dùležité:
   Tento dotaz kontroluje pøesné podmínky použité ve STEP 4:
   - credit type 1 se statusy a,k,z,o,s,t,u
   - credit type 2 se segmentem akv/x-sell a statusy a,k,z,o,s,t,u
   - credit type 3 se segmentem akv/x-sell a statusy a,k,z,o,s,t,u

   V auditním bìhu:
   STEP3_TOTAL_ALL = 3 874 708
   STEP4_COVERED_BY_DEFINED_COLUMNS = 3 519 626
   STEP4_NOT_COVERED_BY_DEFINED_COLUMNS = 355 082
   ============================================================================ */

select
    sum(pocet_cnt) as step3_total_all,

    sum(case
            when skp_credit_type = 1
             and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
            then pocet_cnt

            when skp_credit_type = 2
             and credit_segment in ('akv', 'x-sell')
             and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
            then pocet_cnt

            when skp_credit_type = 3
             and credit_segment in ('akv', 'x-sell')
             and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
            then pocet_cnt

            else 0
        end) as step4_covered_by_defined_columns,

    sum(case
            when skp_credit_type = 1
             and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
            then 0

            when skp_credit_type = 2
             and credit_segment in ('akv', 'x-sell')
             and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
            then 0

            when skp_credit_type = 3
             and credit_segment in ('akv', 'x-sell')
             and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
            then 0

            else pocet_cnt
        end) as step4_not_covered_by_defined_columns

from HU_model_con_sc;


/* ============================================================================
   6) Distribuce všech statusù ve STEP 3
   ----------------------------------------------------------------------------
   Cíl:
   Zjistit, jaké CODE_CREDIT_STATUS existují ve vstupní tabulce HU_model_con_sc.

   Poznámka:
   STEP 4 mapuje pouze statusy:
   a, k, z, o, s, t, u

   V datech byly nalezeny také:
   d, h, l, y
   ============================================================================ */

select
    code_credit_status,
    sum(pocet_cnt) as contract_cnt
from HU_model_con_sc
group by code_credit_status
order by code_credit_status;


/* ============================================================================
   7) Nepokryté statusy podle STEP 4
   ----------------------------------------------------------------------------
   Cíl:
   Najít statusy, které existují ve STEP 3, ale nejsou mapované ve STEP 4.

   Oèekávaný nález:
   d, h, l, y
   ============================================================================ */

select
    code_credit_status,
    sum(pocet_cnt) as contract_cnt
from HU_model_con_sc
where code_credit_status not in ('a', 'k', 'z', 'o', 's', 't', 'u')
group by code_credit_status
order by code_credit_status;


/* ============================================================================
   8) Význam statusù z èíselníku
   ----------------------------------------------------------------------------
   Cíl:
   Dohledat business význam statusù.

   Nález:
   d = Odmítnutý návrh
   h = Odepsaná pohledávka
   l = Zesplatnìná
   y = Vypovìzená
   ============================================================================ */

select
    skp_credit_status,
    code_credit_status,
    name_credit_status,
    text_credit_status
from owner_dwh.cl_credit_status
where code_credit_status in ('a', 'd', 'h', 'k', 'l', 'o', 's', 't', 'u', 'y', 'z')
order by code_credit_status;


/* ============================================================================
   9) Dopad nepokrytých statusù podle poètu klientù
   ----------------------------------------------------------------------------
   Cíl:
   Zjistit, kolika klientù se týkají statusy, které STEP 4 nepokrývá.

   Auditní výsledek:
   d: 7 klientù / 7 kontraktù
   h: 211 733 klientù / 285 475 kontraktù
   l: 40 628 klientù / 53 513 kontraktù
   y: 739 klientù / 803 kontraktù
   ============================================================================ */

select
    code_credit_status,
    count(distinct skp_client) as client_cnt,
    sum(pocet_cnt) as contract_cnt
from HU_model_con_sc
where code_credit_status in ('d', 'h', 'l', 'y')
group by code_credit_status
order by code_credit_status;


/* ============================================================================
   10) Nepokryté statusy podle typu produktu
   ----------------------------------------------------------------------------
   Cíl:
   Zjistit, u kterých SKP_CREDIT_TYPE se nepokryté statusy vyskytují.

   Tento výstup pomáhá urèit, zda problém dopadá na SU/HU/RU èást feature setu.
   ============================================================================ */

select
    skp_credit_type,
    code_credit_status,
    sum(pocet_cnt) as contract_cnt
from HU_model_con_sc
where code_credit_status in ('d', 'h', 'l', 'y')
group by
    skp_credit_type,
    code_credit_status
order by
    skp_credit_type,
    code_credit_status;


/* ============================================================================
   11) Pøesný seznam kombinací, které nejsou pokryté STEP 4
   ----------------------------------------------------------------------------
   Cíl:
   Najít kombinace SKP_CREDIT_TYPE, CREDIT_SEGMENT a CODE_CREDIT_STATUS,
   které se nedostanou do žádného výstupního sloupce ve STEP 4.

   Nález:
   - nepokryté statusy d, h, l, y
   - nepokryté credit typy 6 a 7
   ============================================================================ */

select
    skp_credit_type,
    credit_segment,
    code_credit_status,
    sum(pocet_cnt) as contract_cnt
from HU_model_con_sc
where not (
       skp_credit_type = 1 
       and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
)
and not (
       skp_credit_type = 2 
       and credit_segment in ('akv', 'x-sell')
       and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
)
and not (
       skp_credit_type = 3 
       and credit_segment in ('akv', 'x-sell')
       and code_credit_status in ('a', 'k', 'z', 'o', 's', 't', 'u')
)
group by
    skp_credit_type,
    credit_segment,
    code_credit_status
order by
    skp_credit_type,
    credit_segment,
    code_credit_status;


/* ============================================================================
   12) Kontrola statusu o = Odeslaný návrh
   ----------------------------------------------------------------------------
   Cíl:
   STEP 4 obsahuje sloupce pro status o, ale v aktuální populaci nebyl nalezen.

   Oèekávání podle auditu:
   Dotaz vrací 0 øádkù.
   ============================================================================ */

select
    code_credit_status,
    sum(pocet_cnt) as contract_cnt
from HU_model_con_sc
where code_credit_status = 'o'
group by code_credit_status;


/* ============================================================================
   13) Historické rozložení nepokrytých statusù podle roku rozhodnutí
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, jestli jsou nepokryté statusy pouze historické, nebo se vyskytují
   i v novìjších letech.

   Poznámka:
   HU_model_con_sc nemusí obsahovat DATE_DECISION, proto se tato kontrola
   dìlá pøes zdrojovou logiku ze STEP 3.

   Hlavní nález:
   - d je marginální a historický
   - h je hlavnì historický, ale objemovì velký
   - l je aktuální a významný i v posledních letech
   - y je menší, ale stále aktuální
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

contract_status as (
    select
        c.skp_credit_case,
        c.skp_credit_type,
        c.date_decision,
        cs.code_credit_status
    from HU_model_basic_sc b
    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client
    inner join owner_dwh.f_credit_status_tt s
        on c.skp_credit_case = s.skp_credit_case
       and c.skp_credit_type = s.skp_credit_type
       and c.date_decision = s.date_decision
    inner join owner_dwh.cl_credit_status cs
        on s.skp_credit_status = cs.skp_credit_status
    cross join params p
    where p.as_of_date between s.dtime_valid_from and s.dtime_valid_to
      and c.date_decision < p.as_of_date
)

select
    code_credit_status,
    extract(year from date_decision) as decision_year,
    count(*) as contract_cnt
from contract_status
where code_credit_status in ('d', 'h', 'l', 'y')
group by
    code_credit_status,
    extract(year from date_decision)
order by
    code_credit_status,
    decision_year;


/* ============================================================================
   14) Kontrola sum po STEP 4 bez dvojího zapoèítání cc_loc_rl_poc_a
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit celkovou sumu hodnot v hlavních output featurách.

   Dùležité:
   cc_loc_rl_poc_a je pøekryvný sloupec vùèi ru_akv_a + ru_x_a,
   proto se do covered_contract_cnt níže nezapoèítává.
   ============================================================================ */

select
    sum(
        su_a + su_k + su_z + su_o + su_s + su_t + su_u
      + hu_akv_a + hu_akv_k + hu_akv_z + hu_akv_o + hu_akv_s + hu_akv_t + hu_akv_u
      + hu_x_a + hu_x_k + hu_x_z + hu_x_o + hu_x_s + hu_x_t + hu_x_u
      + ru_akv_a + ru_akv_k + ru_akv_z + ru_akv_o + ru_akv_s + ru_akv_t + ru_akv_u
      + ru_x_a + ru_x_k + ru_x_z + ru_x_o + ru_x_s + ru_x_t + ru_x_u
    ) as covered_contract_cnt,

    sum(cc_loc_rl_poc_a) as cc_loc_rl_poc_a_cnt

from HU_model_sum_con_sc;


/* ============================================================================
   15) Kontrola konzistence cc_loc_rl_poc_a
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, že:
   cc_loc_rl_poc_a = ru_akv_a + ru_x_a

   V aktuálním bìhu se oèekává:
   cc_loc_rl_poc_a = ru_akv_a
   protože x-sell segmenty nevznikly ve STEP 3.
   ============================================================================ */

select
    sum(cc_loc_rl_poc_a) as cc_loc_rl_poc_a,
    sum(ru_akv_a + ru_x_a) as ru_total_a,
    sum(cc_loc_rl_poc_a - (ru_akv_a + ru_x_a)) as diff
from HU_model_sum_con_sc;


/* ============================================================================
   16) Kontrola x-sell sloupcù
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, zda jsou x-sell sloupce nulové.

   Oèekávání podle STEP 3:
   x_sell_contract_cnt = 0

   Dùvod:
   STEP 3 podle aktuální credit_segment CASE logiky nevytvoøil žádné
   credit_segment = 'x-sell' øádky.
   ============================================================================ */

select
    sum(
        hu_x_a + hu_x_k + hu_x_z + hu_x_o + hu_x_s + hu_x_t + hu_x_u
      + ru_x_a + ru_x_k + ru_x_z + ru_x_o + ru_x_s + ru_x_t + ru_x_u
    ) as x_sell_contract_cnt
from HU_model_sum_con_sc;
```
