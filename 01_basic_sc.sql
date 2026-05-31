/* ============================================================
   STEP 1: HU_model_basic_sc
   Purpose:
   Create base client population for selected month.

   Production logic:
   - source: AP_CRM_MODEL.sdm_person_history
   - filter: month_inserted = trunc(sysdate, 'mm')
   - output grain: 1 row per skp_client

   Audit adjustment:
   - sysdate replaced by fixed as_of_date
   - no insert/truncate, read-only CTE only
   ============================================================ */

with params as (
    select date '2026-04-01' as as_of_date from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    left join AP_CRM_MODEL.hu_model_score_history b
        on h.skp_client = b.skp_client
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select skp_client
    from (
        select
            skp_client,
            row_number() over(order by ora_hash(skp_client), skp_client) as rn
        from basic_full
    )
    where rn <= 1000
)
select
    'FULL' as dataset,
    count(*) as rows_total,
    count(distinct skp_client) as clients_distinct,
    count(*) - count(distinct skp_client) as duplicate_rows,
    min(skp_client) as min_skp_client,
    max(skp_client) as max_skp_client
from basic_full

union all

select
    'SAMPLE' as dataset,
    count(*) as rows_total,
    count(distinct skp_client) as clients_distinct,
    count(*) - count(distinct skp_client) as duplicate_rows,
    min(skp_client) as min_skp_client,
    max(skp_client) as max_skp_client
from basic_sample;





/* Check available monthly snapshots in source table */

select
    h.month_inserted,
    count(*) as rows_total,
    count(distinct h.skp_client) as clients_distinct
from AP_CRM_MODEL.sdm_person_history h
where h.month_inserted >= date '2025-01-01'
group by h.month_inserted
order by h.month_inserted;



/* Check whether LEFT JOIN to score history affects the result */

with params as (
    select date '2026-04-01' as as_of_date from dual
),
without_join as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
with_join as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    left join AP_CRM_MODEL.hu_model_score_history b
        on h.skp_client = b.skp_client
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
)
select
    'IN_WITHOUT_JOIN_NOT_IN_WITH_JOIN' as check_name,
    count(*) as cnt
from without_join w
left join with_join j
    on w.skp_client = j.skp_client
where j.skp_client is null

union all

select
    'IN_WITH_JOIN_NOT_IN_WITHOUT_JOIN' as check_name,
    count(*) as cnt
from with_join j
left join without_join w
    on j.skp_client = w.skp_client
where w.skp_client is null;
