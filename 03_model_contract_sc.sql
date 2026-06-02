
---

# Celý auditní SQL kód pro STEP 3

```sql
/* ============================================================================
   STEP 3 AUDIT – HU_model_con_sc
   ----------------------------------------------------------------------------
   Úèel:
   Reprodukovat a zvalidovat logiku kroku 3 bez zápisu do tabulek.

   Produkèní krok plní tabulku HU_model_con_sc historií smluv klientù.
   Tento audit používá fixní AS_OF_DATE místo SYSDATE, aby byl výsledek
   reprodukovatelný.

   Auditní datum:
   DATE '2026-04-01'
   ============================================================================ */


/* ============================================================================
   1) Reprodukce produkèní logiky pøes CTE
   ----------------------------------------------------------------------------
   Cíl:
   - ovìøit poèet výsledných agregaèních bucketù,
   - ovìøit poèet klientù s kontraktovou historií,
   - ovìøit, že suma pocet_cnt odpovídá poètu vstupních kontraktù.

   Poznámka:
   Produkèní kód používá SYSDATE. Tady je SYSDATE nahrazený fixním datem.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

joined_contracts as (
    select
        b.skp_client,
        c.skp_credit_case,
        c.skp_credit_type,
        c.date_decision,

        cs.code_credit_status,

        case 
            when c.skp_credit_type = 2 
                 and g.name_segment_level_2 = 'Cash, X, DM' 
                then 'x-sell'

            when c.skp_credit_type = 3 
                 and g.name_segment_level_2 in ('Credit Card X-sell', 'Revolving Loan X-sell') 
                then 'x-sell'

            else 'akv'
        end as credit_segment,

        cle.code_segmentation_environment,
        cls.code_segmentation_sales_type,
        clp.code_segmentation_proposition,
        clp.code_segmentation_product,
        clo.code_segmentation_other

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

    inner join owner_dwh.f_contract_ad d 
        on c.skp_credit_case = d.skp_credit_case 

    inner join owner_dwh.cl_segmentation_environment cle
        on d.skp_segmentation_environment = cle.skp_segmentation_environment

    inner join owner_dwh.cl_segmentation_sales_type cls
        on d.skp_segmentation_sales_type = cls.skp_segmentation_sales_type

    inner join owner_dwh.cl_segmentation_proposition clp
        on d.skp_segmentation_proposition = clp.skp_segmentation_proposition 

    inner join owner_dwh.cl_segmentation_other clo
        on d.skp_segmentation_other = clo.skp_segmentation_other

    cross join params p

    where p.as_of_date between s.dtime_valid_from and s.dtime_valid_to
      and c.date_decision < p.as_of_date
),

final_sc as (
    select
        skp_client,
        count(*) as pocet_cnt,
        code_credit_status,
        skp_credit_type,
        credit_segment,
        code_segmentation_environment,
        code_segmentation_sales_type,
        code_segmentation_proposition,
        code_segmentation_product,
        code_segmentation_other

    from joined_contracts

    group by
        skp_client,
        code_credit_status,
        skp_credit_type,
        credit_segment,
        code_segmentation_environment,
        code_segmentation_sales_type,
        code_segmentation_proposition,
        code_segmentation_product,
        code_segmentation_other
)

select
    count(*) as final_rows,
    count(distinct skp_client) as clients_with_contract_history,
    sum(pocet_cnt) as total_counted_contract_rows
from final_sc;


/* ============================================================================
   2) Kontrola unikátnosti výsledného grainu ve fyzické tabulce
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, že tabulka HU_model_con_sc nemá duplicity na oèekávaném grainu.

   Oèekávání:
   Dotaz by mìl vrátit 0 øádkù.

   Poznámka:
   Pokud vrátí øádky, mùže to znamenat:
   - tabulka nebyla pøed insertem vyèištìná,
   - stejný krok byl spuštìný vícekrát,
   - nebo grain není takový, jak se oèekává.
   ============================================================================ */

select
    skp_client,
    code_credit_status,
    skp_credit_type,
    credit_segment,
    code_segmentation_environment,
    code_segmentation_sales_type,
    code_segmentation_proposition,
    code_segmentation_product,
    code_segmentation_other,
    count(*) as cnt
from HU_model_con_sc
group by
    skp_client,
    code_credit_status,
    skp_credit_type,
    credit_segment,
    code_segmentation_environment,
    code_segmentation_sales_type,
    code_segmentation_proposition,
    code_segmentation_product,
    code_segmentation_other
having count(*) > 1;


/* ============================================================================
   3) Distribuce poètu øádkù na klienta
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, kolik agregaèních bucketù má jeden klient.

   Dùvod:
   HU_model_con_sc není unikátní podle SKP_CLIENT. Pokud se v dalších krocích
   pøipojí pouze pøes SKP_CLIENT, dojde k násobení klientské báze.
   ============================================================================ */

select
    rows_per_client,
    count(*) as client_cnt
from (
    select
        skp_client,
        count(*) as rows_per_client
    from HU_model_con_sc
    group by skp_client
)
group by rows_per_client
order by rows_per_client;


/* ============================================================================
   4) Souhrnná distribuce poètu øádkù na klienta
   ----------------------------------------------------------------------------
   Cíl:
   Získat kompaktní statistiku distribuce rows_per_client.
   ============================================================================ */

select
    min(rows_per_client) as min_rows_per_client,
    max(rows_per_client) as max_rows_per_client,
    avg(rows_per_client) as avg_rows_per_client,
    percentile_cont(0.50) within group (order by rows_per_client) as p50_rows_per_client,
    percentile_cont(0.90) within group (order by rows_per_client) as p90_rows_per_client,
    percentile_cont(0.99) within group (order by rows_per_client) as p99_rows_per_client
from (
    select
        skp_client,
        count(*) as rows_per_client
    from HU_model_con_sc
    group by skp_client
);


/* ============================================================================
   5) Top klienti podle poètu agregaèních bucketù
   ----------------------------------------------------------------------------
   Cíl:
   Najít outliery s vysokým poètem øádkù v HU_model_con_sc.
   ============================================================================ */

select *
from (
    select
        skp_client,
        count(*) as rows_per_client
    from HU_model_con_sc
    group by skp_client
    order by count(*) desc
)
where rownum <= 20;


/* ============================================================================
   6) Kontrola multiplikace pøes f_contract_ad
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, zda f_contract_ad obsahuje právì jeden øádek na SKP_CREDIT_CASE.

   Riziko:
   Produkèní join je pouze pøes SKP_CREDIT_CASE:

       on c.skp_credit_case = d.skp_credit_case

   Pokud by f_contract_ad mìla více øádkù na jeden credit case,
   došlo by k rozmnožení kontraktù a count(*) by byl nadhodnocený.

   Oèekávání:
   AD_ROWS = 1 pro všechny credit cases.
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

ad_counts as (
    select
        bc.skp_credit_case,
        count(*) as ad_rows
    from base_contracts bc
    inner join owner_dwh.f_contract_ad d
        on bc.skp_credit_case = d.skp_credit_case
    group by bc.skp_credit_case
)

select
    ad_rows,
    count(*) as credit_case_cnt
from ad_counts
group by ad_rows
order by ad_rows;


/* ============================================================================
   7) Kontrola validního statusu ve f_credit_status_tt
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, že každý kontrakt má k AS_OF_DATE právì jeden validní status.

   Riziko:
   Pokud by existovalo více validních statusù pro stejný kontrakt a stejné
   as-of datum, kontrakt by se rozmnožil.

   Oèekávání:
   STATUS_ROWS = 1 pro všechny kontrakty.
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

status_counts as (
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
from status_counts
group by status_rows
order by status_rows;


/* ============================================================================
   8) Kontrola ztráty a multiplikace po jednotlivých joinech
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, zda jednotlivé joiny:
   - nezahazují kontrakty,
   - nerozmnožují kontrakty.

   Interpretace:
   - Pokles CREDIT_CASE_CNT znamená ztrátu kontraktù.
   - Rùst ROW_CNT pøi stejném CREDIT_CASE_CNT znamená multiplikaci øádkù.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

base_contracts as (
    select
        b.skp_client,
        c.skp_credit_case,
        c.skp_credit_type,
        c.date_decision,
        c.skp_credit_segmentation
    from HU_model_basic_sc b
    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client
    cross join params p
    where c.date_decision < p.as_of_date
),

with_status as (
    select bc.*
    from base_contracts bc
    inner join owner_dwh.f_credit_status_tt s
        on bc.skp_credit_case = s.skp_credit_case
       and bc.skp_credit_type = s.skp_credit_type
       and bc.date_decision = s.date_decision
    cross join params p
    where p.as_of_date between s.dtime_valid_from and s.dtime_valid_to
),

with_credit_segmentation as (
    select ws.*
    from with_status ws
    inner join owner_dwh.dc_credit_segmentation g
        on ws.skp_credit_segmentation = g.skp_credit_segmentation
),

with_contract_ad as (
    select wcs.*
    from with_credit_segmentation wcs
    inner join owner_dwh.f_contract_ad d
        on wcs.skp_credit_case = d.skp_credit_case
)

select
    '01_base_contracts' as step_name,
    count(*) as row_cnt,
    count(distinct skp_client) as client_cnt,
    count(distinct skp_credit_case) as credit_case_cnt
from base_contracts

union all

select
    '02_with_status' as step_name,
    count(*) as row_cnt,
    count(distinct skp_client) as client_cnt,
    count(distinct skp_credit_case) as credit_case_cnt
from with_status

union all

select
    '03_with_credit_segmentation' as step_name,
    count(*) as row_cnt,
    count(distinct skp_client) as client_cnt,
    count(distinct skp_credit_case) as credit_case_cnt
from with_credit_segmentation

union all

select
    '04_with_contract_ad' as step_name,
    count(*) as row_cnt,
    count(distinct skp_client) as client_cnt,
    count(distinct skp_credit_case) as credit_case_cnt
from with_contract_ad;


/* ============================================================================
   9) Kontrola detailní distribuce credit_segment
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit, jak se podle aktuální CASE logiky klasifikují segmenty.

   Poznámka:
   V auditním bìhu všechny øádky spadly do akv.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

segmented as (
    select
        c.skp_credit_type,
        g.name_segment_level_2,

        case 
            when c.skp_credit_type = 2 
                 and g.name_segment_level_2 = 'Cash, X, DM' 
                then 'x-sell'

            when c.skp_credit_type = 3 
                 and g.name_segment_level_2 in ('Credit Card X-sell', 'Revolving Loan X-sell') 
                then 'x-sell'

            else 'akv'
        end as credit_segment

    from HU_model_basic_sc b
    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client
    inner join owner_dwh.dc_credit_segmentation g
        on c.skp_credit_segmentation = g.skp_credit_segmentation
    cross join params p
    where c.date_decision < p.as_of_date
)

select
    skp_credit_type,
    name_segment_level_2,
    credit_segment,
    count(*) as row_cnt
from segmented
group by
    skp_credit_type,
    name_segment_level_2,
    credit_segment
order by
    skp_credit_type,
    credit_segment,
    row_cnt desc;


/* ============================================================================
   10) Souhrnná kontrola credit_segment podle typu produktu
   ----------------------------------------------------------------------------
   Cíl:
   Ovìøit poèet øádkù podle SKP_CREDIT_TYPE a CREDIT_SEGMENT.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

segmented as (
    select
        c.skp_credit_type,
        g.name_segment_level_2,

        case 
            when c.skp_credit_type = 2 
                 and g.name_segment_level_2 = 'Cash, X, DM' 
                then 'x-sell'

            when c.skp_credit_type = 3 
                 and g.name_segment_level_2 in ('Credit Card X-sell', 'Revolving Loan X-sell') 
                then 'x-sell'

            else 'akv'
        end as credit_segment

    from HU_model_basic_sc b
    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client
    inner join owner_dwh.dc_credit_segmentation g
        on c.skp_credit_segmentation = g.skp_credit_segmentation
    cross join params p
    where c.date_decision < p.as_of_date
)

select
    skp_credit_type,
    credit_segment,
    count(*) as row_cnt
from segmented
group by
    skp_credit_type,
    credit_segment
order by
    skp_credit_type,
    credit_segment;


/* ============================================================================
   11) Kontrola øádkù klasifikovaných jako x-sell
   ----------------------------------------------------------------------------
   Cíl:
   Vypsat segmenty, které podle aktuální CASE logiky spadnou do x-sell.

   Oèekávání podle auditního bìhu:
   Dotaz vrací 0 øádkù.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

segmented as (
    select
        c.skp_credit_type,
        g.name_segment_level_2,

        case 
            when c.skp_credit_type = 2 
                 and g.name_segment_level_2 = 'Cash, X, DM' 
                then 'x-sell'

            when c.skp_credit_type = 3 
                 and g.name_segment_level_2 in ('Credit Card X-sell', 'Revolving Loan X-sell') 
                then 'x-sell'

            else 'akv'
        end as credit_segment

    from HU_model_basic_sc b
    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client
    inner join owner_dwh.dc_credit_segmentation g
        on c.skp_credit_segmentation = g.skp_credit_segmentation
    cross join params p
    where c.date_decision < p.as_of_date
)

select
    skp_credit_type,
    name_segment_level_2,
    credit_segment,
    count(*) as row_cnt
from segmented
where credit_segment = 'x-sell'
group by
    skp_credit_type,
    name_segment_level_2,
    credit_segment
order by
    skp_credit_type,
    row_cnt desc;


/* ============================================================================
   12) Kontrola skuteèných X / x-sell-like segmentù ve zdrojových datech
   ----------------------------------------------------------------------------
   Cíl:
   Najít segmenty, které názvem vypadají jako X / x-sell / revolving / card,
   ale nejsou zachycené aktuální CASE logikou.

   Dùvod:
   Audit ukázal, že žádný øádek nespadl do x-sell, pøestože data obsahují
   více segmentù s písmenem X nebo podobným významem.
   ============================================================================ */

with params as (
    select date '2026-04-01' as as_of_date
    from dual
),

segmented_source as (
    select
        c.skp_credit_type,
        g.name_segment_level_2,
        count(*) as row_cnt
    from HU_model_basic_sc b
    inner join owner_dwh.dc_contract c
        on b.skp_client = c.skp_client
    inner join owner_dwh.dc_credit_segmentation g
        on c.skp_credit_segmentation = g.skp_credit_segmentation
    cross join params p
    where c.date_decision < p.as_of_date
      and c.skp_credit_type in (2, 3)
    group by
        c.skp_credit_type,
        g.name_segment_level_2
)

select
    skp_credit_type,
    name_segment_level_2,
    row_cnt
from segmented_source
where upper(name_segment_level_2) like '%X%'
   or upper(name_segment_level_2) like '%SELL%'
   or upper(name_segment_level_2) like '%REVOLV%'
   or upper(name_segment_level_2) like '%CREDIT%'
   or upper(name_segment_level_2) like '%CARD%'
order by
    skp_credit_type,
    row_cnt desc;
