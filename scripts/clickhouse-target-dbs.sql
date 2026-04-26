-- ClickHouse target databases for strict target switching

CREATE DATABASE IF NOT EXISTS engineering_data;

CREATE TABLE IF NOT EXISTS engineering_data.fct_sales (
    sale_id UInt64,
    sale_date Date,
    customer_id UInt32,
    product_category_id UInt32,
    region_code LowCardinality(String),
    department_code LowCardinality(String),
    quantity UInt32,
    unit_price Decimal(12, 2),
    total_amount Decimal(12, 2),
    currency LowCardinality(String) DEFAULT 'USD',
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (sale_date, region_code, department_code)
PARTITION BY toYYYYMM(sale_date);

CREATE TABLE IF NOT EXISTS engineering_data.fct_events (
    event_id UUID DEFAULT generateUUIDv4(),
    event_timestamp DateTime,
    event_type LowCardinality(String),
    user_id String,
    department_code LowCardinality(String),
    resource_type LowCardinality(String),
    resource_id String,
    duration_ms UInt32 DEFAULT 0,
    metadata String DEFAULT '{}'
) ENGINE = MergeTree()
ORDER BY (event_timestamp, event_type, department_code)
PARTITION BY toYYYYMM(event_timestamp);

INSERT INTO engineering_data.fct_sales
SELECT *
FROM openinsight.fct_sales
WHERE department_code = 'ENG'
  AND sale_id NOT IN (SELECT sale_id FROM engineering_data.fct_sales);

INSERT INTO engineering_data.fct_events
SELECT *
FROM openinsight.fct_events
WHERE department_code = 'ENG'
  AND event_id NOT IN (SELECT event_id FROM engineering_data.fct_events);

CREATE MATERIALIZED VIEW IF NOT EXISTS engineering_data.mv_sync_sales
TO engineering_data.fct_sales AS
SELECT *
FROM openinsight.fct_sales
WHERE department_code = 'ENG';

CREATE MATERIALIZED VIEW IF NOT EXISTS engineering_data.mv_sync_events
TO engineering_data.fct_events AS
SELECT *
FROM openinsight.fct_events
WHERE department_code = 'ENG';
