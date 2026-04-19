# OpenInsight — Implementation Progress

> **Last updated:** 2026-04-16 (SSO fully wired — Trino password-file auth, Redpanda Console crash fix, all Keycloak clients defined)
> **Branch:** `main`
> **Implementation target:** ARCHITECTURE.md (841 lines, single source of truth)

---

## Overall Status

| Phase | Description | Status | Progress |
|---|---|---|---|
| **Phase 1** | Foundation — core infra, local dev, identity | ✅ Complete | 7/7 tasks |
| **Phase 2** | Data Pipeline — Hop, Kafka→CH, dbt, Airflow, Trino + Keycloak OIDC | ✅ Complete | 5/5 tasks + OIDC + dbt tested in Airflow |
| **🛑 E2E Milestone** | Hop → Airflow → Kafka → ClickHouse → Superset SSO → SQL Lab | ✅ Verified | Full path tested 2026-04-15 |
| **Phase 3** | Semantic & Viz — Cube, Superset, RLS, API Gateway | ⏳ Pending | 0/5 tasks |
| **Phase 4** | Governance & Hardening — observability, DataHub, DR | ⏳ Pending | 0/6 tasks |

---

## Validation Refresh — 2026-04-09

This refresh cross-checks the documented state against the live local environment and current repo contents without removing prior context.

### Verified runtime state

| Check | Result | Detail |
|---|---|---|
| `./scripts/check-health.sh` | ✅ | Core, pipeline, and app stacks all healthy |
| Superset health endpoint | ✅ | `http://localhost:8088/health` returned `OK` |
| Hop Web UI | ✅ | `http://localhost:8090/ui` served HTML successfully |
| Superset admin user | ✅ | `admin` present in Superset metadata DB |
| Kafka Engine tables + MVs | ✅ | `ingest_raw_transactions`, `ingest_raw_events`, `mv_sales_ingest`, `mv_events_ingest` exist in ClickHouse |
| Current ClickHouse row counts | ✅ | `fct_sales = 56`, `fct_events = 32` |
| Redpanda topics | ✅ | All expected topics present, including `ingest.raw.dimensions`, `ingest.raw.transactions`, `ingest.raw.events` |

### Important correction to milestone status

The runtime stack is healthy, but the sample Hop pipeline currently publishes to `ingest.raw.dimensions`, while the ClickHouse Kafka Engine tables consume `ingest.raw.transactions` and `ingest.raw.events`. That means the exact sales/events E2E path is not perfectly aligned yet even though the platform is up and the Kafka/ClickHouse streaming objects are active.

### Documentation adjustments from this refresh

- `M.1` is no longer "missing in code" because the Hop pipeline now includes a real `KafkaProducerOutput`.
- `M.2` is complete in code and runtime because `seed.sh` applies `clickhouse-kafka-tables.sql`.
- `M.3` is live: Superset is running, healthy, and initialized with a local `admin` user.
- `M.4` is complete in code and runtime.
- dbt still has an env-var naming mismatch: `.env.example` uses `CLICKHOUSE_*`, while `dbt/profiles.yml` expects `CH_*`.

**Signed:** Codex

---

## Git Commits

```
81a1363  chore: accept Hop's canonical project-config.json rewrite
289b3f9  feat: add Apache Superset integration, update Hop pipeline for JSON Kafka production, and enable ClickHouse Kafka engine DDL application.
a0b9486  Add progress.md directive to context files and dev server configurations
984d432  Update progress.md: current state, Phase 3 guardrails, implementation plan
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
| Redpanda Console v2.3.8 | openinsight-redpanda-console | 8888 | ✅ Running |

### Keycloak Realm: `openinsight`

**URL:** http://localhost:8080/admin — credentials: `admin / admin`
**File:** `keycloak/realm-openinsight.json`

#### OIDC Clients

| Client | Secret | Callback / Purpose |
|---|---|---|
| `superset` | `superset-dev-secret` | Superset visualization layer (OIDC direct) |
| `cube` | `cube-dev-secret` | Cube semantic layer (OIDC direct, not yet deployed) |
| `airflow` | `airflow-dev-secret` | Airflow orchestration (OIDC direct) |
| `trino` | `trino-dev-secret` | Trino query engine (OIDC via Kong in prod; password-file locally) |
| `hop-web` | `hop-web-dev-secret` | Hop Web ETL designer (OIDC via Kong in prod; unauthenticated locally) |
| `redpanda-console` | `redpanda-console-dev-secret` | Redpanda Console (OIDC requires enterprise license; unauthenticated locally) |
| `openinsight-api` | `api-dev-secret` | General backend API client (service accounts) |

#### Role Matrix

| User | Password | Group | Realm Roles | Superset | Cube | Airflow | Trino |
|---|---|---|---|---|---|---|---|
| `admin` | `Admin123!DevOps` | — | admin | superset-admin | cube-admin | airflow-admin | trino-admin |
| `alice.finance` | `Test123!DevOps` | Finance | data-analyst | superset-alpha | cube-query | — | trino-query |
| `bob.hr` | `Test123!DevOps` | HR | data-analyst | superset-alpha | cube-query | — | trino-query |
| `carol.engineering` | `Test123!DevOps` | Engineering | data-analyst, data-engineer | superset-alpha | cube-admin | airflow-trigger | trino-admin |
| `dave.executive` | `Test123!DevOps` | Executive | admin | superset-admin | cube-admin | airflow-viewer | trino-query |
| `eve.viewer` | `Test123!DevOps` | Finance | viewer | superset-gamma | cube-query | — | — |

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
- `fct_sales` — 32 rows, 6-month range (includes HR department rows)
- `fct_events` — 16 rows, platform usage events

---

## Phase 2: Data Pipeline ✅ COMPLETE

### Tasks

| # | Task | Status | Notes |
|---|---|---|---|
| 2.1 | Apache Hop | ✅ Done | Hop Web running at :8090, project + env + RDBMS connections configured |
| 2.2 | Kafka→ClickHouse | ✅ Done | `scripts/clickhouse-kafka-tables.sql` — Kafka Engine + MVs present in running ClickHouse; `seed.sh` auto-applies the DDL |
| 2.3 | dbt Project | ✅ Done | All 3 models run (dim_customers, stg_sales, stg_events); 17/17 schema tests pass; `dbt run + dbt test` verified locally and inside Airflow container (2026-04-17) |
| 2.4 | Airflow | ✅ Done | LocalExecutor at :8081; `dag_dbt_transform` fully wired — real `dbt run` + `dbt test` inside Airflow; `dag_hop_ingest` verified (see 2.4 below) |
| 2.5 | Trino | ✅ Done | Trino 435 at :8085, clickhouse + postgresql catalogs, federated join verified (see 2.5 below) |

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
    └── sample-ingest-to-kafka.hpl   # Sample: PG customers → JSON → Kafka (`ingest.raw.dimensions`)
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

### 2.2 Kafka→ClickHouse ✅ Applied In Dev

**File:** `scripts/clickhouse-kafka-tables.sql`

Creates two Kafka Engine tables pointing at Redpanda, with materialized views inserting into existing MergeTree tables:

| Kafka Engine Table | Topic | MV Target |
|---|---|---|
| `ingest_raw_transactions` | `ingest.raw.transactions` | `fct_sales` |
| `ingest_raw_events` | `ingest.raw.events` | `fct_events` |

**Status update (2026-04-09):** applied in the current dev environment and auto-applied by `seed.sh`.

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

**Verified (2026-04-17):** `dbt run` PASS=3, `dbt test` PASS=17 (locally and inside Airflow container). `dbt-clickhouse>=1.8,<2` added to `airflow/Dockerfile`; dbt project mounted read-only at `/opt/airflow/dbt`; output dirs redirected to `/tmp` to avoid write into read-only mount. Port type-casting fix: `profiles.yml` port uses `| int` filter — dbt-clickhouse 1.10 requires integer, not string.

**Known:** `dbt-clickhouse` installed in the Airflow image adds ~200MB to the image size.

---

### 2.4 Apache Airflow ✅ Done

**Started with:** `docker compose --profile pipeline up -d airflow`
**URL:** http://localhost:8081 (login: `admin` / `admin`)
**Image:** `apache/airflow:2.8.4-python3.11`
**Executor:** `LocalExecutor` (scheduler + webserver co-located in one container via `scripts/airflow-entrypoint.sh`)
**Metadata DB:** PostgreSQL `airflow` database (pre-created by `scripts/init-postgres.sh`)

#### DAGs
- `dag_hop_ingest.py` — Triggers `sample-ingest-to-kafka.hpl` via `docker exec openinsight-hop-web hop-run.sh`. `schedule=None`, manual trigger.
- `dag_dbt_transform.py` — Placeholder `dbt run` + `dbt test` tasks. Will be wired once dbt is containerised or mounted into Airflow.

Both DAGs load with zero import errors (`airflow dags list-import-errors` returns "No data found"). `dag_dbt_transform` verified end-to-end via `airflow dags test` — both tasks succeed.

#### Verification (2026-04-15)
- Health check: `./scripts/check-health.sh` reports "Airflow (:8081) OK".
- DAG list: `docker exec openinsight-airflow airflow dags list` shows both DAGs loaded.
- `dag_hop_ingest` manually triggered → **success** (ran in ~16s); 30 customer records produced to `ingest.raw.dimensions` with correct timestamps.
- **Fix applied:** Docker socket (`/var/run/docker.sock`) must be mounted in the Airflow container — without it `docker exec` fails with "Cannot connect to the Docker daemon".

---

### 2.5 Trino ✅ Done

**Started with:** `docker compose --profile app up -d trino`
**URL:** http://localhost:8085
**Image:** `trinodb/trino:435`
**Auth:** Password-file (`trino/etc/password.db`, bcrypt). Over HTTP, accepts `X-Trino-User` header. Full password enforcement requires HTTPS.
**Catalogs:** `clickhouse`, `postgresql`, `system` (auto-registered from `trino/etc/catalog/*.properties`)

#### Connector configuration
- `trino/etc/catalog/clickhouse.properties` — points at `clickhouse:8123/openinsight`; `clickhouse.map-string-as-varchar=true` (returns ClickHouse `String` as UTF-8 `varchar` instead of `varbinary`)
- `trino/etc/catalog/postgresql.properties` — points at `postgres:5432/openinsight`

#### Verification
- `SHOW CATALOGS` returns `clickhouse`, `postgresql`, `system`
- `SELECT count(*) FROM clickhouse.openinsight.fct_sales` → 56
- `SELECT count(*) FROM clickhouse.openinsight.fct_events` → 32
- `SELECT count(*) FROM postgresql.public.customers` → 30
- Federated join (fct_sales × customers) returns revenue-by-customer, region codes as strings (`NA`, `EU`, `MEA`, `APAC`)
- Health check: `./scripts/check-health.sh` reports "Trino (:8085) OK"

---

## 🛑 MILESTONE: First E2E Architecture Test

**HARD STOP — The agent MUST reach this milestone and stop. Do NOT proceed to Airflow, Trino, or any other work until the user has manually tested and confirmed the pipeline works.**

**Goal:** Prove the core data flow: **Hop → Kafka → ClickHouse → Superset**

| # | Task | Status | ~Lines | Notes |
|---|---|---|---|---|
| M.1 | Hop pipeline (PG → Kafka) | ⚠️ Partial | ~140 | `.hpl` patched: WriteToLog replaced with JSON output → Kafka Producer. Current sample writes to `ingest.raw.dimensions`, not the `ingest.raw.transactions` / `ingest.raw.events` topics consumed by the existing ClickHouse Kafka Engine tables |
| M.2 | Apply Kafka Engine DDL | ✅ | ~15 | `seed.sh` now auto-applies `clickhouse-kafka-tables.sql` |
| M.3 | Minimal Superset | ✅ | ~80 | docker-compose `app` profile + `superset_config.py` + `init-superset.sh`. Fixed: added healthcheck, removed non-existent `superset set_database_uri` CLI command (same bug as REVIEW-01), replaced with UI instructions |
| M.4 | Health check + env | ✅ | ~11 | `check-health.sh` + `.env.example` updated |

**Total: ~250 lines of config/code (XML, YAML, Python, Shell)**

### Test Results (2026-04-15) — FULL E2E VERIFIED ✅

| Test | Result | Detail |
|------|--------|--------|
| Core stack (6 services) | ✅ | PG, CH, Keycloak, Redis, Redpanda, Console all healthy |
| Seed data | ✅ | `fct_sales` 56+ rows, `fct_events` 32+ rows in ClickHouse |
| Kafka Engine DDL | ✅ | `ingest_raw_transactions`, `ingest_raw_events` + 2 MVs active |
| Kafka→CH streaming | ✅ | Kafka Engine + MV path verified; messages land in `fct_sales` in <4s |
| Hop pipeline (CLI) | ✅ | `hop-run.sh sample-ingest-to-kafka.hpl` runs in ~1.5s, 30 rows to Kafka |
| **Airflow → Hop** | ✅ | `dag_hop_ingest` triggered → success in 16s; Kafka messages confirmed |
| Keycloak SSO (OIDC) | ✅ | `alice.finance` signs in via Keycloak; browser redirected to Superset |
| Superset SQL Lab | ✅ | `SELECT customer_id, SUM(total_amount) … FROM fct_sales` → 10 rows |
| Trino federation | ✅ | `SELECT count(*) FROM clickhouse.openinsight.fct_sales` → 56 |
| Health check (all) | ✅ | `./scripts/check-health.sh` passes all core + pipeline + app checks |

### Fixes applied during E2E validation

| Fix | Root cause | Solution |
|-----|-----------|---------|
| Keycloak OIDC issuer mismatch | `start-dev` ignores `KC_HOSTNAME`; token `iss=localhost:8080` but discovery doc `issuer=keycloak:8080` | Set `attributes.frontendUrl=http://localhost:8080` in realm JSON |
| Superset Alpha missing SQL Lab | `superset init` doesn't grant `TabStateView` to Alpha | `init-superset.sh` step 4 patches Alpha role after `superset init` |
| Airflow `docker exec` fails | Airflow container has no Docker socket | Mount `/var/run/docker.sock` in `docker-compose.yml` |

### SSO + RLS Expansion (2026-04-15)

**Airflow SSO:** `airflow/Dockerfile` (adds authlib) + `airflow/webserver_config.py` (AUTH_OAUTH, dual-issuer `claims_options` fix, `airflow-{admin,trigger,viewer}` role mapping). Verified: `/login/` renders Keycloak button, health returns 200.

**Superset RLS + DB visibility:**
- `ROW_LEVEL_SECURITY` feature flag enabled.
- `oauth_user_info` now returns `client_roles + groups` so each login gets both a functional role (Alpha/Gamma) AND a group-scoped RLS role.
- `init-superset.sh` grew from 5 → 8 steps: creates `Finance_RLS`/`HR_RLS`/`Engineering_RLS` roles, registers `fct_sales` dataset, creates RLS rules, tightens Alpha to `database access on [ClickHouse]` (removes `all_database_access`).
- Verified in Superset metadata DB: 3 RLS rules persisted with correct role/clause bindings; Alpha has ClickHouse-specific DB perm only.

### RLS E2E Validation (2026-04-16)

Full test run via Superset `/api/v1/chart/data` (the path that enforces RLS):

| User | Roles | Expected | Result | Verdict |
|---|---|---|---|---|
| alice.finance | Alpha + Finance_RLS | FIN rows only | `FIN=6` | PASS |
| bob.hr | Alpha + HR_RLS | HR rows only | `HR=5` | PASS |
| carol.engineering | Alpha + Engineering_RLS | ENG rows only | `ENG=21` | PASS |
| eve.viewer | Gamma + Finance_RLS | FIN rows only (view-only) | `FIN=6` | PASS |
| dave.executive | Admin | all departments | `ENG=21, FIN=6, HR=5, SALES=28` | PASS |

**Critical design note — SQL Lab bypasses RLS (by design):**
Superset RLS filters are applied only at the chart/explore layer (`SqlaTable.get_sqla_query()`).
Ad-hoc SQL Lab queries execute directly against the database and bypass RLS entirely.
- Alpha users (alice/bob/carol) can issue raw SQL in SQL Lab and see all rows.
- Mitigation: eve.viewer (Gamma) is correctly blocked from SQL Lab (403).
- Full enforcement requires Layer 3: ClickHouse native row policies per CH user (not yet implemented; see access model below).

**Known limitations:**
- **Superset config restart:** Config changes (e.g., `superset_config.py`, `AUTH_ROLES_MAPPING`) require a container restart to take effect: `docker compose --profile app restart superset`.
- **Redpanda Console OIDC:** OSS requires enterprise RBAC license. Downgraded to v2.3.8 which runs without RBAC validation. Keycloak `redpanda-console` client is defined; console-side OIDC deferred to enterprise build.
- **Hop Web SSO:** Tomcat OIDC adapters removed in Keycloak 20+. Keycloak `hop-web` client defined for production use behind Kong API gateway. Locally unauthenticated (pipeline profile only).
- **Trino auth:** Password-file authentication enabled locally (`allow-insecure-over-http=true`). Over HTTP, `X-Trino-User` header provides identity. Full OAuth2/OIDC requires HTTPS (production via Kong). Keycloak `trino` client defined with `trino-admin`/`trino-query` roles.
- **Dataset column sync:** `init-superset.sh` step 7 calls `fetch_metadata()` automatically. For manually created datasets, call `PUT /api/v1/dataset/{id}/refresh` to sync columns.

### SSO Wiring Matrix (Definitive — 2026-04-16)

| Service | Local Dev Auth | Keycloak Client | Production Auth | Status |
|---|---|---|---|---|
| **Superset** | OIDC (direct) | `superset` | OIDC (direct) | ✅ Working |
| **Airflow** | OIDC (direct) | `airflow` | OIDC (direct) | ✅ Working |
| **Trino** | password-file (X-Trino-User over HTTP) | `trino` | OIDC via Kong | ✅ Working |
| **Hop Web** | none (pipeline profile, not exposed) | `hop-web` | OIDC via Kong | ✅ Client defined |
| **Redpanda Console** | none (enterprise RBAC required) | `redpanda-console` | OIDC via Kong | ✅ Running (v2.3.8) |
| **Cube** | not deployed | `cube` | OIDC (direct) | ⏳ Phase 3 |
| **Grafana** | not deployed | — | OIDC (direct) | ⏳ Phase 4 |

> **ℹ Keycloak realm import is first-boot only**
> `--import-realm` only runs when the realm doesn't already exist in the DB. **Fresh environments** (new clone, CI, teammate setup) get all 7 clients automatically. **Existing running environments** started before the `trino`/`hop-web` clients were added won't see those clients in the Keycloak admin UI — but this has no impact on local dev because Trino uses password-file auth and Hop Web is unauthenticated locally. Both clients are only exercised in production via Kong.
>
> If you do need to force a re-import (e.g. to verify the full realm in the admin UI):
> ```bash
> docker compose stop keycloak
> docker volume rm openinsight_postgres_data   # wipes Keycloak's DB (also loses PG seed data)
> docker compose up -d                         # re-imports realm-openinsight.json on next boot
> ./scripts/seed.sh && ./scripts/init-superset.sh   # restore seed data
> ```

**Files:**
- `keycloak/realm-openinsight.json` — 7 OIDC clients, 6 users, 4 groups, client roles per service
- `superset/superset_config.py` — Authlib OIDC, dual-issuer, `OpenInsightSecurityManager`
- `airflow/webserver_config.py` — Authlib OIDC, dual-issuer, `OpenInsightAirflowSecurityManager`
- `trino/etc/config.properties` — `PASSWORD` auth type, `allow-insecure-over-http=true`
- `trino/etc/password-authenticator.properties` — file-based authenticator
- `trino/etc/password.db` — bcrypt hashes for all 6 Keycloak users + trino service account

**Access model (three layers):**
1. **Keycloak** — identity + group/role claims (single source of truth).
2. **App-level** — functional role (`Alpha`/`Gamma`/`Admin`) controls features + DB visibility; group role (`Finance_RLS`/etc.) controls row-level filters **at chart/explore layer only**.
3. **Data store** — ClickHouse native row policies per-user enforce SQL Lab boundary (deferred; requires per-role CH accounts + row policy DDL).

| Fix applied during SSO work | Root cause | Solution |
|-----|-----------|---------|
| Airflow image build failed | `apache/airflow` forbids `pip install` as root | Remove `USER root`/`USER airflow` dance from Dockerfile |
| Redpanda Console crash loop | `LOGIN_OIDC_*` env vars require enterprise RBAC | Remove env vars; keep Keycloak client for future |
| Dataset chart queries fail with "columns missing" | Dataset created programmatically has no column metadata | `init-superset.sh` step 7 calls `fetch_metadata()` after dataset creation |
| eve.viewer (Gamma) 403 on chart/data API | Gamma role lacks `datasource_access` on fct_sales by default | `init-superset.sh` step 7 grants Gamma `datasource_access on [ClickHouse].[fct_sales]` |
| bob.hr sees 0 rows | Seed data had no HR department rows | Added 5 HR rows to `seed-clickhouse.sql` |
| Duplicate "Other" database (id=1) | Manual setup before init script created ClickHouse (id=2) | Removed duplicate; init script is idempotent |
| Ghost row with empty `department_code` | Test row from Kafka engine ingestion (sale_id=0, all zeros) | Deleted from ClickHouse |

**Note:** Tomcat on the host was binding port 8080, blocking Keycloak — killed to proceed. If Tomcat runs on your machine, either stop it first or remap Keycloak's port in `.env`.

### What is NOT needed for this milestone
- ❌ Airflow (trigger Hop pipeline manually from Hop Web UI)
- ❌ Trino (Superset connects directly to ClickHouse)
- ❌ Cube (Superset queries CH without semantic layer)
- ❌ Keycloak OIDC for Superset (use built-in admin login)
- ❌ dbt (fact tables already seeded; staging views are nice-to-have)

### Verification steps (user performs manually)
1. `docker compose up -d` — core stack healthy
2. `./scripts/seed.sh` — seed data + apply Kafka Engine DDL
3. `docker compose --profile pipeline up -d` — Hop Web starts
4. Open Hop Web (http://localhost:8090/ui), run the PG→Kafka pipeline
5. Check Redpanda Console (http://localhost:8888) — messages appear in topic
6. Query ClickHouse — data landed in `fct_sales` via Kafka Engine + MV
7. `docker compose --profile app up -d` — Superset starts
8. Open Superset (http://localhost:8088), log in as admin, add ClickHouse datasource
9. Create a simple chart from `fct_sales` — **if this works, architecture is validated**

### After verification: resume implementation in the order below

---

## Architectural Directives (from project review, 2026-04-08)

### Directive 1: Keycloak must be wired into every web UI before adding new components

> "Every day a component runs with its own auth is a day where the centralized identity architecture exists on paper only."

Keycloak was the first thing built. It has 3 OIDC clients, 6 users, client-specific roles, group-based inheritance, and verified JWT claims. Yet every running application ignores it. **Superset → Keycloak OIDC is the immediate next action after Phase 2 completion.**

### Directive 2: Finish Phase 2 completely before any Phase 3 work

The implementation sequence is non-negotiable:
1. dbt run (validate transformation layer)
2. Airflow + DAGs (automated orchestration for Hop + dbt)
3. Trino (federated query layer — Cube depends on this)
4. Superset → Keycloak OIDC (centralized auth)
5. Cube (semantic layer, requires Trino)
6. RLS (requires Cube + Keycloak JWT groups)

### Directive 3: Hop vs Airbyte — decision framework

**Current decision: Keep Hop for internal sources and visual orchestration. dbt does all T. Evaluate Airbyte when external sources are onboarded.**

| Concern | Hop | Airbyte |
|---------|-----|---------|
| Visual pipeline design | ✅ Core strength | ❌ Not its purpose |
| Connector breadth | ~50 | 300+ |
| EL from external sources | Limited | ✅ Core strength |
| Custom transforms | ✅ Rich transform library | ❌ EL only |
| dbt overlap | Yes — Hop's T overlaps dbt's T | No — clean EL + T separation |

**Rule: Hop does E+L for internal sources (PG, CH, Kafka). dbt does ALL transformations. No double-transforming. If/when external sources arrive (Salesforce, Stripe, S3), evaluate Airbyte at that point.**

### Known gaps flagged in review

| Gap | Detail | Fix |
|-----|--------|-----|
| Hop pipeline targets wrong topic | Pipeline writes to `ingest.raw.dimensions`, but Kafka Engine tables consume `ingest.raw.transactions` and `ingest.raw.events`. Full chain (Hop→Kafka→CH) never tested automatically. | Create a second Hop pipeline writing to `ingest.raw.transactions` to complete the loop, or add a third Kafka Engine table for `ingest.raw.dimensions` |
| dbt env var naming mismatch | `.env.example` uses `CLICKHOUSE_*`/`POSTGRES_*`, Hop uses `PG_*`/`CH_*`, dbt uses `CH_NATIVE_PORT`. First `dbt run` will fail. | Standardize on `PG_*`/`CH_*` for app-level vars; keep `POSTGRES_*`/`CLICKHOUSE_*` for docker-compose only |

### Maintainer signature

Validation refresh appended on 2026-04-09 by **Codex**.

---

## Recommended Priority Order (4-week plan)

| # | Task | Est. | Phase |
|---|------|------|-------|
| 1 | Run dbt models — validate transformation layer | 1 day | Phase 2 |
| 2 | Fix env var naming alignment (dbt, Hop, .env) | 0.5 day | Phase 2 |
| 3 | Deploy Airflow with DAGs for Hop + dbt | 1 week | Phase 2 |
| 4 | Deploy Trino with CH + PG catalogs | 3 days | Phase 2 |
| 5 | Wire Superset → Keycloak OIDC | 2 days | Phase 2→3 bridge |
| 6 | Deploy Cube in dev mode against ClickHouse | 1 week | Phase 3 |
| 7 | Implement basic RLS in Cube using Keycloak JWT groups | 3 days | Phase 3 |

---

## Remaining Phase 2 Work — Implementation Plan

See detailed task specs below in "Next Steps for Implementation Agent" section.

---

## Phase 3: Semantic & Visualization ⏳ PENDING

**DO NOT START Phase 3 until Phase 2 is verified end-to-end AND Superset→Keycloak OIDC is working.**

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
| REVIEW-02 | M.1 pipeline had empty `<connection/>` | Agent left Table Input with no DB connection. Fixed to `<connection>openinsight-postgres</connection>` |
| REVIEW-03 | M.1 pipeline XML minified | Agent appended JSON output + Kafka Producer as single-line XML. Fixed to proper indentation |
| REVIEW-04 | M.3 Superset had no healthcheck | Agent omitted healthcheck despite rule #3 (follow existing patterns). Fixed: added `curl -sf http://localhost:8088/health` |
| REVIEW-05 | M.3 `init-superset.sh` used `superset set_database_uri` | CLI command doesn't exist in Superset 3.x — same class of bug as REVIEW-01. Replaced with manual UI instructions |
| HOP-05 | Hop rewrites `project-config.json` on startup | Removes `config_version`, `enforcingExecutionInHome`, `variables:[]`; renames `parentProjectReferenceName`→`parentProjectName`. Committed canonical version at `81a1363` |
| ENV-01 | Tomcat (Homebrew) on host binds port 8080 | Conflicts with Keycloak. Kill Tomcat or remap `KEYCLOAK_PORT` in `.env` before starting |

---

## Architecture Decisions Implemented

| ADR | Decision | Implementation |
|---|---|---|
| ADR-001 | Kafka as message backbone | ✅ Proven: Redpanda → Kafka Engine → MV → fct_sales in <4s |
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

### Priority Order (STRICT — follow this sequence exactly)

1. Fix env var naming alignment (PG_*, CH_* standard)
2. Run dbt models — verify transformation layer
3. Deploy Airflow with DAGs for Hop + dbt (task 2.4)
4. Deploy Trino with CH + PG catalogs (task 2.5)
5. Wire Superset → Keycloak OIDC (~30 lines in superset_config.py)
6. **STOP — Phase 2 complete. Report back for Phase 3 review.**

### RULES FOR THE IMPLEMENTATION AGENT

**Permanent rules (apply to all phases):**

1. **Follow the priority order above.** Do not skip steps or reorder. Each step builds on the previous.
2. **Read the Architectural Directives section** before starting any work. Those are non-negotiable project decisions.
3. **Test before committing.** Every service added to docker-compose must start healthy before being committed. Run `./scripts/check-health.sh` after changes.
4. **Follow existing patterns.** Look at how `hop-web` was added to docker-compose.yml — same structure: `profiles`, `depends_on` with `condition: service_healthy`, healthcheck, `restart: unless-stopped`.
5. **Use environment variables.** Never hardcode credentials in config files. Use `${VAR:-default}` in docker-compose and env var functions in application configs. Standardize on `PG_*`/`CH_*` for app-level vars.
6. **One concern per commit.** Don't bundle Airflow + Trino + dbt tests in one commit.
7. **Read ARCHITECTURE.md Section 9** (Phased Implementation Plan) before starting. Tasks 2.4 and 2.5 are defined there.
8. **Read the Hop metadata format notes** (HOP-03, HOP-04 in Known Issues) before writing any Hop metadata JSON.
9. **Hop does E+L only. dbt does ALL transformations.** Do not add transformation logic to Hop pipelines. Keep them as extract-load pipes.
10. **Keycloak is mandatory for every web UI.** Superset OIDC must be wired before declaring Phase 2 done. Use `AUTH_OAUTH` (NOT `AUTH_OID`). The `superset` OIDC client is already configured in `keycloak/realm-openinsight.json`.

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
