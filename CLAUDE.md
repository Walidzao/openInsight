# OpenInsight - Claude Code Context

## Project Overview
OpenInsight is an enterprise-grade BI platform built on open-source components.
The definitive technical spec is ARCHITECTURE.md in the repo root.

## Tech Stack (17 components)
- **Identity:** Keycloak 24+ (OIDC, RBAC, SSO)
- **API Gateway:** Kong or NGINX Ingress
- **Visualization:** Apache Superset 3.x
- **Semantic Layer:** Cube 0.35.x (cluster mode, Redis-backed cache)
- **Transformation:** dbt Core 1.7.x
- **Query Federation:** Trino 435+
- **OLAP:** ClickHouse 24.x (ReplicatedMergeTree)
- **OLTP:** PostgreSQL 16.x (Patroni HA)
- **Messaging:** Redpanda (Kafka-compatible, local dev) / Kafka (production)
- **Cache:** Redis 7.x (Sentinel)
- **Orchestration:** Apache Airflow 2.8.x
- **ETL:** Apache Hop 2.x
- **Catalog:** DataHub 0.13.x (Phase 4)
- **Monitoring:** Prometheus + Grafana
- **Logging:** Grafana Loki + Promtail
- **Tracing:** Jaeger or Grafana Tempo
- **Automation:** n8n (alert routing only)

## Cloud Target
- GCP (GKE) — infrastructure as Terraform modules (deferred)
- CI/CD: GitHub Actions (deferred, directory structure prepared)

## Local Development
```bash
docker compose up -d                            # Start core stack (PG, CH, Keycloak, Redis, Redpanda)
docker compose --profile app up -d              # Add Superset, Cube, Trino (future)
docker compose --profile pipeline up -d         # Add Airflow, dbt (future)
./scripts/check-health.sh                       # Verify all services
./scripts/seed.sh                               # Load sample data
```

## Key Architecture Decisions
- Redpanda for local dev (Kafka-compatible, no ZooKeeper)
- Event-driven cache invalidation: Keycloak -> Kafka -> Redis -> Cube
- Cube routes single-source queries direct to ClickHouse, cross-source through Trino
- Single Keycloak realm with group-based isolation (not multi-realm)
- Namespace-based network isolation in K8s (7 namespaces)
- Monorepo structure (ADR-012)

## Implementation Phases
1. **Foundation** (current): Core infra, local dev, Keycloak, databases
2. **Data Pipeline:** Hop, Kafka->CH, dbt, Airflow, Trino
3. **Semantic & Viz:** Cube cluster, Superset, RLS, API Gateway
4. **Governance:** DataHub, observability, load testing, DR

## Conventions
- All config is IaC (Terraform, Helm, docker-compose) — no manual UI config in prod
- Secrets via .env locally, Sealed Secrets in K8s
- dbt naming: stg_*, int_*, dim_*, fct_*
- JSON structured logging with: timestamp, level, service, trace_id, user_id, message
- Terraform modules: GCP-specific (gke/, cloudsql/, gcs/)

## Important File Locations
- `ARCHITECTURE.md` — full technical spec (single source of truth)
- `docker-compose.yml` — local dev environment
- `keycloak/realm-openinsight.json` — Keycloak realm config
- `.env.example` — required environment variables
- `scripts/init-postgres.sh` — creates keycloak, superset, airflow databases
- `scripts/seed.sh` — sample data loader
- `scripts/check-health.sh` — service health checker

## Service Ports (Local Dev)
| Service          | Port  |
|------------------|-------|
| PostgreSQL       | 5432  |
| ClickHouse HTTP  | 8123  |
| ClickHouse Native| 9000  |
| Keycloak         | 8080  |
| Redis            | 6379  |
| Redpanda Kafka   | 19092 |
| Redpanda HTTP    | 18082 |
| Schema Registry  | 18081 |
| Redpanda Console | 8888  |
| Superset (future)| 8088  |
| Cube (future)    | 4000  |
| Trino (future)   | 8085  |
| Airflow (future) | 8081  |
