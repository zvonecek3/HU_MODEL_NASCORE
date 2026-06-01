## Validation result

Audit was run with `AS_OF_DATE = DATE '2026-04-01'`.

The step produced:

- 3,851,703 base contract rows
- 1,616,580 clients with contract history
- 3,343,364 final aggregated rows
- `sum(pocet_cnt) = 3,851,703`

Join diagnostics showed no row loss and no row multiplication:

- `dc_contract`: 3,851,703 rows
- after valid credit status join: 3,851,703 rows
- after credit segmentation join: 3,851,703 rows
- after contract AD join: 3,851,703 rows

Both checked risky joins are 1:1 for the analyzed population:

- `f_contract_ad`: exactly 1 row per `SKP_CREDIT_CASE`
- `f_credit_status_tt`: exactly 1 valid status row per contract and as-of date

Therefore, in this audited run, `pocet_cnt = count(*)` can be interpreted as the number of contracts in the aggregation bucket.

The output is not unique by `SKP_CLIENT`. It is unique by the full aggregation grain:

`SKP_CLIENT × CODE_CREDIT_STATUS × SKP_CREDIT_TYPE × CREDIT_SEGMENT × CODE_SEGMENTATION_ENVIRONMENT × CODE_SEGMENTATION_SALES_TYPE × CODE_SEGMENTATION_PROPOSITION × CODE_SEGMENTATION_PRODUCT × CODE_SEGMENTATION_OTHER`

If this table is joined to later client-level tables only by `SKP_CLIENT`, it will multiply client rows.






## Additional validation

Rows per client distribution:

- min: 1
- max: 175
- avg: 2.067
- p50: 2
- p90: 4
- p99: 8

The distribution is generally reasonable. One client has 175 aggregation buckets and should be checked separately as an outlier.

`credit_segment` validation showed that all 3,851,703 contract rows are classified as `akv`.

No rows were classified as `x-sell` under the current CASE logic. This is technically consistent with the SQL result, but it may indicate that the old x-sell segmentation rule is stale or too narrow. The current logic only recognizes:

- `SKP_CREDIT_TYPE = 2` and `NAME_SEGMENT_LEVEL_2 = 'Cash, X, DM'`
- `SKP_CREDIT_TYPE = 3` and `NAME_SEGMENT_LEVEL_2 in ('Credit Card X-sell', 'Revolving Loan X-sell')`

A follow-up check of actual `NAME_SEGMENT_LEVEL_2` values for credit types 2 and 3 is recommended before treating `credit_segment` as a meaningful feature.
