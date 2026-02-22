-- OpenInsight PostgreSQL Seed Data
-- Small dimension/reference tables that live in OLTP storage
-- These map to dbt models: dim_department, dim_product_category, dim_region

BEGIN;

-- Departments (maps to Keycloak groups for RLS testing)
CREATE TABLE IF NOT EXISTS departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    code VARCHAR(20) NOT NULL UNIQUE,
    cost_center VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO departments (name, code, cost_center) VALUES
    ('Finance', 'FIN', 'CC-100'),
    ('Human Resources', 'HR', 'CC-200'),
    ('Engineering', 'ENG', 'CC-300'),
    ('Sales', 'SALES', 'CC-400'),
    ('Marketing', 'MKT', 'CC-500'),
    ('Executive', 'EXEC', 'CC-001')
ON CONFLICT (code) DO NOTHING;

-- Product categories
CREATE TABLE IF NOT EXISTS product_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    parent_id INTEGER REFERENCES product_categories(id),
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO product_categories (id, name, parent_id) VALUES
    (1, 'Software', NULL),
    (2, 'Hardware', NULL),
    (3, 'Services', NULL),
    (4, 'SaaS Subscriptions', 1),
    (5, 'On-Premise Licenses', 1),
    (6, 'Servers', 2),
    (7, 'Networking', 2),
    (8, 'Consulting', 3),
    (9, 'Support Plans', 3)
ON CONFLICT (id) DO NOTHING;

-- Regions
CREATE TABLE IF NOT EXISTS regions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    code VARCHAR(10) NOT NULL UNIQUE,
    timezone VARCHAR(50) NOT NULL
);

INSERT INTO regions (name, code, timezone) VALUES
    ('North America', 'NA', 'America/New_York'),
    ('Europe', 'EU', 'Europe/Berlin'),
    ('Asia Pacific', 'APAC', 'Asia/Tokyo'),
    ('Latin America', 'LATAM', 'America/Sao_Paulo'),
    ('Middle East & Africa', 'MEA', 'Asia/Dubai')
ON CONFLICT (code) DO NOTHING;

-- Customers (for joining with ClickHouse fact tables via Trino)
CREATE TABLE IF NOT EXISTS customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    email VARCHAR(200),
    region_id INTEGER REFERENCES regions(id),
    department_id INTEGER REFERENCES departments(id),
    tier VARCHAR(20) DEFAULT 'standard',
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO customers (name, email, region_id, department_id, tier) VALUES
    ('Acme Corp', 'contact@acme.example', 1, 4, 'enterprise'),
    ('GlobalTech GmbH', 'info@globaltech.example', 2, 4, 'enterprise'),
    ('Sakura Industries', 'sales@sakura.example', 3, 4, 'premium'),
    ('LatAm Solutions', 'hello@latam.example', 4, 4, 'standard'),
    ('Desert Dynamics', 'ops@desert.example', 5, 4, 'standard'),
    ('Pinnacle Software', 'dev@pinnacle.example', 1, 3, 'premium'),
    ('Nordic Analytics', 'data@nordic.example', 2, 1, 'enterprise'),
    ('Pacific Ventures', 'invest@pacific.example', 3, 5, 'standard'),
    ('Summit Consulting', 'consult@summit.example', 1, 3, 'premium'),
    ('Atlas Manufacturing', 'orders@atlas.example', 2, 4, 'enterprise')
ON CONFLICT DO NOTHING;

COMMIT;
