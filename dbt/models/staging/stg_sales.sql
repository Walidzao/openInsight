SELECT
    sale_id,
    sale_date,
    customer_id,
    product_category_id,
    region_code,
    department_code,
    quantity,
    unit_price,
    total_amount,
    currency,
    created_at
FROM {{ source('openinsight', 'fct_sales') }}
