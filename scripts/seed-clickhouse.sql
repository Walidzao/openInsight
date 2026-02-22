-- OpenInsight ClickHouse Seed Data
-- Fact tables for analytics (OLAP storage)
-- These map to dbt models: fct_sales, fct_events

-- Sales fact table
CREATE TABLE IF NOT EXISTS openinsight.fct_sales (
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

-- Platform usage events
CREATE TABLE IF NOT EXISTS openinsight.fct_events (
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

-- Seed fct_sales with sample data across departments and regions
-- 6 months of data, ~50 rows
INSERT INTO openinsight.fct_sales (sale_id, sale_date, customer_id, product_category_id, region_code, department_code, quantity, unit_price, total_amount) VALUES
    (1, '2025-09-15', 1, 4, 'NA', 'SALES', 10, 99.00, 990.00),
    (2, '2025-09-22', 2, 5, 'EU', 'SALES', 5, 499.00, 2495.00),
    (3, '2025-10-01', 3, 8, 'APAC', 'ENG', 20, 150.00, 3000.00),
    (4, '2025-10-05', 1, 9, 'NA', 'SALES', 3, 2000.00, 6000.00),
    (5, '2025-10-12', 4, 4, 'LATAM', 'SALES', 15, 99.00, 1485.00),
    (6, '2025-10-20', 5, 6, 'MEA', 'ENG', 2, 5000.00, 10000.00),
    (7, '2025-11-01', 6, 4, 'NA', 'SALES', 50, 99.00, 4950.00),
    (8, '2025-11-03', 7, 8, 'EU', 'FIN', 8, 200.00, 1600.00),
    (9, '2025-11-10', 8, 7, 'APAC', 'ENG', 10, 800.00, 8000.00),
    (10, '2025-11-15', 9, 8, 'NA', 'ENG', 12, 175.00, 2100.00),
    (11, '2025-11-20', 10, 5, 'EU', 'SALES', 25, 499.00, 12475.00),
    (12, '2025-12-01', 1, 4, 'NA', 'SALES', 20, 99.00, 1980.00),
    (13, '2025-12-05', 2, 9, 'EU', 'SALES', 2, 3000.00, 6000.00),
    (14, '2025-12-10', 3, 4, 'APAC', 'SALES', 30, 99.00, 2970.00),
    (15, '2025-12-15', 6, 8, 'NA', 'ENG', 5, 250.00, 1250.00),
    (16, '2025-12-20', 7, 5, 'EU', 'FIN', 10, 499.00, 4990.00),
    (17, '2026-01-05', 1, 4, 'NA', 'SALES', 25, 109.00, 2725.00),
    (18, '2026-01-08', 4, 7, 'LATAM', 'ENG', 5, 1200.00, 6000.00),
    (19, '2026-01-12', 8, 4, 'APAC', 'SALES', 40, 109.00, 4360.00),
    (20, '2026-01-15', 10, 6, 'EU', 'ENG', 3, 8000.00, 24000.00),
    (21, '2026-01-20', 5, 9, 'MEA', 'SALES', 1, 5000.00, 5000.00),
    (22, '2026-01-25', 9, 8, 'NA', 'ENG', 15, 175.00, 2625.00),
    (23, '2026-02-01', 2, 4, 'EU', 'SALES', 35, 109.00, 3815.00),
    (24, '2026-02-05', 3, 8, 'APAC', 'ENG', 10, 200.00, 2000.00),
    (25, '2026-02-10', 1, 5, 'NA', 'SALES', 8, 549.00, 4392.00),
    (26, '2026-02-12', 7, 4, 'EU', 'FIN', 20, 109.00, 2180.00),
    (27, '2026-02-15', 6, 9, 'NA', 'ENG', 4, 2500.00, 10000.00);

-- Seed fct_events with sample platform usage
INSERT INTO openinsight.fct_events (event_timestamp, event_type, user_id, department_code, resource_type, resource_id, duration_ms) VALUES
    ('2026-02-14 09:00:00', 'dashboard_view', 'alice.finance', 'FIN', 'dashboard', 'revenue-overview', 1200),
    ('2026-02-14 09:05:00', 'query_execute', 'alice.finance', 'FIN', 'sql_lab', 'q-001', 3400),
    ('2026-02-14 09:30:00', 'dashboard_view', 'bob.hr', 'HR', 'dashboard', 'headcount-report', 800),
    ('2026-02-14 10:00:00', 'dashboard_view', 'carol.engineering', 'ENG', 'dashboard', 'sprint-metrics', 950),
    ('2026-02-14 10:15:00', 'query_execute', 'carol.engineering', 'ENG', 'sql_lab', 'q-002', 5200),
    ('2026-02-14 10:30:00', 'api_call', 'cube-service', 'ENG', 'cube_api', '/cubejs-api/v1/load', 120),
    ('2026-02-14 11:00:00', 'dashboard_view', 'dave.executive', 'EXEC', 'dashboard', 'executive-summary', 700),
    ('2026-02-14 11:30:00', 'dashboard_view', 'eve.viewer', 'FIN', 'dashboard', 'revenue-overview', 900),
    ('2026-02-14 14:00:00', 'dashboard_view', 'alice.finance', 'FIN', 'dashboard', 'cost-analysis', 1100),
    ('2026-02-14 14:20:00', 'query_execute', 'alice.finance', 'FIN', 'sql_lab', 'q-003', 8700),
    ('2026-02-14 15:00:00', 'pipeline_run', 'airflow', 'ENG', 'dag', 'dag_hop_ingest', 45000),
    ('2026-02-14 15:45:00', 'pipeline_run', 'airflow', 'ENG', 'dag', 'dag_dbt_transform', 120000),
    ('2026-02-15 09:00:00', 'dashboard_view', 'alice.finance', 'FIN', 'dashboard', 'revenue-overview', 1050),
    ('2026-02-15 09:10:00', 'dashboard_view', 'bob.hr', 'HR', 'dashboard', 'headcount-report', 780),
    ('2026-02-15 09:30:00', 'login', 'carol.engineering', 'ENG', 'auth', 'keycloak', 350),
    ('2026-02-15 10:00:00', 'dashboard_view', 'dave.executive', 'EXEC', 'dashboard', 'executive-summary', 680);
