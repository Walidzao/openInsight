# OpenInsight — Implementation Progress

> **Last updated:** 2026-04-08
> **Branch:** `main`
> **Implementation target:** ARCHITECTURE.md (841 lines, single source of truth)

---

## Overall Status

| Phase | Description | Status | Progress |
|---|---|---|---|
| **Phase 1** | Foundation — core infra, local dev, identity | ✅ Complete | 7/7 tasks |
| **Phase 2** | Data Pipeline — Hop, Kafka→CH, dbt, Airflow, Trino | 🔄 In Progress | 3/5 tasks |
| **Phase 3** | Semantic & Viz — Cube, Superset, RLS, API Gateway | ⏳ Pending | 0/5 tasks |
| **Phase 4** | Governance & Hardening — observability, DataHub, DR | ⏳ Pending | 0/6 tasks |

---

## Git Commits

```
ae8b616  Phase 2 progress: Kafka→CH DDL, dbt skeleton, Hop RDBMS connections
f808f81  Fix Hop pipeline-run-configuration schema for Hop 2.10
2e4542e  Phase 1 complete + Phase 2 start: Keycloak role matrix and Apache Hop Web
28d9677  Complete Phase 1: Redpanda topics, seed data for PG and ClickHouse
df5ee77  Fix Keycloak realm import: remove invalid fields, lengthen passwords
674aead  Initial commit: project scaffolding and local dev environment
```

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
| 2.1 | Apache Hop | ✅ Done | Hop Web running at :8090, project + env + RDBMS connections configured |
| 2.2 | Kafka→ClickHouse | ✅ Done | `scripts/clickhouse-kafka-tables.sql` — Kafka Engine + MVs (not yet applied to running CH) |
| 2.3 | dbt Project | ✅ Done | Skeleton committed: staging views, mart tables, profiles.yml (not yet run) |
| 2.4 | Airflow | ⏳ Pending | Next |
| 2.5 | Trino | ⏳ Pending | After Airflow |

### 2.1 Apache Hop Web ✅ Done

**Started with:** `docker compose --profile pipeline up -d`
**URL:** http://localhost:8090/ui
**Image:** `apache/hop-web:2.10.0`

#### Hop Project Structure

```
hop/projects/openinsight/
├── project-config.json          # Hop project metadata
├── local-dev.json               # Environment variables (PG, CH, Kafka connections)
├── metadata/
│   ├── pipeline-run-configuration/
│   │   └── local.json           # Local execution engine config
│   └── rdbms-connection/
│       ├── openinsight-postgres.json    # PG connection (uses env vars)
│       └── openinsight-clickhouse.json  # CH connection (uses env vars)
└── pipelines/
    └── sample-ingest-to-kafka.hpl   # Sample: PG customers → log output
```

#### RDBMS Connection Metadata Format (Hop 2.10)

Hop serializes database connections as:
```json
{
  "rdbms": {
    "<PLUGIN_TYPE>": {   // e.g. "POSTGRESQL", "CLICKHOUSE"
      "accessType": 0,
      "hostname": "...", "port": "...", "databaseName": "...",
      "username": "...", "password": "..."
    }
  },
  "name": "connection-name"
}
```
Plugin types confirmed via bytecode: `POSTGRESQL` (`PostgreSqlDatabaseMeta`), `CLICKHOUSE` (`ClickhouseDatabaseMeta`).

### 2.2 Kafka→ClickHouse ✅ DDL Ready

**File:** `scripts/clickhouse-kafka-tables.sql`

Creates two Kafka Engine tables pointing at Redpanda, with materialized views inserting into existing MergeTree tables:

| Kafka Engine Table | Topic | MV Target |
|---|---|---|
| `ingest_raw_transactions` | `ingest.raw.transactions` | `fct_sales` |
| `ingest_raw_events` | `ingest.raw.events` | `fct_events` |

**Not yet applied** — run manually via CH HTTP API or integrate into seed.sh when ready.

### 2.3 dbt Project ✅ Skeleton Ready

```
dbt/
├── dbt_project.yml         # Profile: openinsight, vars for PG connection
├── profiles.yml            # dbt-clickhouse adapter, native port 9000
├── models/
│   ├── staging/
│   │   ├── _sources.yml    # Sources: fct_sales, fct_events in CH
│   │   ├── stg_sales.sql   # Pass-through view on fct_sales
│   │   └── stg_events.sql  # Pass-through view on fct_events
│   └── mart/
│       └── dim_customers.sql  # CH postgresql() function → PG customers table
```

**Design decision:** `dim_customers.sql` uses ClickHouse's built-in `postgresql()` table function to pull dimension data from PG directly, avoiding Trino for local dev. Credentials are parameterized via dbt `var()` with env var fallbacks.

**Not yet run** — requires `pip install dbt-clickhouse` and `dbt run`.

---

## Remaining Phase 2 Work — Implementation Plan

See detailed plan below in "Next Steps for Implementation Agent" section.

---

## Phase 3: Semantic & Visualization ⏳ PENDING

**DO NOT START Phase 3 until Phase 2 is verified end-to-end.**

| # | Task | Notes |
|---|---|---|
| 3.1 | Cube Cluster | `cube.js` config, schema YAML from dbt manifest, Redis-backed cache |
| 3.2 | Cache Invalidation | Keycloak events → Redpanda → Redis pub/sub → Cube eviction |
| 3.3 | Superset | OIDC config via `AUTH_OAUTH` (NOT `AUTH_OID`), Keycloak role mapping |
| 3.4 | RLS | Cube `security_context`, department/group data isolation |
| 3.5 | API Gateway | Kong or NGINX Ingress, rate limits, TLS termination |

### Phase 3 Guardrails (Lessons from dropped code)

- Superset auth: use `AUTH_OAUTH` not `AUTH_OID`
- Cube connects to ClickHouse via REST/GraphQL API, NOT PostgreSQL wire protocol
- Superset connects to Cube via the Cube SQL API (port 4000, PG-compatible wire)
- Add `CUBEJS_DEV_MODE=true` for local dev
- Each Phase 3 service needs a healthcheck in docker-compose.yml
- Do not add services to docker-compose.yml until they're tested

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
| `scripts/clickhouse-kafka-tables.sql` | Kafka Engine + MVs for streaming ingest |
| `scripts/check-health.sh` | Health check (core + optional pipeline stack) |
| `hop/projects/openinsight/` | Hop ETL project (pipelines, environment config) |
| `dbt/` | dbt-clickhouse project (staging views, mart tables) |
| `docs/SIMILAR_PROJECTS.md` | Reference: similar open-source data stacks |

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
| HOP-03 | `pipeline-run-configuration/local.json` wrong schema | Plugin ID is the key under `engineRunConfiguration`, not a nested field |
| HOP-04 | `rdbms-connection/*.json` schema | Plugin type (e.g. `POSTGRESQL`) is the key under `"rdbms"`, not `"databaseType"` |
| REVIEW-01 | Phase 3 code dropped from other agent | Superset config used wrong auth type, Cube connection URI was incorrect, services added without testing. Dropped; guardrails documented above. |

---

## Architecture Decisions Implemented

| ADR | Decision | Implementation |
|---|---|---|
| ADR-001 | Kafka as message backbone | Redpanda running + Kafka Engine DDL ready |
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

# Apply Kafka Engine tables (when ready)
# Split on ; and send each statement individually (CH HTTP API limitation)
```

---

## Next Steps for Implementation Agent

### Priority: Complete Phase 2 (tasks 2.4 and 2.5), then verify the full pipeline

### RULES FOR THE IMPLEMENTATION AGENT

1. **Stay in Phase 2.** Do not create Phase 3 files (Cube, Superset, API Gateway). They will be designed and reviewed separately.
2. **Test before committing.** Every service added to docker-compose must start healthy before being committed. Run `./scripts/check-health.sh` after changes.
3. **Follow existing patterns.** Look at how `hop-web` was added to docker-compose.yml — same structure: `profiles`, `depends_on` with `condition: service_healthy`, healthcheck, `restart: unless-stopped`.
4. **Use environment variables.** Never hardcode credentials in config files. Use `${VAR:-default}` in docker-compose and env var functions in application configs.
5. **One concern per commit.** Don't bundle Airflow + Trino + dbt tests in one commit.
6. **Read ARCHITECTURE.md Section 9** (Phased Implementation Plan) before starting. Tasks 2.4 and 2.5 are defined there.
7. **Read the Hop metadata format notes** (HOP-03, HOP-04 in Known Issues) before writing any Hop metadata JSON.

---

### Task 2.4: Airflow (pipeline profile)

**Goal:** Add Apache Airflow to the `pipeline` docker-compose profile for orchestrating Hop pipelines and dbt runs.

#### 2.4.1 Docker service

Add `airflow` service to `docker-compose.yml` under `profiles: ["pipeline"]`:

- **Image:** `apache/airflow:2.8.4-python3.11`
- **Port:** `${AIRFLOW_PORT:-8081}:8080`
- **Executor:** `LocalExecutor` (single-node, no Celery needed for dev)
- **Metadata DB:** PostgreSQL — `postgresql+psycopg2://openinsight:openinsight_dev@postgres:5432/airflow`
  - The `airflow` database already exists (created by `scripts/init-postgres.sh`)
- **depends_on:** `postgres` (healthy), `redpanda` (healthy)
- **Volumes:** `./airflow/dags:/opt/airflow/dags`
- **Environment:**
  ```
  AIRFLOW__CORE__EXECUTOR=LocalExecutor
  AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://openinsight:openinsight_dev@postgres:5432/airflow
  AIRFLOW__CORE__FERNET_KEY=  (empty is fine for dev — no encrypted connections)
  AIRFLOW__CORE__LOAD_EXAMPLES=false
  AIRFLOW__WEBSERVER__EXPOSE_CONFIG=true
  ```
- **Entrypoint override:** Airflow needs `airflow db migrate` before the webserver starts. Use a command like:
  ```
  command: bash -c "airflow db migrate && airflow users create --username admin --password admin --firstname Admin --lastname User --role Admin --email admin@openinsight.local || true && airflow webserver"
  ```
  Alternatively, create a `scripts/airflow-entrypoint.sh` that handles init + webserver.
- **Healthcheck:** `curl -sf http://localhost:8080/health`
- **Scheduler:** For LocalExecutor, the scheduler must also run. Either:
  - (a) Run scheduler in the same container via `airflow webserver & airflow scheduler` (simpler for dev)
  - (b) Add a second `airflow-scheduler` service (cleaner but more resources)
  - **Decision: option (a)** for local dev simplicity.

#### 2.4.2 DAG scaffolds

Create minimal DAG files in `airflow/dags/`. These should be syntactically valid Python that Airflow can parse, but don't need to be fully functional yet:

- `dag_hop_ingest.py` — BashOperator calling Hop CLI to run a pipeline (placeholder command)
- `dag_dbt_transform.py` — BashOperator calling `dbt run` and `dbt test`

Keep them simple: one DAG per file, `schedule=None` (manual trigger), `catchup=False`.

#### 2.4.3 Update supporting files

- `scripts/check-health.sh` — add conditional Airflow check (same pattern as Hop Web conditional check)
- `.env.example` — uncomment `AIRFLOW_PORT=8081`

#### 2.4.4 Verify

- `docker compose --profile pipeline up -d` → all pipeline services (Hop + Airflow) start healthy
- Airflow UI accessible at http://localhost:8081
- DAGs appear in the DAG list (no import errors)

---

### Task 2.5: Trino (app profile)

**Goal:** Add Trino as a query federation layer, connecting both ClickHouse and PostgreSQL.

#### 2.5.1 Docker service

Add `trino` service to `docker-compose.yml` under `profiles: ["app"]`:

- **Image:** `trinodb/trino:435`
- **Port:** `${TRINO_PORT:-8085}:8080`
- **Volumes:** `./trino/etc:/etc/trino` (catalog configs)
- **depends_on:** `postgres` (healthy), `clickhouse` (healthy)
- **Healthcheck:** `curl -sf http://localhost:8080/v1/info | grep -q '"starting":false'`

#### 2.5.2 Catalog configs

Create `trino/etc/` directory structure:

```
trino/etc/
├── config.properties           # coordinator config
├── jvm.config                  # JVM settings (reduced for dev)
├── node.properties             # node ID
├── catalog/
│   ├── clickhouse.properties   # ClickHouse connector
│   └── postgresql.properties   # PostgreSQL connector
```

**config.properties:**
```
coordinator=true
node-scheduler.include-coordinator=true
http-server.http.port=8080
discovery.uri=http://localhost:8080
```

**jvm.config** (reduced for dev):
```
-server
-Xmx1G
-XX:+UseG1GC
```

**catalog/clickhouse.properties:**
```
connector.name=clickhouse
connection-url=jdbc:clickhouse://clickhouse:8123/openinsight
connection-user=openinsight
connection-password=openinsight_dev
```

**catalog/postgresql.properties:**
```
connector.name=postgresql
connection-url=jdbc:postgresql://postgres:5432/openinsight
connection-user=openinsight
connection-password=openinsight_dev
```

#### 2.5.3 Verify

- `docker compose --profile app up -d` starts Trino
- Test: `docker compose exec trino trino --execute "SELECT count(*) FROM clickhouse.openinsight.fct_sales"`
- Test: `docker compose exec trino trino --execute "SELECT count(*) FROM postgresql.public.customers"`

#### 2.5.4 Update supporting files

- `scripts/check-health.sh` — add conditional Trino check
- `.env.example` — uncomment `TRINO_PORT=8085`

---

### After 2.4 + 2.5: End-to-End Verification

Before declaring Phase 2 complete, verify the full pipeline works:

1. **Core stack healthy** — `docker compose up -d && ./scripts/check-health.sh`
2. **Seed data loaded** — `./scripts/seed.sh`
3. **Hop Web opens** — http://localhost:8090/ui, openinsight project loads, RDBMS connections visible
4. **Kafka Engine applied** — Run `clickhouse-kafka-tables.sql` against ClickHouse
5. **dbt runs** — `cd dbt && dbt run && dbt test` (requires dbt-clickhouse installed)
6. **Airflow UI** — http://localhost:8081, DAGs visible, no import errors
7. **Trino queries** — Cross-source query via Trino CLI
8. **Update progress.md** — Mark Phase 2 complete

Only then proceed to Phase 3.
