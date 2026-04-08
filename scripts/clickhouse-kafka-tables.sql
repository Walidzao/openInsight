-- ClickHouse Kafka Engine Tables and Materialized Views
-- Connects Redpanda topics to openinsight MergeTree tables

CREATE TABLE IF NOT EXISTS openinsight.ingest_raw_transactions (
    sale_id UInt64,
    sale_date Date,
    customer_id UInt32,
    product_category_id UInt32,
    region_code String,
    department_code String,
    quantity UInt32,
    unit_price Decimal(12, 2),
    total_amount Decimal(12, 2),
    currency String
) ENGINE = Kafka()
SETTINGS
    kafka_broker_list = 'redpanda:9092',
    kafka_topic_list = 'ingest.raw.transactions',
    kafka_group_name = 'ch_ingest_transactions',
    kafka_format = 'JSONEachRow';


CREATE MATERIALIZED VIEW IF NOT EXISTS openinsight.mv_sales_ingest 
TO openinsight.fct_sales AS
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
    now() AS created_at
FROM openinsight.ingest_raw_transactions;

CREATE TABLE IF NOT EXISTS openinsight.ingest_raw_events (
    event_id UUID,
    event_timestamp DateTime,
    event_type String,
    user_id String,
    department_code String,
    resource_type String,
    resource_id String,
    duration_ms UInt32,
    metadata String
) ENGINE = Kafka()
SETTINGS
    kafka_broker_list = 'redpanda:9092',
    kafka_topic_list = 'ingest.raw.events',
    kafka_group_name = 'ch_ingest_events',
    kafka_format = 'JSONEachRow';


CREATE MATERIALIZED VIEW IF NOT EXISTS openinsight.mv_events_ingest 
TO openinsight.fct_events AS
SELECT
    event_id,
    event_timestamp,
    event_type,
    user_id,
    department_code,
    resource_type,
    resource_id,
    duration_ms,
    metadata
FROM openinsight.ingest_raw_events;
