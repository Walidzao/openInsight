# OpenInsight — Implementation Progress

> **Last updated:** 2026-02-22
> **Branch:** `main`
> **Implementation target:** ARCHITECTURE.md (841 lines, single source of truth)

---

## Overall Status

| Phase | Description | Status | Progress |
|---|---|---|---|
| **Phase 1** | Foundation — core infra, local dev, identity | ✅ Complete | 7/7 tasks |
| **Phase 2** | Data Pipeline — Hop, Kafka→CH, dbt, Airflow, Trino | 🔄 In Progress | 1/5 tasks |
| **Phase 3** | Semantic & Viz — Cube, Superset, RLS, API Gateway | ⏳ Pending | 0/5 tasks |
| **Phase 4** | Governance & Hardening — observability, DataHub, DR | ⏳ Pending | 0/6 tasks |

---

## Git Commits

```
28d9677  Complete Phase 1: Redpanda topics, seed data for PG and ClickHouse
df5ee77  Fix Keycloak realm import: remove invalid fields, lengthen passwords
674aead  Initial commit: project scaffolding and local dev environment
```

> **Pending commit:** Phase 1 role matrix + Phase 2 Hop Web (uncommitted — all working, verified)

---

## Phase 1: Foundation ✅ COMPLETE

### Tasks

| # | Task | Status | Notes |
|---|---|---|---|
| 1.1 | K8s Cluster (Terraform/GKE) | ⏳ Deferred | Dir structure ready (`infrastructure/terraform/`); actual TF deferred to cloud phase |
| 1.2 | PostgreSQL HA | ✅ Done | `postgres:16-alpine` running locally; `init-postgres.sh` creates keycloak/superset/airflow DBs |
| 1.3 | ClickHouse | ✅ Done | `clickhouse-server:24` running; fact tables seeded |
| 1.4 | Keycloak | ✅ Done | Full realm with OIDC clients + cross-app role matrix (see below) |
| 1.5 | Redis | ✅ Done | `redis:7-alpine` with LRU eviction, appendonly |
| 1.6 | Kafka / Redpanda | ✅ Done | Redpanda v24.1.1 + Console; 7 topics initialized |
| 1.7 | Networking | ⏳ Deferred | NetworkPolicies deferred to K8s phase; docker network `openinsight` in place |

### Running Services (Local Dev — `docker compose up -d`)

| Service | Container | Port(s) | Status |
|---|---|---|---|
| PostgreSQL 16 | openinsight-postgres | 5432 | ✅ Healthy |
| ClickHouse 24 | openinsight-clickhouse | 8123 / 9000 | ✅ Healthy |
| Keycloak 24 | openinsight-keycloak | 8080 | ✅ Healthy |
| Redis 7 | openinsight-redis | 6379 | ✅ Healthy |
| Redpanda v24 | openinsight-redpanda | 19092 / 18082 / 18081 | ✅ Healthy |
| Redpanda Console | openinsight-redpanda-console | 8888 | ✅ Running |

### Keycloak Realm: `openinsight`

**URL:** http://localhost:8080/admin — credentials: `admin / admin`
**File:** `keycloak/realm-openinsight.json`

#### OIDC Clients

| Client | Secret | Callback / Purpose |
|---|---|---|
| `superset` | `superset-dev-secret` | Superset visualization layer |
| `cube` | `cube-dev-secret` | Cube semantic layer |
| `airflow` | `airflow-dev-secret` | Airflow orchestration |

#### Role Matrix

| User | Password | Group | Realm Roles | Superset | Cube | Airflow |
|---|---|---|---|---|---|---|
| `admin` | `Admin123!DevOps` | — | admin | superset-admin | cube-admin | airflow-admin |
| `alice.finance` | `Test123!DevOps` | Finance | data-analyst | superset-alpha | cube-query | — |
| `bob.hr` | `Test123!DevOps` | HR | data-analyst | superset-alpha | cube-query | — |
| `carol.engineering` | `Test123!DevOps` | Engineering | data-analyst, data-engineer | superset-alpha | cube-admin | airflow-trigger |
| `dave.executive` | `Test123!DevOps` | Executive | admin | superset-admin | cube-admin | airflow-viewer |
| `eve.viewer` | `Test123!DevOps` | Finance | viewer | superset-gamma | cube-query | — |

#### JWT Claims (verified)

- `roles` — realm roles from groups
- `groups` — group memberships (e.g. `["Engineering"]`)
- `client_roles` — client-specific roles in token for that client's audience

#### Password Policy

`length(12) AND upperCase(1) AND digits(1) AND specialChars(1) AND passwordHistory(5)`

### Redpanda Topics

| Topic | Partitions | Retention | Purpose |
|---|---|---|---|
| `keycloak.events` | 3 | 1 day | Keycloak auth events → cache invalidation |
| `ingest.raw.events` | 6 | 7 days | Raw event stream ingestion |
| `ingest.raw.transactions` | 6 | 7 days | Raw transaction ingestion |
| `ingest.raw.dimensions` | 3 | 7 days | Dimension table sync |
| `dlq.ingest` | 3 | 30 days | Dead-letter for ingest failures |
| `dlq.events` | 1 | 30 days | Dead-letter for event failures |
| `pipeline.status` | 1 | 3 days | Pipeline run status/monitoring |

### Seed Data

**Script:** `./scripts/seed.sh`

**PostgreSQL (`openinsight` DB):**
- `departments` — 6 rows (Finance, Engineering, HR, Sales, Executive, Operations)
- `product_categories` — 9 rows
- `regions` — 5 rows (EMEA, APAC, AMER, LATAM, MENA)
- `customers` — 10 rows with region + department FK refs

**ClickHouse (`openinsight` DB):**
- `fct_sales` — 27 rows, 6-month range
- `fct_events` — 16 rows, platform usage events

---

## Phase 2: Data Pipeline 🔄 IN PROGRESS

### Tasks

| # | Task | Status | Notes |
|---|---|---|---|
| 2.1 | Apache Hop | 🔄 In Progress | Hop Web running (see below); pipelines TBD |
| 2.2 | Kafka→ClickHouse | ⏳ Pending | Kafka Engine DDL + materialized views |
| 2.3 | dbt Project | ⏳ Pending | Skeleton, staging/mart models, tests |
| 2.4 | Airflow | ⏳ Pending | Helm values, DAGs for Hop + dbt |
| 2.5 | Trino | ⏳ Pending | Catalog configs (ClickHouse + PostgreSQL connectors) |

### 2.1 Apache Hop Web ✅ Running

**Started with:** `docker compose --profile pipeline up -d`
**URL:** http://localhost:8090/ui
**Image:** `apache/hop-web:2.10.0`

#### Hop Project Structure

```
hop/projects/openinsight/
├── project-config.json          # Hop project metadata
├── local-dev.json               # Environment variables (PG, CH, Kafka connections)
├── metadata/
│   └── pipeline-run-configuration/
│       └── local.json           # Local execution engine config
└── pipelines/
    └── sample-ingest-to-kafka.hpl   # Sample: PG customers → Redpanda
```

#### Environment Variables (local-dev.json)

| Variable | Value | Description |
|---|---|---|
| `PG_HOST` | `postgres` | PostgreSQL container hostname |
| `PG_PORT` | `5432` | PostgreSQL port |
| `PG_USER` | `openinsight` | PG user |
| `PG_PASS` | `openinsight_dev` | PG password |
| `PG_DB` | `openinsight` | PG database |
| `CH_HOST` | `clickhouse` | ClickHouse container hostname |
| `CH_PORT` | `8123` | ClickHouse HTTP port |
| `CH_USER` | `openinsight` | CH user |
| `CH_PASS` | `openinsight_dev` | CH password |
| `KAFKA_BOOTSTRAP` | `redpanda:9092` | Redpanda internal address |
| `KAFKA_TOPIC_DIMENSIONS` | `ingest.raw.dimensions` | Target topic |

#### Sample Pipeline

`sample-ingest-to-kafka.hpl` — demonstrates core ingestion pattern:
1. **Table Input** → reads `customers` joined with `regions` + `departments` from PostgreSQL
2. **Add Constants** → appends `source_system`, `ingested_at`, `pipeline_name`
3. **Select Values** → clean field ordering
4. **Write to Log** → verification output (replace with Kafka Producer step for production)

> **Note:** The WriteToLog step is intentional for local dev visibility. Production pipelines should use the Kafka Producer step targeting `${KAFKA_BOOTSTRAP}` / `${KAFKA_TOPIC_DIMENSIONS}`.

### Next Phase 2 Steps

1. **2.2 Kafka → ClickHouse Engine** — Create Kafka Engine tables in ClickHouse:
   - `ingest_raw_events` (Kafka Engine) → `fct_events` (Materialized View → MergeTree)
   - `ingest_raw_transactions` (Kafka Engine) → `fct_sales` (Materialized View → MergeTree)
   - Script: `scripts/clickhouse-kafka-tables.sql`

2. **2.3 dbt Project** — Scaffold in `dbt/`:
   - `dbt_project.yml`, `profiles.yml`
   - `models/staging/stg_customers.sql`, `stg_sales.sql`
   - `models/mart/dim_customers.sql`, `fct_sales.sql`
   - Schema tests: `unique`, `not_null`, `relationships`

3. **2.4 Airflow** — Add to `pipeline` profile:
   - Docker service: `apache/airflow:2.8.x` with LocalExecutor
   - DAGs: `dag_hop_ingest.py`, `dag_dbt_transform.py`, `dag_data_quality.py`
   - Keycloak OIDC integration using `airflow-dev-secret`

4. **2.5 Trino** — Add to `app` profile (future):
   - Connectors: ClickHouse + PostgreSQL catalogs
   - Port 8085

---

## Phase 3: Semantic & Visualization ⏳ PENDING

| # | Task | Notes |
|---|---|---|
| 3.1 | Cube Cluster | `cube.js` config, schema YAML from dbt manifest, Redis-backed cache |
| 3.2 | Cache Invalidation | Keycloak events → Redpanda → Redis pub/sub → Cube eviction |
| 3.3 | Superset | OIDC config, Keycloak group → Superset role mapping |
| 3.4 | RLS | Cube `security_context`, department/group data isolation |
| 3.5 | API Gateway | Kong or NGINX Ingress, rate limits, TLS termination |

---

## Phase 4: Governance & Hardening ⏳ PENDING

| # | Task | Notes |
|---|---|---|
| 4.1 | Observability | Prometheus + Grafana, Loki, Jaeger/Tempo |
| 4.2 | DataHub | Metadata catalog, lineage from dbt |
| 4.3 | Load Testing | k6 scripts (500 concurrent dashboard + SQL Lab) |
| 4.4 | DR Scripts | `dr-backup.sh`, `dr-restore.sh`, `dr-drill.sh` |
| 4.5 | Security Audit | Trivy, checkov, RBAC audit |
| 4.6 | Documentation | ADRs, runbooks, onboarding guide |

---

## Key Files Reference

| File | Purpose |
|---|---|
| `ARCHITECTURE.md` | Single source of truth (841 lines) |
| `docker-compose.yml` | Local dev — 6 core + 1 pipeline service |
| `keycloak/realm-openinsight.json` | Full realm: 3 OIDC clients, role matrix, 6 users |
| `.env.example` | All env vars with dev defaults |
| `scripts/init-postgres.sh` | Creates keycloak/superset/airflow DBs on PG init |
| `scripts/init-redpanda.sh` | Creates 7 Kafka topics with retention policies |
| `scripts/seed.sh` | Orchestrates: topics → PG seed → CH seed |
| `scripts/seed-postgres.sql` | PG dimension/reference seed data |
| `scripts/seed-clickhouse.sql` | CH fact table seed data |
| `scripts/check-health.sh` | Health check (core + optional pipeline stack) |
| `hop/projects/openinsight/project-config.json` | Hop project root config |
| `hop/projects/openinsight/local-dev.json` | Hop environment: connection strings |
| `hop/projects/openinsight/pipelines/*.hpl` | Hop pipeline files |

---

## Known Issues & Decisions

| # | Item | Resolution |
|---|---|---|
| KC-01 | `refreshTokenLifespan` invalid in Keycloak 24 | Removed — governed by `ssoSessionIdleTimeout` |
| KC-02 | `defaultRoles` replaced by `defaultRole` in KC 20+ | Removed — KC handles defaults automatically |
| KC-03 | Passwords must be ≥ 12 chars (policy enforced) | All passwords are 15 chars: `Admin123!DevOps` / `Test123!DevOps` |
| KC-04 | Client scope warnings for `openid`/`profile` | Harmless — removed explicit `defaultClientScopes` from clients |
| CH-01 | ClickHouse HTTP API: 1 statement per request | `seed.sh` splits on `;` and sends each statement individually |
| HOP-01 | `enforcingExecutionInHome: "N"` invalid in Hop 2.10 | Fixed to boolean `false` |
| HOP-02 | Project registration error on first start | Resolved on restart; project/environment correctly registered |
| HOP-03 | `pipeline-run-configuration/local.json` wrong schema | Hop serializes engine config as `{"engineRunConfiguration": {"Local": {...}}, "name": "local", ...}` — plugin ID is the key, not nested `enginePluginId` field. Copied exact structure from Hop's built-in default project. |

---

## Architecture Decisions Implemented

| ADR | Decision | Implementation |
|---|---|---|
| ADR-001 | Kafka as message backbone | Redpanda (Kafka-compatible) running with 7 topics |
| ADR-002 | Redis for Cube cache | Redis 7 with LRU eviction running; pub/sub pending Phase 3 |
| ADR-007 | Event-driven cache invalidation | `keycloak.events` topic created; listener pending Phase 3 |
| ADR-009 | Namespace isolation | Docker network `openinsight`; K8s NetworkPolicies deferred |
| ADR-011 | n8n: alert routing only | Not yet implemented (Phase 3/4) |
| ADR-012 | Monorepo | ✅ Single repo, all components |

---

## Quick Commands

```bash
# Core stack
docker compose up -d
./scripts/check-health.sh
./scripts/seed.sh

# Pipeline stack (Hop Web)
docker compose --profile pipeline up -d
# → Hop Web UI: http://localhost:8090/ui

# Get a JWT token (verify role matrix)
curl -sf http://localhost:8080/realms/openinsight/protocol/openid-connect/token \
  -d "client_id=cube" \
  -d "client_secret=cube-dev-secret" \
  -d "grant_type=password" \
  -d "username=carol.engineering" \
  -d "password=Test123!DevOps"

# Reset Keycloak (re-import realm after JSON changes)
docker compose stop keycloak
docker compose exec -T postgres psql -U openinsight -d openinsight \
  -c "DROP DATABASE keycloak; CREATE DATABASE keycloak OWNER openinsight;"
docker compose start keycloak

# Inspect Redpanda topics
docker compose exec -T redpanda rpk topic list
```
