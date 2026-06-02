```sql
/* ============================================================================
   STEP 5 AUDIT – HU_model_last_con_sc
   ----------------------------------------------------------------------------
   Úèel:
   Ovìøit krok 5 procedury, který vybírá poslední smlouvu klienta.

   Produkèní logika:
   - bere klienty z HU_model_basic_sc
   - pøipojuje smlouvy z owner_dwh.dc_contract
   - filtruje statusy a/s:
       a = Aktivní
       s = Schválená smlouva
   - vybírá poslední smlouvu podle DATE_DECISION desc
   - ukládá SKP_CLIENT, CREDIT_CASE_AKV, CREDIT_TYPE_AKV, DADE_AKV

   Hlavní auditní otázky:
   1. Má výstup 1 øádek na klienta?
   2. Kolik klientù má eligible smlouvu ve statusu a/s?
   3. Nechybí filtr validity na f_credit_status_tt?
   4. Existují klienti s více posledními smlouvami ve stejný DATE_DECISION?
   5. Ztrácí se nìco pøes join na dc_credit_segmentation?
   ============================================================================ */


/* ============================================================================
   1) Read-only reprodukce STEP 5 s fixním AS_OF_DATE a validitou statusu
   ----------------------------------------------------------------------------
   Cíl:
   Reprodukovat logiku kroku bez zápisu do tabulky.

   Rozdíl proti produkènímu kódu:
   - místo SYSDATE používáme DATE '2026-04-01'
   - doplòujeme validitu statusu:
       p.as_of_date between s.dtime_valid_from and s.dtime_valid_to
   - doplòujeme deterministický tie-breaker v row_number()
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

eligible_contracts as (
    select
        b.skp_client,
        c.skp_credit_case as credit_case_akv,
        c.skp_credit_type as credit_type_akv,
        c.date_decision as dade_akv,
        cs.code_credit_status,
        g.name_segment_level_1_sales,

        row_number() over (
            partition by b.skp_client
            order by
                c.date_decision desc,
                c.skp_credit_case desc,
                c.skp_credit_type desc
        ) as poradi

    from HU_model_basic_sc b

    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client

    inner join owner_dwh.f_credit_status_tt s
        on c.skp_credit_case = s.skp_credit_case
       and c.skp_credit_type = s.skp_credit_type
       and c.date_decision = s.date_decision

    inner join owner_dwh.cl_credit_status cs
        on s.skp_credit_status = cs.skp_credit_status

    inner join owner_dwh.dc_credit_segmentation g
        on c.skp_credit_segmentation = g.skp_credit_segmentation

    cross join params p

    where p.as_of_date between s.dtime_valid_from and s.dtime_valid_to
      and cs.code_credit_status in ('a', 's')
      and c.date_decision < p.as_of_date
),

final_sc as (
    select
        skp_client,
        credit_case_akv,
        credit_type_akv,
        dade_akv
    from eligible_contracts
    where poradi = 1
)

select
    count(*) as final_rows,
    count(distinct skp_client) as distinct_clients,
    min(dade_akv) as min_dade_akv,
    max(dade_akv) as max_dade_akv
from final_sc;


/* ============================================================================
   2) Kontrola fyzické tabulky HU_model_last_con_sc
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, že výstupní tabulka má 1 øádek na klienta.

   Oèekávání:
   ROW_CNT = DISTINCT_CLIENT_CNT
   ============================================================================ */

select
    count(*) as row_cnt,
    count(distinct skp_client) as distinct_client_cnt
from HU_model_last_con_sc;


/* ============================================================================
   3) Kontrola duplicit klientù ve fyzické tabulce
   ----------------------------------------------------------------------------
   Cíl:
   Najít klienty, kteøí jsou v HU_model_last_con_sc více než jednou.

   Oèekávání:
   Dotaz vrátí 0 øádkù.
   ============================================================================ */

select
    skp_client,
    count(*) as cnt
from HU_model_last_con_sc
group by skp_client
having count(*) > 1;


/* ============================================================================
   4) Poèet eligible smluv a klientù
   ----------------------------------------------------------------------------
   Cíl:
   Zjistit, kolik smluv a klientù vstupuje do výbìru poslední smlouvy.

   Eligible smlouva:
   - status a/s
   - validní status k AS_OF_DATE
   - DATE_DECISION < AS_OF_DATE

   Auditní výsledek:
   - eligible contract rows: 431 288
   - clients with eligible contract: 388 451
   - eligible credit cases: 431 288
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

eligible_contracts as (
    select
        b.skp_client,
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
      and cs.code_credit_status in ('a', 's')
      and c.date_decision < p.as_of_date
)

select
    count(*) as eligible_contract_rows,
    count(distinct skp_client) as clients_with_active_or_approved_contract,
    count(distinct skp_credit_case) as eligible_credit_cases
from eligible_contracts;


/* ============================================================================
   5) Kontrola status mixu eligible smluv
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit rozpad eligible smluv mezi statusy a/s.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

eligible_contracts as (
    select
        b.skp_client,
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
      and cs.code_credit_status in ('a', 's')
      and c.date_decision < p.as_of_date
)

select
    code_credit_status,
    count(*) as row_cnt,
    count(distinct skp_client) as client_cnt,
    count(distinct skp_credit_case) as credit_case_cnt
from eligible_contracts
group by code_credit_status
order by code_credit_status;


/* ============================================================================
   6) Kontrola chybìjící validity ve f_credit_status_tt
   ----------------------------------------------------------------------------
   Cíl:
   Ukázat, co se stane, pokud se f_credit_status_tt joinuje bez validity,
   stejnì jako v produkèním STEP 5.

   Riziko:
   f_credit_status_tt je historizovaná tabulka. Bez validity se pøipojují
   historické verze statusù.

   Auditní nález:
   Vìtšina kontraktù má více než jeden statusový øádek.
   ============================================================================ */

with base_contracts as (
    select
        c.skp_credit_case,
        c.skp_credit_type,
        c.date_decision
    from HU_model_basic_sc b
    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client
    where c.date_decision < date '2026-04-01'
),

status_join_counts as (
    select
        bc.skp_credit_case,
        bc.skp_credit_type,
        bc.date_decision,
        count(*) as status_rows
    from base_contracts bc
    inner join owner_dwh.f_credit_status_tt s
        on bc.skp_credit_case = s.skp_credit_case
       and bc.skp_credit_type = s.skp_credit_type
       and bc.date_decision = s.date_decision
    group by
        bc.skp_credit_case,
        bc.skp_credit_type,
        bc.date_decision
)

select
    status_rows,
    count(*) as contract_cnt
from status_join_counts
group by status_rows
order by status_rows;


/* ============================================================================
   7) Stejná kontrola s validitou statusu
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, že po pøidání valid-time filtru je status join 1:1.

   Oèekávání:
   STATUS_ROWS = 1
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

base_contracts as (
    select
        c.skp_credit_case,
        c.skp_credit_type,
        c.date_decision
    from HU_model_basic_sc b
    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client
    cross join params p
    where c.date_decision < p.as_of_date
),

status_join_counts as (
    select
        bc.skp_credit_case,
        bc.skp_credit_type,
        bc.date_decision,
        count(*) as status_rows
    from base_contracts bc
    inner join owner_dwh.f_credit_status_tt s
        on bc.skp_credit_case = s.skp_credit_case
       and bc.skp_credit_type = s.skp_credit_type
       and bc.date_decision = s.date_decision
    cross join params p
    where p.as_of_date between s.dtime_valid_from and s.dtime_valid_to
    group by
        bc.skp_credit_case,
        bc.skp_credit_type,
        bc.date_decision
)

select
    status_rows,
    count(*) as contract_cnt
from status_join_counts
group by status_rows
order by status_rows;


/* ============================================================================
   8) Kontrola ztráty pøes join na dc_credit_segmentation
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, zda join na dc_credit_segmentation filtruje eligible smlouvy.

   Auditní výsledek:
   01_eligible_status:     431 288 rows / 388 451 clients / 431 288 credit cases
   02_with_segmentation:   431 288 rows / 388 451 clients / 431 288 credit cases

   Závìr:
   Join na segmentaci nic nezahazuje.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

eligible_status as (
    select
        b.skp_client,
        c.skp_credit_case,
        c.skp_credit_type,
        c.date_decision,
        c.skp_credit_segmentation
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
      and cs.code_credit_status in ('a', 's')
      and c.date_decision < p.as_of_date
),

with_segmentation as (
    select es.*
    from eligible_status es
    inner join owner_dwh.dc_credit_segmentation g
        on es.skp_credit_segmentation = g.skp_credit_segmentation
)

select
    '01_eligible_status' as step_name,
    count(*) as row_cnt,
    count(distinct skp_client) as client_cnt,
    count(distinct skp_credit_case) as credit_case_cnt
from eligible_status

union all

select
    '02_with_segmentation' as step_name,
    count(*) as row_cnt,
    count(distinct skp_client) as client_cnt,
    count(distinct skp_credit_case) as credit_case_cnt
from with_segmentation;


/* ============================================================================
   9) Kontrola klientù s více eligible smlouvami ve stejný DATE_DECISION
   ----------------------------------------------------------------------------
   Cíl:
   Najít pøípady, kdy row_number() není deterministický, protože více smluv
   má stejné DATE_DECISION.

   Tento dotaz ukazuje všechny klientské dny s více kontrakty.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

eligible_contracts as (
    select
        b.skp_client,
        c.skp_credit_case,
        c.date_decision
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
      and cs.code_credit_status in ('a', 's')
      and c.date_decision < p.as_of_date
)

select
    skp_client,
    date_decision,
    count(*) as contract_cnt
from eligible_contracts
group by
    skp_client,
    date_decision
having count(*) > 1
order by
    contract_cnt desc,
    skp_client,
    date_decision;


/* ============================================================================
   10) Poèet klientù s více kontrakty na nejnovìjším DATE_DECISION
   ----------------------------------------------------------------------------
   Cíl:
   Zmìøit skuteèný dopad nedeterministického výbìru poslední smlouvy.

   Auditní výsledek:
   AFFECTED_CLIENTS = 284

   Podíl:
   284 / 388 451 = cca 0.073 %
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

eligible_contracts as (
    select
        b.skp_client,
        c.skp_credit_case,
        c.date_decision
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
      and cs.code_credit_status in ('a', 's')
      and c.date_decision < p.as_of_date
),

max_dates as (
    select
        skp_client,
        max(date_decision) as max_date_decision
    from eligible_contracts
    group by skp_client
)

select
    count(*) as affected_clients
from (
    select
        e.skp_client
    from eligible_contracts e
    inner join max_dates m
        on e.skp_client = m.skp_client
       and e.date_decision = m.max_date_decision
    group by e.skp_client
    having count(*) > 1
);


/* ============================================================================
   11) Doporuèená stabilní produkèní logika
   ----------------------------------------------------------------------------
   Poznámka:
   Toto není auditní dotaz, ale návrh bezpeènìjší logiky.

   Rozdíly proti pùvodnímu kódu:
   - pøidán valid-time filtr na f_credit_status_tt
   - pøidán deterministický tie-breaker
   - doporuèeno používat explicitní seznam cílových sloupcù pøi INSERTu
   ============================================================================ */

/*
insert into HU_model_last_con_sc (
    skp_client,
    credit_case_akv,
    credit_type_akv,
    dade_akv
)
select
    skp_client,
    credit_case_akv,
    credit_type_akv,
    dade_akv
from (
    select
        b.skp_client,
        c.skp_credit_case as credit_case_akv,
        c.skp_credit_type as credit_type_akv,
        c.date_decision as dade_akv,

        row_number() over (
            partition by b.skp_client
            order by
                c.date_decision desc,
                c.skp_credit_case desc,
                c.skp_credit_type desc
        ) as poradi

    from HU_model_basic_sc b

    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client

    inner join owner_dwh.f_credit_status_tt s
        on c.skp_credit_case = s.skp_credit_case
       and c.skp_credit_type = s.skp_credit_type
       and c.date_decision = s.date_decision

    inner join owner_dwh.cl_credit_status cs
        on s.skp_credit_status = cs.skp_credit_status

    inner join owner_dwh.dc_credit_segmentation g
        on c.skp_credit_segmentation = g.skp_credit_segmentation

    where sysdate between s.dtime_valid_from and s.dtime_valid_to
      and cs.code_credit_status in ('a', 's')
      and c.date_decision < sysdate
)
where poradi = 1;
*/

