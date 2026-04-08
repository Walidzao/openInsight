{{ config(materialized='table') }}

/*
 Using ClickHouse's PostgreSQL engine to query dim_customers from PG.
 This avoids needing Trino for the V1 local dev use case.
 Credentials sourced from dbt project variables.
*/
SELECT * FROM postgresql(
    '{{ var("pg_host", "postgres") }}:{{ var("pg_port", "5432") }}',
    '{{ var("pg_database", "openinsight") }}',
    'customers',
    '{{ var("pg_user", "openinsight") }}',
    '{{ var("pg_password", "openinsight_dev") }}'
)
