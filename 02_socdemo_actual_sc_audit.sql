/* =====================================================================
   STEP 2 AUDIT: hu_socdemo_actual_sc
   =====================================================================

   Purpose:
   - Reproduce STEP 2 logic from procedure HU_model_nascore.
   - Test grain, client loss, nulls, distributions and row multiplication.
   - Keep everything read-only.

   Important:
   - No insert.
   - No truncate.
   - No commit.
   - No modification of production tables/procedures.

   Default test setup:
   - AS_OF_DATE  = date '2026-04-01'
   - SAMPLE_SIZE = 5000

   Notes:
   - For quick null-profile comparable with earlier run, set SAMPLE_SIZE = 1000.
   - For multiplication analysis, keep SAMPLE_SIZE = 5000.
   - The original production logic uses sysdate.
   - This audit version replaces sysdate with AS_OF_DATE for repeatability.
   - The row_number ordering intentionally copies the production logic:
       order by a.date_decision desc
     No tie-breaker is added here, because this file audits the current logic.
   ===================================================================== */


/* =====================================================================
   01 - FINAL OUTPUT CHECK
   Grain, rowcount, coverage.
   Expected final grain: 1 row per client after poradi_app = 1.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
socdemo_pre as (
    select distinct
        b.skp_client,
        c.code_gender,
        c.num_client_current_age,
        c.flag_aml_client,
        d.name_education_type,
        d.name_family_status,
        d.name_housing_type,
        d.name_income_type,
        d.name_nationality,

        a.amt_income,
        nvl(a.amt_income, 0) + nvl(a.amt_income_partner, 0) as amt_income_total,
        nvl(a.cnt_children, 0) as cnt_children,

        case when e.skp_client is not null then 1 else 0 end as flag_eclient,

        ad.name_street,
        ad.text_street_number,
        ad.name_town,
        g.name_municipality,

        em.name_employer,
        months_between(p.as_of_date, em.date_employment_from) as date_employment_from,
        months_between(em.date_employment_to, p.as_of_date) as date_employment_to,

        case when pp.text_best_email_contact is not null then 1 else 0 end as flag_mail,
        case when pp.text_best_phone_contact is not null then 1 else 0 end as flag_phone,
        case when pp.code_phone_contact_validity in (2, 3) then 1 else 0 end as flag_phone_verified,

        case
            when c.date_rejection_last < p.as_of_date
            then months_between(p.as_of_date, c.date_rejection_last)
            else null
        end as months_last_rejection,

        row_number() over(
            partition by c.skp_client
            order by a.date_decision desc
        ) as poradi_app

    from owner_dwh.dc_client c
    join basic_sample b
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    cross join params p

    left join owner_dwh.f_application_detail_tt a
        on c.skp_client = a.skp_client
       and a.flag_last_appl_on_credit = 'Y'
       and a.date_decision < p.as_of_date

    left join owner_dwh.dc_eclient_account e
        on c.skp_client = e.skp_client
       and e.dtime_inserted < p.as_of_date

    left join (
        select
            ad.skp_client,
            ha.name_street,
            ha.text_street_number,
            ha.name_town,
            ha.code_zip,
            row_number() over(
                partition by ad.skp_client
                order by ha.dtime_source_modified desc, ha.id_source desc
            ) as rn
        from basic_sample bs
        join owner_dwh.f_client_address_tt ad
            on bs.skp_client = ad.skp_client
        join owner_dwh.dh_address ha
            on ad.skp_address = ha.skp_address
           and ad.code_object_type = ha.code_object_type
        where ad.code_address_status = 'a'
          and ad.flag_address_reporting = 'Y'
          and ad.flag_address_current = 'Y'
          and ad.flag_deleted = 'N'
          and ha.flag_deleted = 'N'
    ) ad
        on b.skp_client = ad.skp_client
       and ad.rn = 1

    left join dm_campaign.cl_cmp_geography g
        on replace(ad.code_zip, ' ', '') = replace(g.code_zip, ' ', '')

    left join owner_dwh.f_client_employer_tt em
        on c.skp_client = em.skp_client
       and em.code_status = 'a'
       and em.date_employment_from < p.as_of_date

    left join dm_campaign.f_person_ad pp
        on c.skp_client = pp.skp_client

    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
socdemo_result as (
    select
        skp_client,
        code_gender,
        num_client_current_age,
        flag_aml_client,
        name_education_type,
        name_family_status,
        name_housing_type,
        name_income_type,
        name_nationality,
        amt_income,
        amt_income_total,
        cnt_children,
        flag_eclient,
        name_street,
        text_street_number,
        name_town,
        name_municipality,
        name_employer,
        date_employment_from,
        date_employment_to,
        flag_mail,
        flag_phone,
        flag_phone_verified,
        months_last_rejection
    from socdemo_pre
    where poradi_app = 1
)
select
    (select as_of_date from params) as as_of_date,
    (select sample_size from params) as sample_size,
    (select count(*) from basic_sample) as input_clients,
    count(*) as rows_total,
    count(distinct skp_client) as clients_distinct,
    count(*) - count(distinct skp_client) as duplicate_rows,
    round(
        100 * count(distinct skp_client) / nullif((select count(*) from basic_sample), 0),
        2
    ) as coverage_pct
from socdemo_result;


/* =====================================================================
   02 - DROP ACCOUNTING
   Explains why clients disappear between basic_sample and STEP 2 output.
   Main known reason: c.name_first like '%*%'.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
)
select
    case
        when c.skp_client is null then 'MISSING_IN_DC_CLIENT'
        when c.skp_client = -1 then 'SKP_CLIENT_MINUS_1'
        when c.skp_client_demography is null then 'MISSING_SKP_CLIENT_DEMOGRAPHY'
        when d.skp_client_demography is null then 'MISSING_IN_DC_CLIENT_DEMOGRAPHY'
        when c.name_first is null then 'NAME_FIRST_NULL'
        when c.name_first like '%*%' then 'NAME_FIRST_CONTAINS_STAR'
        else 'OTHER'
    end as drop_reason,
    count(*) as clients_count
from basic_sample b
left join owner_dwh.dc_client c
    on b.skp_client = c.skp_client
left join owner_dwh.dc_client_demography d
    on c.skp_client_demography = d.skp_client_demography
where c.skp_client is null
   or c.skp_client = -1
   or c.skp_client_demography is null
   or d.skp_client_demography is null
   or c.name_first is null
   or c.name_first like '%*%'
group by
    case
        when c.skp_client is null then 'MISSING_IN_DC_CLIENT'
        when c.skp_client = -1 then 'SKP_CLIENT_MINUS_1'
        when c.skp_client_demography is null then 'MISSING_SKP_CLIENT_DEMOGRAPHY'
        when d.skp_client_demography is null then 'MISSING_IN_DC_CLIENT_DEMOGRAPHY'
        when c.name_first is null then 'NAME_FIRST_NULL'
        when c.name_first like '%*%' then 'NAME_FIRST_CONTAINS_STAR'
        else 'OTHER'
    end
order by clients_count desc;


/* =====================================================================
   03 - NULL PROFILE
   Checks null counts and null percentages in final STEP 2 output.
   For comparison with original notes, use SAMPLE_SIZE = 1000.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
socdemo_pre as (
    select distinct
        b.skp_client,
        c.code_gender,
        c.num_client_current_age,
        c.flag_aml_client,
        d.name_education_type,
        d.name_family_status,
        d.name_housing_type,
        d.name_income_type,
        d.name_nationality,
        a.amt_income,
        nvl(a.amt_income, 0) + nvl(a.amt_income_partner, 0) as amt_income_total,
        nvl(a.cnt_children, 0) as cnt_children,
        case when e.skp_client is not null then 1 else 0 end as flag_eclient,
        ad.name_street,
        ad.text_street_number,
        ad.name_town,
        g.name_municipality,
        em.name_employer,
        months_between(p.as_of_date, em.date_employment_from) as date_employment_from,
        months_between(em.date_employment_to, p.as_of_date) as date_employment_to,
        case when pp.text_best_email_contact is not null then 1 else 0 end as flag_mail,
        case when pp.text_best_phone_contact is not null then 1 else 0 end as flag_phone,
        case when pp.code_phone_contact_validity in (2, 3) then 1 else 0 end as flag_phone_verified,
        case
            when c.date_rejection_last < p.as_of_date
            then months_between(p.as_of_date, c.date_rejection_last)
            else null
        end as months_last_rejection,
        row_number() over(
            partition by c.skp_client
            order by a.date_decision desc
        ) as poradi_app
    from owner_dwh.dc_client c
    join basic_sample b
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    cross join params p
    left join owner_dwh.f_application_detail_tt a
        on c.skp_client = a.skp_client
       and a.flag_last_appl_on_credit = 'Y'
       and a.date_decision < p.as_of_date
    left join owner_dwh.dc_eclient_account e
        on c.skp_client = e.skp_client
       and e.dtime_inserted < p.as_of_date
    left join (
        select
            ad.skp_client,
            ha.name_street,
            ha.text_street_number,
            ha.name_town,
            ha.code_zip,
            row_number() over(
                partition by ad.skp_client
                order by ha.dtime_source_modified desc, ha.id_source desc
            ) as rn
        from basic_sample bs
        join owner_dwh.f_client_address_tt ad
            on bs.skp_client = ad.skp_client
        join owner_dwh.dh_address ha
            on ad.skp_address = ha.skp_address
           and ad.code_object_type = ha.code_object_type
        where ad.code_address_status = 'a'
          and ad.flag_address_reporting = 'Y'
          and ad.flag_address_current = 'Y'
          and ad.flag_deleted = 'N'
          and ha.flag_deleted = 'N'
    ) ad
        on b.skp_client = ad.skp_client
       and ad.rn = 1
    left join dm_campaign.cl_cmp_geography g
        on replace(ad.code_zip, ' ', '') = replace(g.code_zip, ' ', '')
    left join owner_dwh.f_client_employer_tt em
        on c.skp_client = em.skp_client
       and em.code_status = 'a'
       and em.date_employment_from < p.as_of_date
    left join dm_campaign.f_person_ad pp
        on c.skp_client = pp.skp_client
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
socdemo_result as (
    select *
    from socdemo_pre
    where poradi_app = 1
)
select
    column_name,
    null_count,
    round(100 * null_count / nullif(total_rows, 0), 2) as null_pct,
    total_rows
from (
    select 'code_gender' as column_name, sum(case when code_gender is null then 1 else 0 end) as null_count, count(*) as total_rows from socdemo_result
    union all select 'num_client_current_age', sum(case when num_client_current_age is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'flag_aml_client', sum(case when flag_aml_client is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_education_type', sum(case when name_education_type is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_family_status', sum(case when name_family_status is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_housing_type', sum(case when name_housing_type is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_income_type', sum(case when name_income_type is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_nationality', sum(case when name_nationality is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'amt_income', sum(case when amt_income is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'amt_income_total', sum(case when amt_income_total is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'cnt_children', sum(case when cnt_children is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'flag_eclient', sum(case when flag_eclient is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_street', sum(case when name_street is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'text_street_number', sum(case when text_street_number is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_town', sum(case when name_town is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_municipality', sum(case when name_municipality is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'name_employer', sum(case when name_employer is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'date_employment_from', sum(case when date_employment_from is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'date_employment_to', sum(case when date_employment_to is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'flag_mail', sum(case when flag_mail is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'flag_phone', sum(case when flag_phone is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'flag_phone_verified', sum(case when flag_phone_verified is null then 1 else 0 end), count(*) from socdemo_result
    union all select 'months_last_rejection', sum(case when months_last_rejection is null then 1 else 0 end), count(*) from socdemo_result
)
order by null_pct desc, column_name;


/* =====================================================================
   04 - CATEGORICAL DISTRIBUTIONS
   Checks distribution of key categorical attributes and flags.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
socdemo_pre as (
    select distinct
        b.skp_client,
        c.code_gender,
        c.flag_aml_client,
        d.name_education_type,
        d.name_family_status,
        d.name_housing_type,
        d.name_income_type,
        d.name_nationality,
        case when e.skp_client is not null then 1 else 0 end as flag_eclient,
        g.name_municipality,
        em.name_employer,
        case when pp.text_best_email_contact is not null then 1 else 0 end as flag_mail,
        case when pp.text_best_phone_contact is not null then 1 else 0 end as flag_phone,
        case when pp.code_phone_contact_validity in (2, 3) then 1 else 0 end as flag_phone_verified,
        row_number() over(
            partition by c.skp_client
            order by a.date_decision desc
        ) as poradi_app
    from owner_dwh.dc_client c
    join basic_sample b
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    cross join params p
    left join owner_dwh.f_application_detail_tt a
        on c.skp_client = a.skp_client
       and a.flag_last_appl_on_credit = 'Y'
       and a.date_decision < p.as_of_date
    left join owner_dwh.dc_eclient_account e
        on c.skp_client = e.skp_client
       and e.dtime_inserted < p.as_of_date
    left join (
        select
            ad.skp_client,
            ha.code_zip,
            row_number() over(
                partition by ad.skp_client
                order by ha.dtime_source_modified desc, ha.id_source desc
            ) as rn
        from basic_sample bs
        join owner_dwh.f_client_address_tt ad
            on bs.skp_client = ad.skp_client
        join owner_dwh.dh_address ha
            on ad.skp_address = ha.skp_address
           and ad.code_object_type = ha.code_object_type
        where ad.code_address_status = 'a'
          and ad.flag_address_reporting = 'Y'
          and ad.flag_address_current = 'Y'
          and ad.flag_deleted = 'N'
          and ha.flag_deleted = 'N'
    ) ad
        on b.skp_client = ad.skp_client
       and ad.rn = 1
    left join dm_campaign.cl_cmp_geography g
        on replace(ad.code_zip, ' ', '') = replace(g.code_zip, ' ', '')
    left join owner_dwh.f_client_employer_tt em
        on c.skp_client = em.skp_client
       and em.code_status = 'a'
       and em.date_employment_from < p.as_of_date
    left join dm_campaign.f_person_ad pp
        on c.skp_client = pp.skp_client
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
socdemo_result as (
    select *
    from socdemo_pre
    where poradi_app = 1
)
select
    column_name,
    value,
    cnt,
    round(100 * cnt / sum(cnt) over(partition by column_name), 2) as pct
from (
    select 'code_gender' as column_name, nvl(to_char(code_gender), '<NULL>') as value, count(*) as cnt
    from socdemo_result
    group by nvl(to_char(code_gender), '<NULL>')

    union all
    select 'flag_aml_client', nvl(to_char(flag_aml_client), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(flag_aml_client), '<NULL>')

    union all
    select 'name_education_type', nvl(to_char(name_education_type), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(name_education_type), '<NULL>')

    union all
    select 'name_family_status', nvl(to_char(name_family_status), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(name_family_status), '<NULL>')

    union all
    select 'name_housing_type', nvl(to_char(name_housing_type), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(name_housing_type), '<NULL>')

    union all
    select 'name_income_type', nvl(to_char(name_income_type), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(name_income_type), '<NULL>')

    union all
    select 'name_nationality', nvl(to_char(name_nationality), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(name_nationality), '<NULL>')

    union all
    select 'flag_eclient', nvl(to_char(flag_eclient), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(flag_eclient), '<NULL>')

    union all
    select 'flag_mail', nvl(to_char(flag_mail), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(flag_mail), '<NULL>')

    union all
    select 'flag_phone', nvl(to_char(flag_phone), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(flag_phone), '<NULL>')

    union all
    select 'flag_phone_verified', nvl(to_char(flag_phone_verified), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(flag_phone_verified), '<NULL>')

    union all
    select 'name_municipality', nvl(to_char(name_municipality), '<NULL>'), count(*)
    from socdemo_result
    group by nvl(to_char(name_municipality), '<NULL>')
)
order by column_name, cnt desc;


/* =====================================================================
   05 - NUMERIC SANITY CHECKS
   Checks min, percentiles and max of important numeric attributes.
   Watch for impossible ages, negative income, extreme values, etc.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
socdemo_pre as (
    select distinct
        b.skp_client,
        c.num_client_current_age,
        a.amt_income,
        nvl(a.amt_income, 0) + nvl(a.amt_income_partner, 0) as amt_income_total,
        nvl(a.cnt_children, 0) as cnt_children,
        months_between(p.as_of_date, em.date_employment_from) as date_employment_from,
        months_between(em.date_employment_to, p.as_of_date) as date_employment_to,
        case
            when c.date_rejection_last < p.as_of_date
            then months_between(p.as_of_date, c.date_rejection_last)
            else null
        end as months_last_rejection,
        row_number() over(
            partition by c.skp_client
            order by a.date_decision desc
        ) as poradi_app
    from owner_dwh.dc_client c
    join basic_sample b
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    cross join params p
    left join owner_dwh.f_application_detail_tt a
        on c.skp_client = a.skp_client
       and a.flag_last_appl_on_credit = 'Y'
       and a.date_decision < p.as_of_date
    left join owner_dwh.f_client_employer_tt em
        on c.skp_client = em.skp_client
       and em.code_status = 'a'
       and em.date_employment_from < p.as_of_date
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
socdemo_result as (
    select *
    from socdemo_pre
    where poradi_app = 1
)
select
    metric_name,
    min_value,
    p01_value,
    median_value,
    p99_value,
    max_value
from (
    select
        'num_client_current_age' as metric_name,
        min(num_client_current_age) as min_value,
        percentile_cont(0.01) within group(order by num_client_current_age) as p01_value,
        percentile_cont(0.50) within group(order by num_client_current_age) as median_value,
        percentile_cont(0.99) within group(order by num_client_current_age) as p99_value,
        max(num_client_current_age) as max_value
    from socdemo_result
    where num_client_current_age is not null

    union all

    select
        'amt_income',
        min(amt_income),
        percentile_cont(0.01) within group(order by amt_income),
        percentile_cont(0.50) within group(order by amt_income),
        percentile_cont(0.99) within group(order by amt_income),
        max(amt_income)
    from socdemo_result
    where amt_income is not null

    union all

    select
        'amt_income_total',
        min(amt_income_total),
        percentile_cont(0.01) within group(order by amt_income_total),
        percentile_cont(0.50) within group(order by amt_income_total),
        percentile_cont(0.99) within group(order by amt_income_total),
        max(amt_income_total)
    from socdemo_result
    where amt_income_total is not null

    union all

    select
        'cnt_children',
        min(cnt_children),
        percentile_cont(0.01) within group(order by cnt_children),
        percentile_cont(0.50) within group(order by cnt_children),
        percentile_cont(0.99) within group(order by cnt_children),
        max(cnt_children)
    from socdemo_result
    where cnt_children is not null

    union all

    select
        'date_employment_from_months',
        min(date_employment_from),
        percentile_cont(0.01) within group(order by date_employment_from),
        percentile_cont(0.50) within group(order by date_employment_from),
        percentile_cont(0.99) within group(order by date_employment_from),
        max(date_employment_from)
    from socdemo_result
    where date_employment_from is not null

    union all

    select
        'date_employment_to_months',
        min(date_employment_to),
        percentile_cont(0.01) within group(order by date_employment_to),
        percentile_cont(0.50) within group(order by date_employment_to),
        percentile_cont(0.99) within group(order by date_employment_to),
        max(date_employment_to)
    from socdemo_result
    where date_employment_to is not null

    union all

    select
        'months_last_rejection',
        min(months_last_rejection),
        percentile_cont(0.01) within group(order by months_last_rejection),
        percentile_cont(0.50) within group(order by months_last_rejection),
        percentile_cont(0.99) within group(order by months_last_rejection),
        max(months_last_rejection)
    from socdemo_result
    where months_last_rejection is not null
);


/* =====================================================================
   06 - MULTIPLICATION BEFORE poradi_app = 1
   Shows how many rows exist before final row_number filter.
   This is the main issue found in STEP 2.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
socdemo_pre as (
    select
        b.skp_client
    from owner_dwh.dc_client c
    join basic_sample b
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    cross join params p
    left join owner_dwh.f_application_detail_tt a
        on c.skp_client = a.skp_client
       and a.flag_last_appl_on_credit = 'Y'
       and a.date_decision < p.as_of_date
    left join owner_dwh.dc_eclient_account e
        on c.skp_client = e.skp_client
       and e.dtime_inserted < p.as_of_date
    left join (
        select
            ad.skp_client,
            ha.code_zip,
            row_number() over(
                partition by ad.skp_client
                order by ha.dtime_source_modified desc, ha.id_source desc
            ) as rn
        from basic_sample bs
        join owner_dwh.f_client_address_tt ad
            on bs.skp_client = ad.skp_client
        join owner_dwh.dh_address ha
            on ad.skp_address = ha.skp_address
           and ad.code_object_type = ha.code_object_type
        where ad.code_address_status = 'a'
          and ad.flag_address_reporting = 'Y'
          and ad.flag_address_current = 'Y'
          and ad.flag_deleted = 'N'
          and ha.flag_deleted = 'N'
    ) ad
        on b.skp_client = ad.skp_client
       and ad.rn = 1
    left join dm_campaign.cl_cmp_geography g
        on replace(ad.code_zip, ' ', '') = replace(g.code_zip, ' ', '')
    left join owner_dwh.f_client_employer_tt em
        on c.skp_client = em.skp_client
       and em.code_status = 'a'
       and em.date_employment_from < p.as_of_date
    left join dm_campaign.f_person_ad pp
        on c.skp_client = pp.skp_client
    where c.skp_client <> -1
      and c.name_first not like '%*%'
)
select
    count(*) as rows_before_rn_filter,
    count(distinct skp_client) as clients_distinct,
    count(*) - count(distinct skp_client) as extra_rows_before_rn_filter,
    max(cnt_per_client) as max_rows_per_client
from (
    select
        p.*,
        count(*) over(partition by skp_client) as cnt_per_client
    from socdemo_pre p
);


/* =====================================================================
   07 - SOURCE MULTIPLICITY PROFILE
   Checks which joined source has multiple records per client.
   Key sources:
   - APPLICATION
   - ECLIENT_ACCOUNT
   - EMPLOYER
   - ADDRESS_RAW_BEFORE_RN
   - GEOGRAPHY_AFTER_ADDRESS_RN
   - PERSON_AD
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
valid_clients as (
    select
        b.skp_client
    from basic_sample b
    join owner_dwh.dc_client c
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
address_raw as (
    select
        ad.skp_client,
        ha.code_zip,
        row_number() over(
            partition by ad.skp_client
            order by ha.dtime_source_modified desc, ha.id_source desc
        ) as rn
    from valid_clients v
    join owner_dwh.f_client_address_tt ad
        on v.skp_client = ad.skp_client
    join owner_dwh.dh_address ha
        on ad.skp_address = ha.skp_address
       and ad.code_object_type = ha.code_object_type
    where ad.code_address_status = 'a'
      and ad.flag_address_reporting = 'Y'
      and ad.flag_address_current = 'Y'
      and ad.flag_deleted = 'N'
      and ha.flag_deleted = 'N'
),
source_rows as (
    select
        'APPLICATION' as source_name,
        a.skp_client,
        count(*) as rows_per_client
    from valid_clients v
    join owner_dwh.f_application_detail_tt a
        on v.skp_client = a.skp_client
    cross join params p
    where a.flag_last_appl_on_credit = 'Y'
      and a.date_decision < p.as_of_date
    group by a.skp_client

    union all

    select
        'ECLIENT_ACCOUNT',
        e.skp_client,
        count(*)
    from valid_clients v
    join owner_dwh.dc_eclient_account e
        on v.skp_client = e.skp_client
    cross join params p
    where e.dtime_inserted < p.as_of_date
    group by e.skp_client

    union all

    select
        'ADDRESS_RAW_BEFORE_RN',
        ar.skp_client,
        count(*)
    from address_raw ar
    group by ar.skp_client

    union all

    select
        'GEOGRAPHY_AFTER_ADDRESS_RN',
        ar.skp_client,
        count(*)
    from address_raw ar
    join dm_campaign.cl_cmp_geography g
        on replace(ar.code_zip, ' ', '') = replace(g.code_zip, ' ', '')
    where ar.rn = 1
    group by ar.skp_client

    union all

    select
        'EMPLOYER',
        em.skp_client,
        count(*)
    from valid_clients v
    join owner_dwh.f_client_employer_tt em
        on v.skp_client = em.skp_client
    cross join params p
    where em.code_status = 'a'
      and em.date_employment_from < p.as_of_date
    group by em.skp_client

    union all

    select
        'PERSON_AD',
        pp.skp_client,
        count(*)
    from valid_clients v
    join dm_campaign.f_person_ad pp
        on v.skp_client = pp.skp_client
    group by pp.skp_client
)
select
    source_name,
    count(*) as clients_with_record,
    sum(case when rows_per_client > 1 then 1 else 0 end) as clients_with_multiple_records,
    sum(rows_per_client) as total_source_rows,
    round(avg(rows_per_client), 2) as avg_rows_if_present,
    max(rows_per_client) as max_rows_per_client
from source_rows
group by source_name
order by source_name;


/* =====================================================================
   08 - CLIENT MULTIPLICATION MATRIX
   Shows top clients by expected row multiplication.
   Useful to explain max rows per client, e.g. application_cnt * eclient_cnt.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
valid_clients as (
    select
        b.skp_client
    from basic_sample b
    join owner_dwh.dc_client c
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
address_raw as (
    select
        ad.skp_client,
        ha.code_zip,
        row_number() over(
            partition by ad.skp_client
            order by ha.dtime_source_modified desc, ha.id_source desc
        ) as rn
    from valid_clients v
    join owner_dwh.f_client_address_tt ad
        on v.skp_client = ad.skp_client
    join owner_dwh.dh_address ha
        on ad.skp_address = ha.skp_address
       and ad.code_object_type = ha.code_object_type
    where ad.code_address_status = 'a'
      and ad.flag_address_reporting = 'Y'
      and ad.flag_address_current = 'Y'
      and ad.flag_deleted = 'N'
      and ha.flag_deleted = 'N'
),
app_cnt as (
    select
        a.skp_client,
        count(*) as app_cnt
    from valid_clients v
    join owner_dwh.f_application_detail_tt a
        on v.skp_client = a.skp_client
    cross join params p
    where a.flag_last_appl_on_credit = 'Y'
      and a.date_decision < p.as_of_date
    group by a.skp_client
),
eclient_cnt as (
    select
        e.skp_client,
        count(*) as eclient_cnt
    from valid_clients v
    join owner_dwh.dc_eclient_account e
        on v.skp_client = e.skp_client
    cross join params p
    where e.dtime_inserted < p.as_of_date
    group by e.skp_client
),
geo_cnt as (
    select
        ar.skp_client,
        count(*) as geo_cnt
    from address_raw ar
    join dm_campaign.cl_cmp_geography g
        on replace(ar.code_zip, ' ', '') = replace(g.code_zip, ' ', '')
    where ar.rn = 1
    group by ar.skp_client
),
employer_cnt as (
    select
        em.skp_client,
        count(*) as employer_cnt
    from valid_clients v
    join owner_dwh.f_client_employer_tt em
        on v.skp_client = em.skp_client
    cross join params p
    where em.code_status = 'a'
      and em.date_employment_from < p.as_of_date
    group by em.skp_client
),
person_ad_cnt as (
    select
        pp.skp_client,
        count(*) as person_ad_cnt
    from valid_clients v
    join dm_campaign.f_person_ad pp
        on v.skp_client = pp.skp_client
    group by pp.skp_client
),
client_counts as (
    select
        v.skp_client,
        nvl(a.app_cnt, 0) as app_cnt,
        nvl(e.eclient_cnt, 0) as eclient_cnt,
        nvl(g.geo_cnt, 0) as geo_cnt,
        nvl(em.employer_cnt, 0) as employer_cnt,
        nvl(pp.person_ad_cnt, 0) as person_ad_cnt,

        greatest(nvl(a.app_cnt, 0), 1)
        * greatest(nvl(e.eclient_cnt, 0), 1)
        * greatest(nvl(g.geo_cnt, 0), 1)
        * greatest(nvl(em.employer_cnt, 0), 1)
        * greatest(nvl(pp.person_ad_cnt, 0), 1) as expected_pre_rows
    from valid_clients v
    left join app_cnt a
        on v.skp_client = a.skp_client
    left join eclient_cnt e
        on v.skp_client = e.skp_client
    left join geo_cnt g
        on v.skp_client = g.skp_client
    left join employer_cnt em
        on v.skp_client = em.skp_client
    left join person_ad_cnt pp
        on v.skp_client = pp.skp_client
)
select *
from (
    select
        skp_client,
        app_cnt,
        eclient_cnt,
        geo_cnt,
        employer_cnt,
        person_ad_cnt,
        expected_pre_rows
    from client_counts
    where expected_pre_rows > 1
    order by expected_pre_rows desc, skp_client
)
where rownum <= 50;


/* =====================================================================
   09 - INCREMENTAL JOIN ROWCOUNT
   Shows where rows start to multiply after each join.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
valid_clients as (
    select
        b.skp_client
    from basic_sample b
    join owner_dwh.dc_client c
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
application_rows as (
    select
        a.skp_client
    from valid_clients v
    join owner_dwh.f_application_detail_tt a
        on v.skp_client = a.skp_client
    cross join params p
    where a.flag_last_appl_on_credit = 'Y'
      and a.date_decision < p.as_of_date
),
eclient_rows as (
    select
        e.skp_client
    from valid_clients v
    join owner_dwh.dc_eclient_account e
        on v.skp_client = e.skp_client
    cross join params p
    where e.dtime_inserted < p.as_of_date
),
address_raw as (
    select
        ad.skp_client,
        ha.code_zip,
        row_number() over(
            partition by ad.skp_client
            order by ha.dtime_source_modified desc, ha.id_source desc
        ) as rn
    from valid_clients v
    join owner_dwh.f_client_address_tt ad
        on v.skp_client = ad.skp_client
    join owner_dwh.dh_address ha
        on ad.skp_address = ha.skp_address
       and ad.code_object_type = ha.code_object_type
    where ad.code_address_status = 'a'
      and ad.flag_address_reporting = 'Y'
      and ad.flag_address_current = 'Y'
      and ad.flag_deleted = 'N'
      and ha.flag_deleted = 'N'
),
address_one as (
    select
        skp_client,
        code_zip
    from address_raw
    where rn = 1
),
geography_rows as (
    select
        ad.skp_client
    from address_one ad
    join dm_campaign.cl_cmp_geography g
        on replace(ad.code_zip, ' ', '') = replace(g.code_zip, ' ', '')
),
employer_rows as (
    select
        em.skp_client
    from valid_clients v
    join owner_dwh.f_client_employer_tt em
        on v.skp_client = em.skp_client
    cross join params p
    where em.code_status = 'a'
      and em.date_employment_from < p.as_of_date
),
person_ad_rows as (
    select
        pp.skp_client
    from valid_clients v
    join dm_campaign.f_person_ad pp
        on v.skp_client = pp.skp_client
),
stage_00 as (
    select skp_client
    from valid_clients
),
stage_01 as (
    select s.skp_client
    from stage_00 s
    left join application_rows a
        on s.skp_client = a.skp_client
),
stage_02 as (
    select s.skp_client
    from stage_01 s
    left join eclient_rows e
        on s.skp_client = e.skp_client
),
stage_03 as (
    select s.skp_client
    from stage_02 s
    left join address_one ad
        on s.skp_client = ad.skp_client
),
stage_04 as (
    select s.skp_client
    from stage_03 s
    left join geography_rows g
        on s.skp_client = g.skp_client
),
stage_05 as (
    select s.skp_client
    from stage_04 s
    left join employer_rows em
        on s.skp_client = em.skp_client
),
stage_06 as (
    select s.skp_client
    from stage_05 s
    left join person_ad_rows pp
        on s.skp_client = pp.skp_client
),
all_stage_rows as (
    select '00_VALID_CLIENTS' as stage_name, skp_client from stage_00
    union all select '01_AFTER_APPLICATION', skp_client from stage_01
    union all select '02_AFTER_ECLIENT', skp_client from stage_02
    union all select '03_AFTER_ADDRESS', skp_client from stage_03
    union all select '04_AFTER_GEOGRAPHY', skp_client from stage_04
    union all select '05_AFTER_EMPLOYER', skp_client from stage_05
    union all select '06_AFTER_PERSON_AD', skp_client from stage_06
),
stage_client_counts as (
    select
        stage_name,
        skp_client,
        count(*) as rows_per_client
    from all_stage_rows
    group by
        stage_name,
        skp_client
)
select
    stage_name,
    sum(rows_per_client) as rows_total,
    count(*) as clients_distinct,
    sum(rows_per_client) - count(*) as extra_rows,
    max(rows_per_client) as max_rows_per_client
from stage_client_counts
group by stage_name
order by stage_name;


/* =====================================================================
   10 - VALUE VARIABILITY BEFORE poradi_app = 1
   Checks whether duplicated pre-rows contain different output values.
   If yes, row_number may be selecting one of several possible values.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
address_one as (
    select
        skp_client,
        name_street,
        text_street_number,
        name_town,
        code_zip
    from (
        select
            ad.skp_client,
            ha.name_street,
            ha.text_street_number,
            ha.name_town,
            ha.code_zip,
            row_number() over(
                partition by ad.skp_client
                order by ha.dtime_source_modified desc, ha.id_source desc
            ) as rn
        from basic_sample bs
        join owner_dwh.f_client_address_tt ad
            on bs.skp_client = ad.skp_client
        join owner_dwh.dh_address ha
            on ad.skp_address = ha.skp_address
           and ad.code_object_type = ha.code_object_type
        where ad.code_address_status = 'a'
          and ad.flag_address_reporting = 'Y'
          and ad.flag_address_current = 'Y'
          and ad.flag_deleted = 'N'
          and ha.flag_deleted = 'N'
    )
    where rn = 1
),
socdemo_pre as (
    select
        b.skp_client,
        a.date_decision,
        a.amt_income,
        nvl(a.amt_income, 0) + nvl(a.amt_income_partner, 0) as amt_income_total,
        nvl(a.cnt_children, 0) as cnt_children,
        case when e.skp_client is not null then 1 else 0 end as flag_eclient,
        g.name_municipality,
        em.name_employer,
        months_between(p.as_of_date, em.date_employment_from) as months_employment_from,
        months_between(em.date_employment_to, p.as_of_date) as months_employment_to,
        case when pp.text_best_email_contact is not null then 1 else 0 end as flag_mail,
        case when pp.text_best_phone_contact is not null then 1 else 0 end as flag_phone,
        case when pp.code_phone_contact_validity in (2, 3) then 1 else 0 end as flag_phone_verified
    from owner_dwh.dc_client c
    join basic_sample b
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    cross join params p
    left join owner_dwh.f_application_detail_tt a
        on c.skp_client = a.skp_client
       and a.flag_last_appl_on_credit = 'Y'
       and a.date_decision < p.as_of_date
    left join owner_dwh.dc_eclient_account e
        on c.skp_client = e.skp_client
       and e.dtime_inserted < p.as_of_date
    left join address_one ad
        on b.skp_client = ad.skp_client
    left join dm_campaign.cl_cmp_geography g
        on replace(ad.code_zip, ' ', '') = replace(g.code_zip, ' ', '')
    left join owner_dwh.f_client_employer_tt em
        on c.skp_client = em.skp_client
       and em.code_status = 'a'
       and em.date_employment_from < p.as_of_date
    left join dm_campaign.f_person_ad pp
        on c.skp_client = pp.skp_client
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
per_client as (
    select
        skp_client,
        count(*) as rows_pre,

        count(distinct nvl(to_char(date_decision, 'YYYY-MM-DD HH24:MI:SS'), '<NULL>')) as distinct_date_decision,
        count(distinct nvl(to_char(amt_income), '<NULL>')) as distinct_amt_income,
        count(distinct nvl(to_char(amt_income_total), '<NULL>')) as distinct_amt_income_total,
        count(distinct nvl(to_char(cnt_children), '<NULL>')) as distinct_cnt_children,
        count(distinct nvl(to_char(flag_eclient), '<NULL>')) as distinct_flag_eclient,
        count(distinct nvl(name_municipality, '<NULL>')) as distinct_name_municipality,
        count(distinct nvl(name_employer, '<NULL>')) as distinct_name_employer,
        count(distinct nvl(to_char(months_employment_from), '<NULL>')) as distinct_months_employment_from,
        count(distinct nvl(to_char(months_employment_to), '<NULL>')) as distinct_months_employment_to,
        count(distinct nvl(to_char(flag_mail), '<NULL>')) as distinct_flag_mail,
        count(distinct nvl(to_char(flag_phone), '<NULL>')) as distinct_flag_phone,
        count(distinct nvl(to_char(flag_phone_verified), '<NULL>')) as distinct_flag_phone_verified
    from socdemo_pre
    group by skp_client
    having count(*) > 1
)
select
    count(*) as clients_with_multiple_pre_rows,
    max(rows_pre) as max_rows_pre,

    sum(case when distinct_date_decision > 1 then 1 else 0 end) as clients_multi_date_decision,
    sum(case when distinct_amt_income > 1 then 1 else 0 end) as clients_multi_amt_income,
    sum(case when distinct_amt_income_total > 1 then 1 else 0 end) as clients_multi_amt_income_total,
    sum(case when distinct_cnt_children > 1 then 1 else 0 end) as clients_multi_cnt_children,

    sum(case when distinct_flag_eclient > 1 then 1 else 0 end) as clients_multi_flag_eclient,
    sum(case when distinct_name_municipality > 1 then 1 else 0 end) as clients_multi_name_municipality,

    sum(case when distinct_name_employer > 1 then 1 else 0 end) as clients_multi_name_employer,
    sum(case when distinct_months_employment_from > 1 then 1 else 0 end) as clients_multi_months_employment_from,
    sum(case when distinct_months_employment_to > 1 then 1 else 0 end) as clients_multi_months_employment_to,

    sum(case when distinct_flag_mail > 1 then 1 else 0 end) as clients_multi_flag_mail,
    sum(case when distinct_flag_phone > 1 then 1 else 0 end) as clients_multi_flag_phone,
    sum(case when distinct_flag_phone_verified > 1 then 1 else 0 end) as clients_multi_flag_phone_verified
from per_client;


/* =====================================================================
   11 - LATEST APPLICATION TIE CHECK
   Checks if client has multiple application rows with the same latest
   date_decision.
   This is important because production row_number orders only by
   a.date_decision desc.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
valid_clients as (
    select
        b.skp_client
    from basic_sample b
    join owner_dwh.dc_client c
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
app_rows as (
    select
        a.skp_client,
        a.date_decision,
        a.amt_income,
        a.amt_income_partner,
        a.cnt_children
    from valid_clients v
    join owner_dwh.f_application_detail_tt a
        on v.skp_client = a.skp_client
    cross join params p
    where a.flag_last_appl_on_credit = 'Y'
      and a.date_decision < p.as_of_date
),
app_latest_counts as (
    select
        a.skp_client,
        count(*) as cnt_latest_rows
    from app_rows a
    join (
        select
            skp_client,
            max(date_decision) as max_date_decision
        from app_rows
        group by skp_client
    ) m
        on a.skp_client = m.skp_client
       and a.date_decision = m.max_date_decision
    group by a.skp_client
)
select
    count(*) as clients_with_latest_app,
    sum(case when cnt_latest_rows > 1 then 1 else 0 end) as clients_with_latest_app_tie,
    max(cnt_latest_rows) as max_latest_rows_per_client
from app_latest_counts;


/* =====================================================================
   12 - LATEST APPLICATION TIE VALUE DIFFERENCES
   Checks whether latest application candidates have different values.
   If differences exist, current row_number selection may affect predictors.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
valid_clients as (
    select
        b.skp_client
    from basic_sample b
    join owner_dwh.dc_client c
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
app_rows as (
    select
        a.skp_client,
        a.date_decision,
        a.amt_income,
        a.amt_income_partner,
        nvl(a.amt_income, 0) + nvl(a.amt_income_partner, 0) as amt_income_total,
        nvl(a.cnt_children, 0) as cnt_children
    from valid_clients v
    join owner_dwh.f_application_detail_tt a
        on v.skp_client = a.skp_client
    cross join params p
    where a.flag_last_appl_on_credit = 'Y'
      and a.date_decision < p.as_of_date
),
app_latest_candidates as (
    select
        a.*
    from app_rows a
    join (
        select
            skp_client,
            max(date_decision) as max_date_decision
        from app_rows
        group by skp_client
    ) m
        on a.skp_client = m.skp_client
       and a.date_decision = m.max_date_decision
),
per_client as (
    select
        skp_client,
        count(*) as latest_rows,
        count(distinct nvl(to_char(amt_income), '<NULL>')) as distinct_amt_income,
        count(distinct nvl(to_char(amt_income_total), '<NULL>')) as distinct_amt_income_total,
        count(distinct nvl(to_char(cnt_children), '<NULL>')) as distinct_cnt_children
    from app_latest_candidates
    group by skp_client
    having count(*) > 1
)
select
    count(*) as clients_with_latest_app_tie,
    sum(case when distinct_amt_income > 1 then 1 else 0 end) as clients_diff_amt_income,
    sum(case when distinct_amt_income_total > 1 then 1 else 0 end) as clients_diff_amt_income_total,
    sum(case when distinct_cnt_children > 1 then 1 else 0 end) as clients_diff_cnt_children,
    max(latest_rows) as max_latest_rows
from per_client;


/* =====================================================================
   13 - DETAIL OF LATEST APPLICATION TIES
   Optional diagnostic detail.
   Use only if section 11 / 12 shows non-zero tie counts.
   ===================================================================== */

with params as (
    select
        date '2026-04-01' as as_of_date,
        5000 as sample_size
    from dual
),
basic_full as (
    select distinct
        h.skp_client
    from AP_CRM_MODEL.sdm_person_history h
    cross join params p
    where h.month_inserted = trunc(p.as_of_date, 'mm')
),
basic_sample as (
    select
        x.skp_client
    from (
        select
            bf.skp_client,
            row_number() over(order by ora_hash(bf.skp_client), bf.skp_client) as rn
        from basic_full bf
    ) x
    where x.rn <= (select sample_size from params)
),
valid_clients as (
    select
        b.skp_client
    from basic_sample b
    join owner_dwh.dc_client c
        on c.skp_client = b.skp_client
    join owner_dwh.dc_client_demography d
        on c.skp_client_demography = d.skp_client_demography
    where c.skp_client <> -1
      and c.name_first not like '%*%'
),
app_rows as (
    select
        a.skp_client,
        a.date_decision,
        a.amt_income,
        a.amt_income_partner,
        nvl(a.amt_income, 0) + nvl(a.amt_income_partner, 0) as amt_income_total,
        nvl(a.cnt_children, 0) as cnt_children
    from valid_clients v
    join owner_dwh.f_application_detail_tt a
        on v.skp_client = a.skp_client
    cross join params p
    where a.flag_last_appl_on_credit = 'Y'
      and a.date_decision < p.as_of_date
),
app_latest_candidates as (
    select
        a.*
    from app_rows a
    join (
        select
            skp_client,
            max(date_decision) as max_date_decision
        from app_rows
        group by skp_client
    ) m
        on a.skp_client = m.skp_client
       and a.date_decision = m.max_date_decision
),
tie_clients as (
    select
        skp_client,
        count(*) as latest_rows
    from app_latest_candidates
    group by skp_client
    having count(*) > 1
)
select *
from (
    select
        a.skp_client,
        t.latest_rows,
        a.date_decision,
        a.amt_income,
        a.amt_income_partner,
        a.amt_income_total,
        a.cnt_children
    from app_latest_candidates a
    join tie_clients t
        on a.skp_client = t.skp_client
    order by
        t.latest_rows desc,
        a.skp_client,
        a.date_decision desc
)
where rownum <= 100;


/* =====================================================================
   14 - APPLICATION TABLE COLUMNS FOR POSSIBLE TIE-BREAKER
   Diagnostic only.
   Purpose:
   - Find candidate technical columns for stable ordering in future refactor.
   - Example candidates could be SKP_APPLICATION, SKP_CREDIT_CASE,
     ID_SOURCE, DTIME_INSERTED, DTIME_SOURCE_MODIFIED, etc.
   ===================================================================== */

select
    column_id,
    column_name,
    data_type
from all_tab_columns
where owner = 'OWNER_DWH'
  and table_name = 'F_APPLICATION_DETAIL_TT'
  and (
       column_name like '%SKP%'
    or column_name like '%ID%'
    or column_name like '%DATE%'
    or column_name like '%DTIME%'
    or column_name like '%APPLICATION%'
    or column_name like '%CREDIT%'
  )
order by column_id;


/* =====================================================================
   END OF STEP 2 AUDIT SCRIPT
   ===================================================================== */
