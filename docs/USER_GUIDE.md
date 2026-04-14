# OpenInsight Platform — User Guide

> **Audience:** Business analysts, data analysts, data engineers, and BI consumers.
> **Prerequisite:** The platform is running (either locally via `docker compose` or on a Kubernetes cluster).

---

## Platform Status

| Component | Status | Notes |
|-----------|--------|-------|
| PostgreSQL, ClickHouse, Redis, Redpanda | **Live** | Core data stack |
| Keycloak (SSO) | **Live** | All logins go through Keycloak OIDC |
| Superset (dashboards, SQL Lab) | **Live** | Connected to ClickHouse, SSO wired |
| Apache Hop (ETL) | **Live** | Hop Web at :8090, sample pipeline included |
| dbt (transforms) | **Live** | Staging views + mart tables materialized |
| Kafka→ClickHouse streaming | **Live** | Kafka Engine tables auto-ingest from Redpanda |
| Airflow (orchestration) | Planned | Phase 2 |
| Trino (federation) | Planned | Phase 2 |
| Cube (semantic layer) | Planned | Phase 3 |
| Row-level security | Planned | Phase 3 (requires Cube + Keycloak JWT groups) |

---

## What Is OpenInsight?

OpenInsight is a business intelligence platform that lets your organization collect data from multiple sources, transform it into meaningful metrics, and explore it through interactive dashboards — all without depending on proprietary tools like Power BI or Tableau.

It's built from open-source components, which means your data stays on your infrastructure, there are no per-user license fees, and everything is auditable.

---

## Quick Start: Your First 10 Minutes

### Step 1 — Log In

Open your browser and go to the Superset URL (locally: `http://localhost:8088`).

You'll be redirected to the Keycloak login page. Enter your credentials — your IT admin will have created an account for you. If your organization uses Active Directory or LDAP, your normal corporate password works here.

After login, you land on the Superset home screen. You're authenticated across the entire platform with that single login — Superset, Cube API, Airflow (if you have access), and any embedded dashboards all recognize you.

**Local dev test users:**

| User | Password | Superset role | Group |
|------|----------|---------------|-------|
| alice.finance | Test123!DevOps | Alpha (SQL Lab + dashboards) | Finance |
| bob.hr | Test123!DevOps | Alpha | HR |
| eve.viewer | Test123!DevOps | Gamma (view only) | Finance |
| dave.executive | Test123!DevOps | Admin | Executive |
| carol.engineering | Test123!DevOps | Alpha | Engineering |

Fallback login (if Keycloak is down): `http://localhost:8088/login/` — admin / admin.

### Step 2 — Browse Existing Dashboards

Click **Dashboards** in the top navigation. You'll see all dashboards you have permission to view. Dashboards are organized by the data domain they belong to (Sales, HR, Finance, etc.).

Click any dashboard to open it. You can:

- **Filter data** using the filter bar at the top. Filters apply across all charts on the dashboard.
- **Drill down** by clicking on chart elements (bars, slices, data points) to see more granular data.
- **Adjust time ranges** using the time filter — most dashboards default to the last 30 days.
- **Download** individual charts as images or CSV files by clicking the three-dot menu on any chart.

### Step 3 — Ask a Question with SQL Lab

If you have the **Alpha** role or higher, you can write SQL queries directly. Go to **SQL Lab** in the top navigation.

Select the **ClickHouse** database connection for analytics data. Write your query and click **Run**.

Results appear in a table below. From there you can:

- **Visualize** the result by clicking "Create Chart" — this opens the chart builder with your query pre-loaded.
- **Download** results as CSV.
- **Save** the query for later reuse.

**Available tables (current seed data):**

| Table | Type | Rows | Description |
|-------|------|------|-------------|
| `fct_sales` | Fact | 56 | Sales transactions |
| `fct_events` | Fact | 32 | Platform usage events |
| `stg_sales` | View | — | Staging view over fct_sales |
| `stg_events` | View | — | Staging view over fct_events |
| `dim_customers` | Table | 30 | Customer dimension (sourced from PostgreSQL) |

---

## Understanding the Data Flow

When you look at a dashboard, the data has traveled through several stages to reach you. Understanding this helps you interpret freshness and troubleshoot issues.

```
Your data sources         What happens                  What you see
─────────────────         ──────────────                ────────────

ERP, CRM, APIs    →    Apache Hop extracts data    →   (you don't see this)
                        and sends it to Kafka

Kafka topics      →    ClickHouse ingests in        →   (you don't see this)
                        near-real-time (<5 seconds)

ClickHouse        →    dbt transforms raw data      →   (you don't see this)
                        into clean dimensions
                        and fact tables

Transformed       →    Cube defines business         →   This is what powers
tables                  metrics (revenue, counts,         your dashboards
                        averages) and caches them         [planned — Phase 3]

Cube API          →    Superset renders charts       →   This is what you see
                        and dashboards                    in your browser
```

> **Current state:** Superset queries ClickHouse directly. Once Cube is deployed (Phase 3), it will sit between ClickHouse and Superset as a semantic/caching layer.

**Data freshness:** Kafka→ClickHouse streaming is near-real-time (<5s). dbt transforms run on demand (`cd dbt && dbt run`). Once Airflow is deployed, transforms will run on a schedule. Cube-cached queries will refresh on a configurable interval (typically 15 minutes).

---

## Common BI Use Cases

### Use Case 1: Sales Performance Dashboard

**Who uses it:** Sales managers, executives, finance team.

**What it shows:** Revenue by region, product category, and time period. Month-over-month trends, top customers, and sales pipeline health.

**How it works:** Sales transactions flow from your ERP/CRM into ClickHouse's `fct_sales` table. dbt transforms join sales data with customer dimensions (region, department, product category) to create analytics-ready tables. Once deployed, Cube will define metrics like `total_revenue`, `average_order_value`, and `sales_count` with pre-computed aggregations for fast response.

**Row-level security** *(planned — Phase 3):* A user in the Finance department sees all sales data. A user in the Sales department sees only their region's data. This will be automatic — Cube reads your group membership from your login token and filters accordingly.

**Example query in SQL Lab:**
```sql
SELECT
    region_code,
    sum(total_amount) AS revenue,
    count(*) AS order_count,
    avg(total_amount) AS avg_order_value
FROM fct_sales
GROUP BY region_code
ORDER BY revenue DESC
```

### Use Case 2: Operational Metrics & Platform Usage

**Who uses it:** Engineering leads, platform administrators, data stewards.

**What it shows:** How the platform itself is being used — dashboard views, query execution times, API calls, pipeline runs. Helps identify popular dashboards, slow queries, and adoption trends.

**How it works:** Usage events are captured in `fct_events` — every dashboard view, query execution, API call, and pipeline run generates an event record. These flow through Kafka into ClickHouse in near-real-time.

**Example query:**
```sql
SELECT
    event_type,
    department_code,
    count(*) AS event_count,
    avg(duration_ms) AS avg_duration_ms
FROM fct_events
WHERE event_timestamp >= now() - INTERVAL 7 DAY
GROUP BY event_type, department_code
ORDER BY event_count DESC
```

### Use Case 3: Cross-Source Analysis (Federated Queries)

> **Status:** Planned — requires Trino (Phase 2).

**Who uses it:** Data analysts who need to combine data from multiple databases.

**What it shows:** Any analysis that requires joining ClickHouse analytics data with PostgreSQL operational data or external sources.

**How it works:** Trino acts as a federation layer — it can query ClickHouse, PostgreSQL, and other connected databases in a single SQL statement. You write one query, and Trino figures out where each table lives and joins the results.

**Example:** Joining ClickHouse sales facts with PostgreSQL customer details:
```sql
-- This runs in Trino (SQL Lab, Trino connection)
SELECT
    c.company_name,
    c.tier,
    r.region_name,
    sum(s.total_amount) AS total_revenue
FROM clickhouse.openinsight.fct_sales s
JOIN postgresql.openinsight.customers c
    ON s.customer_id = c.customer_id
JOIN postgresql.openinsight.regions r
    ON c.region_code = r.region_code
GROUP BY c.company_name, c.tier, r.region_name
ORDER BY total_revenue DESC
```

### Use Case 4: Scheduled Reports & Alerts

> **Status:** Planned — requires Superset SMTP configuration and Airflow.

**Who uses it:** Managers who want regular updates without logging in.

**What it shows:** Dashboard snapshots delivered to email or Slack on a schedule. Alerts when metrics cross thresholds (e.g., daily revenue drops below a target).

**How it works:** Superset's reporting feature takes a screenshot of a dashboard or chart at a scheduled interval and delivers it via email or Slack. Alerts monitor a SQL query and trigger a notification when the result meets a condition.

**Setup (requires Alpha role):**
1. Open the dashboard or chart you want to report on.
2. Click the three-dot menu → **Set up a scheduled report**.
3. Choose frequency (daily, weekly, monthly), recipients, and delivery method.
4. For alerts: define a SQL condition (e.g., `SELECT count(*) FROM fct_sales WHERE sale_date = today() AND total_amount < 0` → triggers if any negative sales appear).

### Use Case 5: Embedded Analytics

> **Status:** Planned — requires Cube API (Phase 3).

**Who uses it:** Product teams who want to embed dashboards into internal applications.

**What it shows:** OpenInsight dashboards rendered inside your own web applications (intranets, customer portals, internal tools).

**How it works:** Superset dashboards can be embedded via iframe. The embedded dashboard respects the same row-level security as the standalone version — the user's JWT token is passed through, and they only see data they're authorized to access.

**For developers:** Use the Cube REST or GraphQL API directly to build custom visualizations. The API returns pre-aggregated metrics with sub-second response times.

```bash
# Example: Query Cube API for sales metrics
curl -H "Authorization: Bearer <your-jwt-token>" \
     "http://localhost:4000/cubejs-api/v1/load?query={
       \"measures\": [\"Sales.totalRevenue\", \"Sales.orderCount\"],
       \"dimensions\": [\"Sales.regionCode\"],
       \"timeDimensions\": [{
         \"dimension\": \"Sales.saleDate\",
         \"granularity\": \"month\"
       }]
     }"
```

---

## Roles & What You Can Do

Your access level depends on the role assigned to you in Keycloak. Here's what each role unlocks:

| Role | Superset | SQL Lab | Create Dashboards | Cube API | Airflow | Typical User |
|---|---|---|---|---|---|---|
| **Gamma** (viewer) | View published dashboards | No | No | Read-only queries | No | Executives, occasional consumers |
| **Alpha** (data-analyst) | Full dashboard access | Yes | Yes | Full query access | No | Business analysts, finance team |
| **data-engineer** | Full dashboard access | Yes | Yes | Full access + admin | View & trigger DAGs | Analytics engineers, ETL developers |
| **Admin** | Everything | Everything | Everything | Everything | Everything | Platform administrators |

Keycloak client roles (`superset-admin`, `superset-alpha`, `superset-gamma`) are synced to Superset roles at each login.

**Row-level security** *(planned — Phase 3)* is separate from roles. Your role determines *what features* you can use. Your group membership (Finance, HR, Engineering, etc.) determines *what data* you can see. A data-analyst in Finance and a data-analyst in HR have the same features but see different rows.

---

## How Data Gets In: A Guide for Data Engineers

If you have the **data-engineer** role, you're responsible for getting data into the platform. Here's how each ingestion path works.

### Path 1: Batch Ingestion via Apache Hop

Open Hop Web at `http://localhost:8090`. Hop provides a visual pipeline designer where you drag and drop transforms to build ETL workflows.

A typical pipeline: **Read from source** (database, API, file) → **Add metadata** (timestamps, source system tags) → **Serialize to JSON** → **Publish to Kafka topic**.

The platform ships with a sample pipeline (`sample-ingest-to-kafka.hpl`) that demonstrates this pattern: it reads customer data from PostgreSQL, enriches it with metadata, and publishes JSON messages to the `ingest.raw.dimensions` Kafka topic.

**Rule:** Hop does E+L only. All transformations go through dbt.

### Path 2: Real-Time Streaming via Kafka

If your source system can produce Kafka messages directly (many modern applications can), data flows into ClickHouse automatically. The platform has pre-configured Kafka Engine tables and materialized views that consume from topics and insert into fact tables.

The topics are:
- `ingest.raw.transactions` → routes to `fct_sales`
- `ingest.raw.events` → routes to `fct_events`
- `ingest.raw.dimensions` → for dimension/reference data updates

Failed messages land in dead-letter queues (`dlq.ingest`, `dlq.events`) for investigation.

### Path 3: Transformation via dbt

After data lands in ClickHouse, dbt handles the transformation layer. Models follow a naming convention:

- `stg_*` — Staging models. Thin views over raw source tables. Minimal transformation, mostly renaming and type casting.
- `int_*` — Intermediate models. Business logic joins and calculations that serve as building blocks.
- `dim_*` — Dimension tables. Customer, product, region lookups. Slowly changing.
- `fct_*` — Fact tables. Transactional/event data. Append-only, time-partitioned.

To run transformations: `cd dbt && dbt run`. To validate data quality: `dbt test`.

### Path 4: Orchestration via Airflow

> **Status:** Planned — Phase 2.

Airflow schedules and monitors all of the above. Typical DAGs:

- **dag_hop_ingest**: Triggers Hop pipelines on a schedule (e.g., hourly for batch sources).
- **dag_dbt_transform**: Runs `dbt run` followed by `dbt test` after new data arrives.
- **dag_data_quality**: Runs validation checks and alerts on failures.

Access Airflow at `http://localhost:8081`. You can view DAG run history, trigger manual runs, and inspect logs for failed tasks.

---

## Troubleshooting

**"Dashboard shows no data"**
- Check that seed data was loaded (`./scripts/seed.sh`) and dbt was run (`cd dbt && dbt run`).
- Check your group membership — you may not have access to the dataset. Contact your admin to verify your Keycloak groups.
- Check data freshness — the pipeline may not have run yet. Once Airflow is deployed, check the last successful DAG run.

**"Query is slow"**
- Always include a date filter on fact tables. ClickHouse queries on fact tables should be sub-second for typical aggregations. If a query takes more than 5 seconds, check if it's scanning a very large time range.
- Once deployed, Cube-cached queries should respond in under 200ms. If Cube is slow, the pre-aggregation may need refreshing.

**"I can see a dashboard but some charts show 'Access Denied'"**
- Individual charts may query datasets you don't have group access to. This is row-level security working correctly. Contact your data steward if you believe your access should be broader.

**"I can't access SQL Lab"**
- SQL Lab requires the **Alpha** role or higher. If you're a **Gamma** (viewer), you can only see published dashboards. Contact your admin to upgrade your role if needed.

**"Login fails / redirect loop"**
- Verify Keycloak is healthy: `curl http://localhost:8080/health/ready`.
- Check that nothing else on your machine is using port 8080 (e.g., Tomcat).

---

## Service URLs (Local Dev)

| Service | URL | Purpose |
|---------|-----|---------|
| Superset | http://localhost:8088 | Dashboards, SQL Lab |
| Keycloak | http://localhost:8080 | User management, SSO |
| Hop Web | http://localhost:8090 | ETL pipeline designer |
| Redpanda Console | http://localhost:8888 | Kafka topic inspection |
| ClickHouse HTTP | http://localhost:8123 | Direct ClickHouse queries |
| Cube *(planned)* | http://localhost:4000 | Semantic layer API |
| Trino *(planned)* | http://localhost:8085 | Federated SQL |
| Airflow *(planned)* | http://localhost:8081 | Orchestration UI |

---

## Getting Help

- **Platform issues** (login problems, service outages): Contact the platform engineering team.
- **Data questions** (incorrect numbers, missing data, freshness concerns): Contact the data engineering team or your data steward.
- **Dashboard requests** (new charts, custom reports): Contact the analytics engineering team.
- **Access requests** (role upgrades, new group membership): Submit through your organization's IT access management process — your admin will update your Keycloak profile.
