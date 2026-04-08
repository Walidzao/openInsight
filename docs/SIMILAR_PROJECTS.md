# Open Source Data Stack Reference Projects

> Projects similar to OpenInsight's architecture, useful for reference and inspiration.
> Last updated: February 2026

---

## Comparison Overview

OpenInsight is unusual in combining three concerns most repos treat separately:

| Concern | Typical OSS Repos | OpenInsight |
|---|---|---|
| **Identity + RLS** | Ignored or basic API keys | Keycloak OIDC, group-based RLS, JWT cache invalidation via Kafka → Redis → Cube |
| **Semantic layer** | Skip straight to BI tool | Cube cluster with pre-aggregations, user-context caching, Trino routing |
| **Event-driven ops** | Batch-only or stream-only | Kafka as backbone for both data ingestion AND operational events (cache invalidation, pipeline signals) |

No single repo matches OpenInsight's exact combination. The projects below cover significant overlapping subsets.

---

## Projects (Ordered by Relevance)

### 1. [fortiql/data-forge](https://github.com/fortiql/data-forge) — Closest overall match

**Stars:** 168 · **Forks:** 25

A modern data stack playground designed for practicing data flows and best practices. All components wired together in Docker Compose.

| Layer | Components |
|---|---|
| Processing | Spark, Trino, Kafka, Iceberg |
| Storage | ClickHouse, MinIO |
| Orchestration | Airflow |
| Visualization | Superset |

**Overlap with OpenInsight:** Trino, ClickHouse, Kafka, Airflow, Superset, Docker Compose structure, Jupyter notebooks for exploration.

**Missing vs. OpenInsight:** No Keycloak/auth, no Cube semantic layer, no Redis cache invalidation, no Hop ETL, no RLS, no dbt.

**Best used for:** Reference on wiring Trino + ClickHouse + Airflow + Superset together locally.

---

### 2. [vincevv017/modern-data-stack](https://github.com/vincevv017/modern-data-stack) — Semantic layer focus

A vendor-agnostic data lakehouse focusing on the transform-to-serve layer. 100% open source.

| Layer | Components |
|---|---|
| Federation | Trino |
| Transform | dbt |
| Semantic | Cube.js |
| Visualization | Metabase |

**Overlap with OpenInsight:** Trino federation, Cube.js semantic layer, dbt transforms — the exact Phase 2+3 pipeline.

**Missing vs. OpenInsight:** No ClickHouse, no Kafka, no Keycloak, no Airflow, no Hop.

**Best used for:** Reference for Cube.js + Trino + dbt integration and schema configuration.

---

### 3. [buun-ch/buun-stack](https://github.com/buun-ch/buun-stack) — Auth + data stack on Kubernetes

**Stars:** 15 · **Commits:** 368 · **License:** MIT

Kubernetes home lab combining identity management with a full data stack.

| Layer | Components |
|---|---|
| Identity | Keycloak (OIDC) + cert-manager |
| Storage | ClickHouse |
| Orchestration | Airflow |
| Platform | Kubernetes |

**Overlap with OpenInsight:** Keycloak OIDC on Kubernetes, ClickHouse, Airflow, Helm-based deployment.

**Missing vs. OpenInsight:** No Cube semantic layer, no Trino federation, no Hop ETL, no Kafka streaming pipeline.

**Best used for:** Reference for wiring Keycloak OIDC auth with data tools on Kubernetes.

---

### 4. [hoangsonww/End-to-End-Data-Pipeline](https://github.com/hoangsonww/end-to-end-data-pipeline) — Production patterns

**Stars:** 81 · **Created:** 2025

Production-ready solution supporting batch and streaming processing with observability and CI/CD.

| Layer | Components |
|---|---|
| Ingestion | Kafka streaming |
| Processing | Apache Spark ETL |
| Storage | PostgreSQL, MinIO |
| Orchestration | Airflow |
| Quality | Great Expectations |
| Observability | Prometheus + Grafana |
| MLOps | MLflow |
| CI/CD | GitHub Actions, Docker, Kubernetes |

**Overlap with OpenInsight:** Kafka, Airflow, monitoring, GitHub Actions CI/CD patterns, data quality checks, Docker + Kubernetes structure.

**Missing vs. OpenInsight:** No ClickHouse, no Cube, no Keycloak, no Trino, no dbt.

**Best used for:** Reference for CI/CD pipeline design, Great Expectations data quality integration, and observability setup.

---

### 5. [mohhddhassan/kafka-clickhouse-pipeline](https://github.com/mohhddhassan/kafka-clickhouse-pipeline) — Minimal but targeted

Minimal streaming pipeline connecting a Python Kafka producer directly to ClickHouse.

| Layer | Components |
|---|---|
| Ingestion | Python Kafka producer |
| Storage | ClickHouse (Kafka Engine + Materialized Views) |
| Infra | Docker Compose |

**Overlap with OpenInsight:** Exactly the Kafka → ClickHouse Kafka Engine + Materialized View pattern needed for Phase 2 (task 2.2).

**Missing vs. OpenInsight:** Everything else — no auth, no transform, no orchestration, no BI layer.

**Best used for:** Direct reference implementation for `scripts/clickhouse-kafka-tables.sql` (Phase 2 task 2.2).

---

### 6. [Stefen-Taime/Iceberg-Dbt-Trino-Hive](https://github.com/stefen-taime/iceberg-dbt-trino-hive-modern-open-source-data-stack) — Lakehouse focus

Demonstrates Iceberg + dbt + Trino + Hive integration. Setup via `docker-compose up --build -d` then `dbt deps && dbt run`.

| Layer | Components |
|---|---|
| Storage | Apache Iceberg |
| Transform | dbt |
| Federation | Trino |
| Metastore | Hive |

**Overlap with OpenInsight:** dbt transform patterns, Trino federation setup and catalog configuration.

**Missing vs. OpenInsight:** No streaming, no auth, no BI layer, no ClickHouse.

**Best used for:** dbt project structure and Trino catalog configuration reference (Phase 2 tasks 2.3, 2.5).

---

## What to Take From Each

| Project | Borrow For |
|---|---|
| **data-forge** | Docker Compose wiring for Trino + ClickHouse + Airflow + Superset |
| **modern-data-stack** | Cube.js schema YAML + Trino connector + dbt integration |
| **buun-stack** | Keycloak OIDC on Kubernetes with data tools, Helm chart structure |
| **end-to-end-data-pipeline** | CI/CD GitHub Actions, data quality (Great Expectations), observability |
| **kafka-clickhouse-pipeline** | Kafka Engine DDL + Materialized View pattern (Phase 2 task 2.2) |
| **Iceberg-Dbt-Trino-Hive** | dbt project layout, Trino catalog configs |
