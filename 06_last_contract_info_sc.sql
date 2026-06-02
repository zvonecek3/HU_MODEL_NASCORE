select
    count(*) as row_cnt,
    count(distinct skp_client) as distinct_client_cnt
from HU_model_last_con_info_sc;

--duplicity
select
    skp_client,
    count(*) as cnt
from HU_model_last_con_info_sc
group by skp_client
having count(*) > 1;

-- porovnani joinu

with base as (
    select
        a.skp_client,
        a.credit_case_akv,
        a.credit_type_akv,
        a.dade_akv
    from ap_crm_model.HU_model_last_con_sc a
),

with_contract_ad as (
    select b.*, c.skp_credit_status, c.skp_credit_segmentation, c.skp_product, c.skp_salesroom
    from base b
    inner join owner_dwh.f_contract_ad c
        on b.credit_case_akv = c.skp_credit_case
       and b.credit_type_akv = c.skp_credit_type
       and b.dade_akv = c.date_decision
),

with_credit_status as (
    select wca.*
    from with_contract_ad wca
    inner join owner_dwh.cl_credit_status ccs
        on wca.skp_credit_status = ccs.skp_credit_status
),

with_segmentation as (
    select wcs.*
    from with_credit_status wcs
    inner join owner_dwh.dc_credit_segmentation g
        on wcs.skp_credit_segmentation = g.skp_credit_segmentation
),

with_product as (
    select ws.*
    from with_segmentation ws
    inner join owner_dwh.dc_product p
        on ws.skp_product = p.skp_product
),

with_salesroom as (
    select wp.*, r.skp_seller
    from with_product wp
    inner join owner_dwh.dc_salesroom r
        on wp.skp_salesroom = r.skp_salesroom
),

with_seller as (
    select wr.*
    from with_salesroom wr
    inner join owner_dwh.dc_seller l
        on wr.skp_seller = l.skp_seller
)

select '01_base_step5' as step_name, count(*) row_cnt, count(distinct skp_client) client_cnt from base
union all
select '02_with_contract_ad', count(*), count(distinct skp_client) from with_contract_ad
union all
select '03_with_credit_status', count(*), count(distinct skp_client) from with_credit_status
union all
select '04_with_segmentation', count(*), count(distinct skp_client) from with_segmentation
union all
select '05_with_product', count(*), count(distinct skp_client) from with_product
union all
select '06_with_salesroom', count(*), count(distinct skp_client) from with_salesroom
union all
select '07_with_seller', count(*), count(distinct skp_client) from with_seller;




with benefit_source as (
    select
        cf.skp_credit_case,
        cf.dtime_valid_to,
        cl.name_codelist_value,
        ft.code_flag_type_general,
        ft.name_flag_type_general
    from owner_dwh.f_credit_flag_at cf
    inner join owner_dwh.cl_flag_type_general ft
        on cf.skp_flag_type_general = ft.skp_flag_type_general
    inner join owner_dwh.cl_codelist_value_hom cl
        on cf.text_credit_flag_value = cl.code_codelist_value
    where cl.code_codelist = '1017'
      and cl.code_status = 'a'
      and lower(ft.name_flag_type_general) like '%turbo%'
),

max_dates as (
    select
        skp_credit_case,
        max(dtime_valid_to) as max_dtime_valid_to
    from benefit_source
    group by skp_credit_case
)

select
    bs.skp_credit_case,
    bs.dtime_valid_to,
    count(*) as cnt
from benefit_source bs
inner join max_dates md
    on bs.skp_credit_case = md.skp_credit_case
   and bs.dtime_valid_to = md.max_dtime_valid_to
group by
    bs.skp_credit_case,
    bs.dtime_valid_to
having count(*) > 1
order by cnt desc;



with status_check as (
    select
        a.skp_client,
        a.credit_case_akv,
        cs.code_credit_status as current_status,
        ccs.code_credit_status as contract_ad_status,
        case 
            when cs.code_credit_status is null then 1 
            else 0 
        end as fallback_used
    from ap_crm_model.HU_model_last_con_sc a
    inner join owner_dwh.f_contract_ad c
        on a.credit_case_akv = c.skp_credit_case
       and a.credit_type_akv = c.skp_credit_type
       and a.dade_akv = c.date_decision
    inner join owner_dwh.cl_credit_status ccs
        on c.skp_credit_status = ccs.skp_credit_status
    left join owner_dwh.f_credit_status_tt s
        on a.credit_case_akv = s.skp_credit_case
       and a.credit_type_akv = s.skp_credit_type
       and a.dade_akv = s.date_decision
       and date '2026-04-01' between s.dtime_valid_from and s.dtime_valid_to
    left join owner_dwh.cl_credit_status cs
        on s.skp_credit_status = cs.skp_credit_status
)

select
    fallback_used,
    count(*) as row_cnt,
    count(distinct skp_client) as client_cnt
from status_check
group by fallback_used
order by fallback_used;



-- distinct counter 

with joined_data as (
    select
        a.skp_client,
        a.credit_case_akv,
        c.amt_annuity,
        c.amt_credit,
        c.amt_credit_start,
        g.name_segment_level_1_sales,
        g.name_segment_level_2,
        c.cnt_days_past_due_maximal,
        c.amt_goods_price,
        c.cnt_instalment,
        c.flag_insured_ppi,
        c.flag_insured_pzk,
        c.flag_ins_holiday_allowed,
        c.flag_ins_recalculation_allowed,
        case 
            when c.date_contract_close = date '3000-01-01'
                then floor(months_between(date '2026-04-01', c.date_decision))
            else floor(months_between(c.date_contract_close, c.date_decision))
        end as mob,
        case 
            when cs.code_credit_status is null then ccs.code_credit_status
            else cs.code_credit_status
        end as code_credit_status,
        nvl(bf.name_codelist_value, '0') as benefit,
        c.rate_interest_basic,
        p.code_channel,
        nvl(p.code_profit_group, '0') as code_profit_group,
        p.flag_zero,
        p.rate_bonus,
        case
            when c.skp_credit_type = 1 then
                case
                    when g.name_segment_level_2 = 'PoS, KA, Datart'
                      or upper(l.name_seller) like '%DATART %' then 'DATART'
                    when g.name_segment_level_2 = 'PoS, KA, O2'
                      or l.code_seller = '010410' then 'O2'
                    when g.name_segment_level_2 = 'PoS, KA, Tesco'
                      or l.code_seller = '017700' then 'TESCO'
                    else 'HC'
                end

            when c.skp_credit_type = 2 then
                case
                    when p.code_channel in ('SC004', 'SC005', 'SC007')
                      or l.code_seller = '0131' then 'CPG'
                    when l.code_seller = '017700'
                      or p.code_channel = 'SC018' then 'TESCO'
                    else 'HC'
                end

            when c.skp_credit_type = 3 then
                case
                    when p.code_channel in ('RD017','RD035','RD013','RD014','RD016','RD024','RD028') then 'CPG'
                    when (
                            p.code_channel = 'RD018'
                        and p.code_product in (
                            'PKDAT','PKDAT11','PKDAT11T','PKDATRE24','PKD10N','PKD20N',
                            'PKDL66','PKDL72','PKPROC05','PKPROC06','PKPROC07','PKPROC08',
                            'PKPROC09','PKPROC10','PKPROC11','PKPROC12','PKPROC13','PKPROC14',
                            'PKPROC15','PKPROC16','PKPROC17','PKPROC18','PKPROC19','PKPROC20',
                            'PKPROC21','PKPROC22','PKPROC23','PKPROC24','PKPROC25'
                        )
                    )
                    or p.code_channel in ('RD050','RD051','RD052','RD053') then 'DATART'
                    when p.code_channel in ('RD041','RD042','RD043','RD044','RD045','RD046','RD047') then 'O2'
                    when p.code_channel in ('RD030','RD031','RD032','RD033','RD037','RD029','RD040','RD061') then 'TESCO'
                    when p.code_channel = 'RD060' then 'Online'
                    else 'HC'
                end
            else null
        end as contract_brand,
        case
            when c.amt_credit = 0 or c.amt_credit is null then 0
            else c.amt_outstanding_principal / c.amt_credit
        end as zbyva_doplatit,
        c.cnt_inst_regular_unpaid,
        a.dade_akv as date_decision_last

    from ap_crm_model.hu_model_last_con_sc a
    inner join owner_dwh.f_contract_ad c
        on a.credit_case_akv = c.skp_credit_case
       and a.credit_type_akv = c.skp_credit_type
       and a.dade_akv = c.date_decision
    inner join owner_dwh.cl_credit_status ccs
        on c.skp_credit_status = ccs.skp_credit_status
    inner join owner_dwh.dc_credit_segmentation g
        on c.skp_credit_segmentation = g.skp_credit_segmentation
    inner join owner_dwh.dc_product p
        on c.skp_product = p.skp_product
    inner join owner_dwh.dc_salesroom r
        on c.skp_salesroom = r.skp_salesroom
    inner join owner_dwh.dc_seller l
        on r.skp_seller = l.skp_seller
    left join owner_dwh.f_credit_status_tt s
        on a.credit_case_akv = s.skp_credit_case
       and a.credit_type_akv = s.skp_credit_type
       and a.dade_akv = s.date_decision
       and date '2026-04-01' between s.dtime_valid_from and s.dtime_valid_to
    left join owner_dwh.cl_credit_status cs
        on s.skp_credit_status = cs.skp_credit_status
    left join (
        select
            distinct
            cf.skp_credit_case,
            cf.dtime_valid_to,
            cl.name_codelist_value,
            ft.code_flag_type_general,
            ft.name_flag_type_general,
            row_number() over (
                partition by cf.skp_credit_case
                order by cf.dtime_valid_to desc
            ) as poradi
        from owner_dwh.f_credit_flag_at cf
        inner join owner_dwh.cl_flag_type_general ft
            on cf.skp_flag_type_general = ft.skp_flag_type_general
        inner join owner_dwh.cl_codelist_value_hom cl
            on cf.text_credit_flag_value = cl.code_codelist_value
        where cl.code_codelist = '1017'
          and cl.code_status = 'a'
          and lower(ft.name_flag_type_general) like '%turbo%'
    ) bf
        on a.credit_case_akv = bf.skp_credit_case
       and bf.poradi = 1
)

select
    count(*) as rows_before_distinct,
    count(distinct skp_client) as distinct_clients,
    count(distinct credit_case_akv) as distinct_credit_cases
from joined_data;
