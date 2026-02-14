# OpenInsight Platform — Architecture & Design Document

> **Version:** 1.0 · **Date:** February 2026 · **Source:** OpenInsight PRD v1.0
> **Purpose:** Definitive technical blueprint for Claude Code implementation.
> This document is the single source of truth for building OpenInsight. Every Helm chart, Terraform module, dbt model, and CI pipeline must conform to the specifications below.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [PRD Architecture Critique](#2-prd-architecture-critique)
3. [Target System Architecture](#3-target-system-architecture)
4. [High Availability Architecture](#4-high-availability-architecture)
5. [Security Architecture](#5-security-architecture)
6. [Observability Architecture](#6-observability-architecture)
7. [CI/CD & Development Strategy](#7-cicd--development-strategy)
8. [Disaster Recovery](#8-disaster-recovery)
9. [Phased Implementation Plan](#9-phased-implementation-plan)
10. [Claude Code Automation Specification](#10-claude-code-automation-specification)
11. [Operational Requirements](#11-operational-requirements)
12. [Architecture Decision Log](#12-architecture-decision-log)
13. [Appendices](#13-appendices)

---

## 1. Executive Summary

OpenInsight is an integrated, enterprise-grade BI platform built on open-source components. This Architecture & Design Document (ADD) translates the PRD v1.0 into a concrete, implementable architecture. It does three things:

1. **Extracts and validates** the PRD architecture.
2. **Identifies 14 critical gaps** and rates them by severity.
3. **Establishes corrective design decisions** with implementation specifics for Claude Code.

**Key finding:** The PRD describes an ambitious 12-component stack but under-specifies cache invalidation, high-availability, operational automation, security hardening, and CI/CD strategy. This document closes those gaps by adding 5 infrastructure components (Kafka, Redis, API Gateway, Loki, Jaeger) and redesigning the Cube, Keycloak, and pipeline layers for production resilience.

### 1.1 Design Principles

- **Infrastructure-as-Code First:** Every resource is defined in version-controlled Terraform, Helm, or Kubernetes manifests. Nothing is configured via UI clicks in production.
- **Fail-Safe Defaults:** Components start with restrictive network policies, minimal RBAC, and explicit deny rules.
- **Observable by Default:** Distributed tracing, structured logging, and metrics instrumentation from day one.
- **Incremental Complexity:** MVP with 6 core components; add governance and scale tooling in later phases.
- **Automate the Automatable:** Claude Code generates ~70% of scaffolding; humans validate security, performance, and domain logic.

---

## 2. PRD Architecture Critique

Before building, we must understand what's wrong with the PRD design. Each deficiency has a severity rating and a pointer to the corrective section.

### 2.1 Critical Deficiencies

#### 2.1.1 JWT-Based Cache Invalidation Gap — `CRITICAL`

**Problem:** The PRD routes all data access through Keycloak JWT → Cube `security_context`. When user group membership changes in Keycloak (e.g., user moves from Finance to HR), cached query results in Cube remain stale until cache TTL expires. If cache TTL = 5 min and token refresh = 1 min, there is a **4-minute window of unauthorized data access**. Cube has no API to invalidate cache by user context.

**Corrective action:** Event-driven cache invalidation via Keycloak → Kafka → Redis pub/sub → Cube cache eviction. See [Section 3.4](#34-cache-invalidation-design).

#### 2.1.2 Cube Single Point of Failure at Scale — `CRITICAL`

**Problem:** The PRD targets 500 concurrent users hitting a single Cube deployment. Cube uses single-threaded Node.js for query planning. User-specific RLS filters dramatically reduce cache hit rates. Under load, query queuing becomes a bottleneck with no graceful degradation.

**Corrective action:** Cube cluster mode with Cube Store, Redis shared state, and HPA. See [Section 3.3](#33-cube-cluster-architecture).

#### 2.1.3 Keycloak as Authentication SPOF — `CRITICAL`

**Problem:** While the PRD lists 3 Keycloak replicas, it doesn't specify session persistence, database HA, or fallback authentication. If the Keycloak cluster fails, the entire platform is inaccessible.

**Corrective action:** Infinispan cross-site replication, dedicated PostgreSQL with Patroni, and emergency JWKS caching in Cube/Superset. See [Section 4.2](#42-keycloak-ha-detail).

#### 2.1.4 No Backpressure in Data Pipeline — `HIGH`

**Problem:** The pipeline `Sources → Hop → ClickHouse → dbt → Cube` assumes every stage is available. No circuit breaker, dead-letter queue, or backpressure mechanism. A slow ClickHouse causes Hop to queue in memory → OOM → cascading failure.

**Corrective action:** Kafka as the message backbone between Hop and ClickHouse, with dead-letter topics. See [Section 3.2](#32-data-flow-architecture-corrected).

#### 2.1.5 Missing Operational Infrastructure — `HIGH`

**Problem:** The PRD omits: API gateway, log aggregation, distributed tracing, secret rotation, certificate management, network policies, blue-green deployments, and local dev environment.

**Corrective action:** See Sections [3.6](#36-api-gateway-design), [5](#5-security-architecture), [6](#6-observability-architecture), [7](#7-cicd--development-strategy).

#### 2.1.6 dbt-to-Cube Schema Synchronization — `HIGH`

**Problem:** dbt models are the source of truth for transformations, but Cube schemas are separate YAML files with no automated sync. Schema drift causes silent data inconsistencies and broken dashboards.

**Corrective action:** Build a dbt-to-Cube schema generator that runs post-`dbt compile`. See [Section 10](#10-claude-code-automation-specification).

### 2.2 Complete Gap Matrix

| Gap Category | PRD Coverage | Impact | Resolved In |
|---|---|---|---|
| Cache Invalidation | Not addressed | Data leakage risk | §3.4 |
| High Availability | Partial (replica counts only) | Full platform outage | §4 |
| API Gateway / Service Mesh | Not mentioned | No inter-service observability | §3.6 |
| Message Queue / Backpressure | Not mentioned | Cascading pipeline failures | §3.2 |
| Log Aggregation | Not mentioned | Cannot debug production issues | §6.2 |
| Distributed Tracing | Not mentioned | Cannot identify latency bottlenecks | §6.3 |
| CI/CD Pipeline | Not mentioned | Manual, error-prone deployments | §7 |
| Secret Rotation | Not mentioned | Credential compromise risk | §5.4 |
| Network Policies | Not mentioned | Lateral movement risk | §5.2 |
| Local Dev Environment | Not mentioned | Slow developer onboarding | §7.4 |
| Schema Evolution | Not mentioned | Silent data corruption | §10 |
| Disaster Recovery | Partial (SLA only) | Data loss beyond RPO | §8 |
| Load Testing | Not mentioned | SLA violations in production | §7.3 |
| Data Quality Framework | Partial (dbt tests) | Bad data reaches dashboards | §6.4 |

---

## 3. Target System Architecture

### 3.1 Revised Component Stack

The target architecture adds 5 infrastructure components to the PRD's 12 and clarifies the scope of n8n:

| Layer | Component | Purpose | PRD Status |
|---|---|---|---|
| Identity & Access | Keycloak 24+ (HA cluster) | SSO, RBAC, OIDC, SAML, MFA | Retained |
| API Gateway | Kong or NGINX Ingress | Rate limiting, routing, TLS termination | **NEW** |
| Visualization | Apache Superset | Dashboards, SQL IDE, exploration | Retained |
| Semantic Layer | Cube (cluster mode) | Metrics, caching, RLS, REST/GraphQL API | **Enhanced** |
| Transformation | dbt Core | SQL transforms, testing, lineage | Retained |
| Query Federation | Trino (HA) | Distributed SQL across sources | **Enhanced** |
| OLAP Storage | ClickHouse (replicated) | Columnar analytics, real-time ingest | Retained |
| OLTP Storage | PostgreSQL (HA via Patroni) | Metadata, operational data | Retained |
| Message Backbone | Apache Kafka or Redpanda | CDC, backpressure, event streaming | **NEW** |
| ETL / Ingestion | Apache Hop | Visual data pipelines | Retained |
| Orchestration | Apache Airflow | DAG scheduling, monitoring | Retained |
| Data Catalog | DataHub | Metadata, lineage, discovery | Retained (Phase 4) |
| Monitoring | Prometheus + Grafana | Infrastructure metrics, alerting | Retained |
| Logging | Grafana Loki + Promtail | Centralized log aggregation | **NEW** |
| Tracing | Jaeger or Grafana Tempo | Distributed request tracing | **NEW** |
| Cache | Redis (Sentinel) | Cube cache, session store, pub/sub | **NEW** |
| Automation | n8n | Alert routing, webhook automation only | **Clarified** |

### 3.2 Data Flow Architecture (Corrected)

The corrected data flow introduces Kafka as a decoupling layer and Redis as the shared cache/pub-sub backbone:

```
┌──────────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                                  │
│            (APIs, Databases, Files, SaaS, Kafka)                     │
└───────────────────────────────┬──────────────────────────────────────┘
                                │
                                ▼
                     ┌─────────────────────┐
                     │    Apache Hop        │  ← ETL / Ingestion
                     │  (Visual Pipelines)  │
                     └──────────┬──────────┘
                                │
                                ▼
                     ┌─────────────────────┐
                     │   Apache Kafka       │  ← NEW: Message Backbone
                     │  (Backpressure, CDC) │     Dead-letter topics
                     └──────────┬──────────┘     Event replay
                                │
                  ┌─────────────┴─────────────┐
                  ▼                             ▼
       ┌──────────────────┐         ┌──────────────────┐
       │   ClickHouse      │         │   PostgreSQL      │
       │ (Kafka Engine /   │         │ (Small dims,      │
       │  Mat. Views)      │         │  metadata)        │
       └────────┬─────────┘         └────────┬─────────┘
                │                             │
                └──────────────┬──────────────┘
                               ▼
                    ┌─────────────────────┐
                    │      Trino           │  ← Query Federation
                    │  (Pushdown rules,    │     Resource groups
                    │   HA coordinator)    │
                    └──────────┬──────────┘
                               ▼
              ┌──────────────────────────────┐
              │  Airflow triggers dbt runs    │  ← Orchestration
              │  dbt publishes manifest to    │     + Transformation
              │  DataHub                      │
              └──────────────┬───────────────┘
                             ▼
                  ┌─────────────────────┐
                  │       Cube           │  ← Semantic Layer
                  │  (Cluster mode,      │     Redis-backed cache
                  │   Cube Store,        │     JWT-based RLS
                  │   HPA autoscaling)   │
                  └──────────┬──────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌────────────┐ ┌────────────┐ ┌────────────┐
       │  Superset   │ │  REST API  │ │  Custom UI │
       │ (Dashboards)│ │ (Embedding)│ │  (React)   │
       └────────────┘ └────────────┘ └────────────┘

═══════════════════════════════════════════════════════════════
                    CROSS-CUTTING SERVICES
═══════════════════════════════════════════════════════════════
 Keycloak │ Kong │ Redis │ Prometheus │ Loki │ Jaeger │ n8n
═══════════════════════════════════════════════════════════════
```

**Tier-by-tier flow:**

- **Tier 1 — Ingestion:** Data Sources → Apache Hop → Kafka Topics (raw events)
- **Tier 2 — Storage:** Kafka → ClickHouse (via Kafka Engine / materialized views) + PostgreSQL (small dims)
- **Tier 3 — Transform:** Airflow triggers dbt runs against ClickHouse/PostgreSQL. dbt publishes `manifest.json` to DataHub.
- **Tier 4 — Semantic:** Cube reads from Trino (federated) or direct ClickHouse. Redis caches results keyed by user-context hash.
- **Tier 5 — Presentation:** Superset queries Cube REST/GraphQL API. Embedded dashboards via iframe with JWT.
- **Cross-cutting:** Keycloak issues JWTs; Kong enforces rate limits; Prometheus scrapes all; Loki aggregates logs; Jaeger traces requests.

### 3.3 Cube Cluster Architecture

Cube must operate in cluster mode to meet the 500-concurrent-user target:

| Component | Replicas | Purpose |
|---|---|---|
| **Cube API Instances** | 3+ (HPA) | Stateless query planning and REST/GraphQL serving. Auto-scaled on CPU and request queue depth. |
| **Cube Refresh Worker** | 1-2 | Dedicated pods for pre-aggregation refresh. Isolated from query path to prevent refresh blocking user queries. |
| **Cube Store** | 3+ | Distributed pre-aggregation storage. Stores materialized rollups in columnar format for sub-second response. |
| **Redis Sentinel** | 3 | Shared state for cache coordination, query deduplication, and Keycloak invalidation events. |

**Cube-to-data routing rules:**

- Single-source queries (ClickHouse only): Cube connects **directly to ClickHouse** — bypasses Trino overhead.
- Cross-source queries (ClickHouse + PostgreSQL): Cube routes through **Trino federation**.
- This routing is configured per-cube in `cube.js` via the `dataSource` property.

### 3.4 Cache Invalidation Design

To resolve the critical JWT-cache gap, the architecture implements event-driven cache invalidation:

```
Keycloak ──(user/group change event)──► Kafka topic: keycloak.events
                                                │
                                                ▼
                                   Invalidation Service
                                   (lightweight consumer)
                                                │
                                                ▼
                                   Redis PUBLISH: cache.invalidate
                                                │
                                                ▼
                                   Cube API Instances (subscribers)
                                   → Evict entries by user-context hash
```

**Step 1:** Keycloak Event Listener SPI publishes user/group change events to Kafka topic `keycloak.events`.
**Step 2:** A lightweight invalidation service consumes events and publishes Redis `PUBLISH` messages with affected user IDs.
**Step 3:** Cube API instances subscribe to the Redis channel. On invalidation event, they evict all cache entries containing the affected user-context hash.
**Step 4:** Next query for that user triggers a cache miss → re-fetches with updated JWT → re-caches.

**Worst-case invalidation latency:** < 5 seconds.

### 3.5 Trino Federation Strategy

| Config | Specification |
|---|---|
| **ClickHouse Connector** | Enable predicate pushdown, aggregation pushdown, and limit pushdown. Pin connector version to match Trino release. |
| **PostgreSQL Connector** | Enable join pushdown for dimension lookups. Use PgBouncer for connection pooling. |
| **Query Routing** | Single-source queries bypass Trino; Cube routes directly to ClickHouse. |
| **Resource Groups** | Max 5 concurrent queries/user. Max 200 total cluster concurrency. |
| **Memory** | Coordinator: 16 GB. Workers: 32 GB each. `query.max-memory-per-node = 8GB`. |

### 3.6 API Gateway Design

All external traffic enters through Kong or NGINX Ingress:

| Function | Configuration |
|---|---|
| **TLS Termination** | All HTTPS at gateway; internal traffic via mTLS or plain HTTP in trusted namespace. |
| **Rate Limiting** | Per-user: 100 req/min (dashboard), 20 req/min (SQL). Enforced via Keycloak token claims. |
| **Path Routing** | `/superset/*` → Superset, `/cubejs-api/*` → Cube, `/auth/*` → Keycloak, `/airflow/*` → Airflow. |
| **Health Checks** | Active checks on all backends; auto-remove unhealthy pods. |
| **CORS** | Restrictive: platform domain only. No wildcard origins. |

---

## 4. High Availability Architecture

### 4.1 HA Topology

| Component | HA Pattern | Min Replicas | Failover Mechanism | RTO |
|---|---|---|---|---|
| Keycloak | Active-Active (Infinispan) | 3 | LB health checks | < 30s |
| Superset | Stateless Deployment | 3+ | K8s rolling restart | < 15s |
| Cube API | Stateless + Redis state | 3+ | HPA + LB | < 15s |
| Cube Store | Distributed (Raft) | 3+ | Auto leader election | < 60s |
| Trino Coordinator | Active-Passive | 2 | K8s liveness probe failover | < 120s |
| Trino Workers | Stateless pool | 3-10 | Auto-replaced by K8s | < 30s |
| ClickHouse | ReplicatedMergeTree + Keeper | 3 | Auto replica promotion | < 60s |
| PostgreSQL | Streaming replication (Patroni) | 2 (primary + standby) | Patroni auto-failover | < 30s |
| Redis | Sentinel | 3 | Sentinel auto-promote | < 15s |
| Airflow Scheduler | HA Scheduler | 2 | Active-active lock-based | < 60s |
| Kafka | Replicated partitions | 3 brokers | ISR leader election | < 30s |

### 4.2 Keycloak HA Detail

Keycloak HA requires three layers of redundancy:

- **Application Layer:** 3+ pods with Infinispan distributed cache for session replication. `JDBC_PING` or `DNS_PING` for cluster discovery in Kubernetes.
- **Database Layer:** Dedicated PostgreSQL instance with Patroni for automatic failover. **Separate** from the application PostgreSQL to isolate blast radius.
- **Emergency Fallback:** Cube and Superset cache the Keycloak JWKS locally with a 1-hour TTL. If Keycloak is unreachable, existing valid JWTs continue to work for read-only operations.

### 4.3 ClickHouse HA Detail

- **Shard Strategy:** Start with 1 shard / 3 replicas for data under 10TB. Add shards at 10TB increments.
- **Replication:** Synchronous for fact tables (`insert_quorum=2`); asynchronous for staging tables.
- **Keeper:** Use ClickHouse Keeper (replaces ZooKeeper). 3 Keeper nodes in separate availability zones.
- **Backup:** Daily incremental to S3 via `clickhouse-backup`. Full backup weekly. Retention: 30 days.

---

## 5. Security Architecture

### 5.1 Defense-in-Depth Model

| Layer | Control | Implementation |
|---|---|---|
| Network | Kubernetes NetworkPolicy | Explicit allow-list between namespaces; deny-all default |
| Network | Ingress firewall | Only 443 (HTTPS) and 8443 (Keycloak admin) exposed externally |
| Transport | TLS 1.3 everywhere | cert-manager with Let's Encrypt or internal CA; 60-day auto-rotation |
| Transport | mTLS internal | Istio/Linkerd service mesh or K8s-native mTLS |
| Application | Keycloak OIDC/OAuth2 | All user-facing apps require valid JWT; service accounts for backend |
| Application | Rate limiting | Kong enforces per-user and per-IP limits |
| Data | Row-Level Security | Cube `security_context` with Keycloak JWT claims |
| Data | Encryption at rest | ClickHouse encrypted disks; PostgreSQL TDE; K8s etcd encryption |
| Data | Column-level masking | Cube view layer masks PII fields based on role claims |

### 5.2 Network Policy Design

Default **deny-all** policy with explicit allowances. Each component runs in a dedicated namespace:

```
Namespace: openinsight-gateway
  Contains: Kong / NGINX
  Ingress:  External (port 443)
  Egress:   openinsight-app, openinsight-auth

Namespace: openinsight-auth
  Contains: Keycloak
  Ingress:  openinsight-gateway, all app namespaces
  Egress:   openinsight-data (Keycloak DB)

Namespace: openinsight-app
  Contains: Superset, Cube API, Airflow UI
  Ingress:  openinsight-gateway
  Egress:   openinsight-query, openinsight-auth

Namespace: openinsight-query
  Contains: Trino, Cube Store
  Ingress:  openinsight-app
  Egress:   openinsight-data

Namespace: openinsight-data
  Contains: ClickHouse, PostgreSQL, Kafka, Redis
  Ingress:  openinsight-query, openinsight-pipeline
  Egress:   NONE (no external access)

Namespace: openinsight-pipeline
  Contains: Hop, Airflow workers, dbt
  Ingress:  openinsight-app (Airflow UI)
  Egress:   openinsight-data, external data sources

Namespace: openinsight-observe
  Contains: Prometheus, Grafana, Loki, Jaeger
  Ingress:  All namespaces (metrics scraping)
  Egress:   Alerting endpoints (email, Slack, PagerDuty)
```

### 5.3 Keycloak Security Configuration

| Setting | Value |
|---|---|
| Access token lifetime | 5 minutes |
| Refresh token lifetime | 30 minutes |
| Offline tokens | Disabled by default |
| Token content | Minimal claims (`sub`, `groups`, `roles`). Extended claims via userinfo endpoint only. |
| Brute force protection | Lockout after 5 failed attempts; 15-min cooldown; permanent after 20 |
| Password policy | Min 12 chars, 1 upper, 1 number, 1 special. History: last 5 |
| Max concurrent sessions | 5 per user |
| Idle timeout | 30 minutes |
| Max session lifetime | 10 hours |
| Admin console access | Internal network only (NetworkPolicy). MFA required for all admin accounts |

### 5.4 Secrets Management

All secrets managed via Kubernetes **Sealed Secrets** (or HashiCorp Vault for enterprise):

| Secret Category | Rotation Period | Management |
|---|---|---|
| Database passwords | 90 days | Sealed Secrets + CronJob rotation script |
| Keycloak client secrets | 180 days | Sealed Secrets |
| TLS certificates | 60 days | cert-manager (automated) |
| Service account tokens | 90 days | K8s projected volume tokens |
| API keys | 180 days | Sealed Secrets |

**Access control:** Secrets are namespace-scoped. Only pods in the same namespace can mount a secret. RBAC restricts human access to production secrets.

**Audit:** Kubernetes audit logging enabled for all Secret read/write operations. Alerts on unexpected access patterns.

### 5.5 Data Classification

| Classification | Examples | Storage | Access | Masking |
|---|---|---|---|---|
| Public | Product catalog, published reports | ClickHouse (standard) | All authenticated users | None |
| Internal | Sales figures, operational metrics | ClickHouse (standard) | Role-based (`data-analyst+`) | None |
| Confidential | Employee data, financial details | ClickHouse (encrypted) | Department-restricted RLS | Column masking for non-owners |
| Restricted | PII, health data, passwords | PostgreSQL (TDE) | Named individuals only | Full masking; audit logged |

---

## 6. Observability Architecture

### 6.1 Metrics (Prometheus + Grafana)

| Component | Metrics Source | Key Metrics |
|---|---|---|
| Cube | Custom Prometheus exporter | Query latency P50/P95/P99, cache hit ratio, active connections, pre-agg refresh time |
| Trino | JMX exporter | Query count, failed queries, running queries, memory utilization |
| ClickHouse | Native `/metrics` endpoint | Insert rows/s, query latency, merge operations, replication lag |
| PostgreSQL | `postgres_exporter` | Active connections, transaction rate, replication lag |
| Keycloak | Micrometer metrics | Login success/failure rate, active sessions, token issuance rate |
| Kafka | JMX exporter | Consumer lag, partition count, ISR shrink rate |
| Airflow | StatsD exporter | DAG run duration, task success/failure rate, scheduler heartbeat |
| Redis | `redis_exporter` | Memory usage, eviction rate, connected clients |

### 6.2 Log Aggregation (Grafana Loki)

- **Format:** All components output JSON structured logs with fields: `timestamp`, `level`, `service`, `trace_id`, `user_id`, `message`.
- **Collection:** Promtail DaemonSet ships logs to Loki.
- **Retention:** 7 days hot (SSD), 90 days cold (S3-compatible object storage).
- **Alert rules:** ERROR rate > 10/min per service; auth failures > 50/hour; query timeout rate > 5%.

### 6.3 Distributed Tracing (Jaeger / Tempo)

- **Propagation:** W3C TraceContext headers through Kong → Superset → Cube → Trino → ClickHouse.
- **Sampling:** 100% for errors, 10% for successes in production.
- **Storage:** Grafana Tempo with S3 backend. Retention: 7 days.

### 6.4 Data Quality Monitoring

Three checkpoints in the pipeline:

1. **Post-Ingestion (Hop):** Row count validation, null percentage checks, schema conformance. Failures trigger Airflow SLA alerts.
2. **Post-Transform (dbt):** dbt tests (`unique`, `not_null`, `accepted_values`, `relationships`). Great Expectations for distribution and anomaly tests.
3. **Pre-Serve (Cube):** Pre-aggregation freshness checks. If source data older than threshold, Cube returns `X-Stale-Data: true` header.

---

## 7. CI/CD & Development Strategy

### 7.1 Repository Structure

```
openinsight/
├── infrastructure/
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── modules/
│       │   ├── vpc/
│       │   ├── eks/        (or gke/, aks/)
│       │   ├── rds/
│       │   └── s3/
│       └── env/
│           ├── dev.tfvars
│           ├── staging.tfvars
│           └── prod.tfvars
├── helm/
│   ├── Chart.yaml
│   ├── values.yaml          # Base (shared)
│   ├── values-dev.yaml      # Dev overrides
│   ├── values-staging.yaml  # Staging overrides
│   ├── values-prod.yaml     # Prod overrides
│   ├── charts/
│   │   ├── keycloak/
│   │   ├── superset/
│   │   ├── cube/
│   │   ├── trino/
│   │   ├── clickhouse/
│   │   ├── postgresql/
│   │   ├── kafka/
│   │   ├── redis/
│   │   ├── airflow/
│   │   ├── hop/
│   │   ├── kong/
│   │   ├── datahub/
│   │   ├── loki/
│   │   ├── jaeger/
│   │   └── monitoring/      # Prometheus + Grafana
│   └── templates/
│       ├── namespace.yaml
│       ├── networkpolicy.yaml
│       ├── ingress.yaml
│       └── cert-manager.yaml
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml          # Template — secrets injected at runtime
│   ├── packages.yml
│   ├── models/
│   │   ├── staging/          # stg_*.sql — source-conformed
│   │   ├── intermediate/     # int_*.sql — business logic joins
│   │   └── mart/             # dim_*.sql, fct_*.sql — analytics-ready
│   ├── tests/
│   ├── macros/
│   ├── seeds/
│   └── snapshots/
├── cube/
│   ├── schema/               # *.yml — auto-generated from dbt manifest
│   ├── cube.js               # Runtime config (dataSource routing, caching)
│   └── .env.template
├── airflow/
│   └── dags/
│       ├── dag_hop_ingest.py
│       ├── dag_dbt_transform.py
│       ├── dag_data_quality.py
│       └── dag_cube_refresh.py
├── keycloak/
│   ├── realm-openinsight.json
│   └── spi/                  # Custom Event Listener SPI for cache invalidation
├── superset/
│   ├── superset_config.py
│   └── dashboards/           # Exported dashboard JSON
├── scripts/
│   ├── dbt-to-cube-sync.py
│   ├── keycloak-cache-invalidation-listener.py
│   ├── clickhouse-kafka-tables.sql
│   ├── seed.sh               # Load sample data for local dev
│   ├── dr-backup.sh
│   ├── dr-restore.sh
│   └── dr-drill.sh
├── tests/
│   ├── integration/
│   │   ├── test_e2e_pipeline.py
│   │   ├── test_rls.py
│   │   └── test_auth.py
│   └── load/
│       ├── k6_dashboard.js
│       ├── k6_cube_api.js
│       └── k6_mixed.js
├── monitoring/
│   ├── grafana-dashboards/   # JSON dashboard definitions
│   ├── prometheus-rules.yaml
│   └── alertmanager.yaml
├── docs/
│   ├── adr/                  # Architecture Decision Records
│   ├── runbooks/
│   └── onboarding.md
├── docker-compose.yml        # Local dev environment
├── .github/workflows/
│   ├── ci.yml
│   ├── cd-dev.yml
│   ├── cd-staging.yml
│   └── cd-prod.yml
├── ARCHITECTURE.md           # ← THIS FILE
└── README.md
```

### 7.2 CI Pipeline

Every pull request triggers:

| Stage | Tool | Checks | Blocking? |
|---|---|---|---|
| Lint | yamllint, eslint, sqlfluff | YAML syntax, JS lint, SQL formatting | Yes |
| Helm Validate | `helm lint`, `helm template` | Chart syntax, template rendering | Yes |
| Terraform Validate | `terraform validate`, tflint | HCL syntax, provider compat | Yes |
| dbt Compile | `dbt compile` | Model SQL compilation | Yes |
| dbt Test (Unit) | `dbt test --select tag:unit` | Schema tests on fixtures | Yes |
| Cube Validate | Custom validator script | Schema YAML syntax, refs | Yes |
| Security Scan | trivy, checkov | CVEs, IaC misconfigurations | Yes (Critical/High) |
| Integration Test | docker-compose + pytest | E2E on sample data | Yes |

### 7.3 CD Pipeline

GitOps model with environment promotion:

- **Development:** Auto-deploy on merge to `develop`. Single-replica, reduced resources. Integration tests run.
- **Staging:** Manual promotion. Full replica count with anonymized production-like data. Load tests run here.
- **Production:** Manual approval gate. Blue-green for stateless (Superset, Cube, Trino workers). Rolling update for stateful (ClickHouse, PostgreSQL).

### 7.4 Load Testing

Tests run in staging using **k6**:

| Scenario | Users | Duration | Pass Criteria |
|---|---|---|---|
| Dashboard browse (cached) | 500 concurrent | 10 min | P95 < 1s, error < 0.1% |
| Dashboard browse (uncached) | 100 concurrent | 10 min | P95 < 5s, error < 0.5% |
| SQL Lab queries | 50 concurrent | 10 min | P95 < 10s, error < 1% |
| Cube API (REST) | 200 concurrent | 10 min | P95 < 200ms, error < 0.1% |
| Mixed workload | 500 concurrent | 30 min | All SLA targets met |

### 7.5 Local Development Environment

`docker-compose.yml` mirrors production at reduced scale:

- **Core stack (always running):** PostgreSQL, ClickHouse (single node), Keycloak, Redis → ~4 GB RAM
- **App stack (on-demand):** Superset, Cube (dev mode), Trino (single coordinator) → ~4 GB RAM
- **Pipeline stack (on-demand):** Airflow (LocalExecutor), dbt CLI → ~2 GB RAM
- **Seed data:** `scripts/seed.sh` loads 10 MB sample dataset covering all dbt models and Cube schemas
- **Total developer machine requirement:** 16 GB RAM, 4 CPU cores, 20 GB disk

---

## 8. Disaster Recovery

### 8.1 RPO / RTO Targets

| Component | RPO | RTO | Backup Method | Recovery Method |
|---|---|---|---|---|
| ClickHouse | 1 hour | 2 hours | `clickhouse-backup` to S3 (hourly incremental, daily full) | Restore from S3; replay Kafka for gap |
| PostgreSQL | 5 min | 30 min | WAL archiving to S3 (continuous) + `pg_basebackup` (daily) | Patroni auto-failover; PITR from WAL |
| Keycloak DB | 5 min | 30 min | Shared PostgreSQL backup | Restore PostgreSQL; Keycloak reconnects |
| Keycloak Config | On change | 15 min | Realm export in Git (CI-triggered) | Import realm JSON |
| dbt Models | On change | 5 min | Git repository | `git clone` + `dbt run` |
| Cube Schemas | On change | 5 min | Git repository | `git clone` + Cube restart |
| Airflow DAGs | On change | 5 min | Git repository | `git clone`; Airflow auto-syncs |
| Kafka | 0 (replicated) | < 30s | 3x replication factor | ISR leader election |
| Superset Dashboards | Daily | 1 hour | `superset export-dashboards` to Git | Import from Git |

### 8.2 DR Drill Schedule

- **Monthly:** PostgreSQL failover test (Patroni switchover). ClickHouse replica promotion.
- **Quarterly:** Full cluster restore from backup. Measure actual RTO against targets.
- **Annually:** Full disaster simulation (primary cluster destroyed). Cross-region recovery if applicable.

---

## 9. Phased Implementation Plan

### Phase 1: Foundation — Weeks 1-3

**Goal:** Core infrastructure operational with basic data flow.

| Task | Claude Code Generates | Manual Validation |
|---|---|---|
| 1.1 K8s Cluster | Terraform modules (EKS/GKE/AKS, VPC, security groups) | Cloud account setup, IAM, cost review |
| 1.2 PostgreSQL HA | Helm values (Patroni), backup CronJob, PVC config | Connection test, failover drill |
| 1.3 ClickHouse Cluster | Helm values (ClickHouse Operator, Keeper, ReplicatedMergeTree) | Perf baseline, disk sizing |
| 1.4 Keycloak HA | Helm values, realm JSON, OIDC client configs | LDAP integration, admin MFA |
| 1.5 Redis Sentinel | Helm values, eviction policy, memory limits | Connection from Cube verified |
| 1.6 Kafka | Helm values, topic configs, retention policies | Producer/consumer smoke test |
| 1.7 Networking | NetworkPolicy YAMLs, Ingress, cert-manager | Security team review |

### Phase 2: Data Pipeline — Weeks 4-6

**Goal:** End-to-end data flow from source to transformed tables.

| Task | Claude Code Generates | Manual Validation |
|---|---|---|
| 2.1 Apache Hop | Helm deployment, sample pipeline configs | Source connectivity, credentials |
| 2.2 Kafka→ClickHouse | Kafka Engine DDL, materialized views | Data integrity checks |
| 2.3 dbt Project | Skeleton, staging/mart models, tests, profiles.yml | Business logic review |
| 2.4 Airflow | Helm values, DAGs for Hop + dbt, alerting | Schedule validation, SLA monitoring |
| 2.5 Trino | Helm values, catalog configs (CH + PG) | Pushdown verification, perf baseline |

### Phase 3: Semantic & Visualization — Weeks 7-9

**Goal:** Business users access dashboards with proper access control.

| Task | Claude Code Generates | Manual Validation |
|---|---|---|
| 3.1 Cube Cluster | Helm values (API + Store + Worker), schema from dbt | Schema review, pre-agg strategy |
| 3.2 Cache System | Redis config, invalidation listener code | Cache hit ratio under load |
| 3.3 Superset | Helm values, OIDC config, database connection | Dashboard UX, role mapping |
| 3.4 RLS | Cube security_context, group-to-data mapping | Cross-user isolation testing |
| 3.5 API Gateway | Kong/NGINX Helm values, rate limits, routing | Pen testing, rate limit validation |

### Phase 4: Governance & Hardening — Weeks 10-12

**Goal:** Production-ready with full observability and governance.

| Task | Claude Code Generates | Manual Validation |
|---|---|---|
| 4.1 Observability | Prometheus configs, Grafana dashboards, Loki, Jaeger | Alert threshold tuning |
| 4.2 DataHub | Helm values, ingestion configs | Lineage accuracy |
| 4.3 Load Testing | k6 scripts, test data generation | Performance analysis |
| 4.4 DR Testing | Backup/restore scripts, runbooks | Actual DR drill execution |
| 4.5 Security Audit | CVE scan configs, RBAC audit scripts | Pen test, compliance review |
| 4.6 Documentation | ADRs, runbooks, onboarding guide | Technical writing review |

---

## 10. Claude Code Automation Specification

### 10.1 Automation Tiers

| Tier | Description | Artifacts | Human Review |
|---|---|---|---|
| **Tier 1: Full Auto** | Generate and deploy with minimal config | Helm charts, K8s manifests, Prometheus configs, CI/CD pipelines, NetworkPolicies | Config values only |
| **Tier 2: Generate + Validate** | Auto-generate; requires domain review | dbt models, Cube schemas, Airflow DAGs, Keycloak realm, Trino catalogs | Business logic, security |
| **Tier 3: Scaffold + Manual** | Generate templates; human completes | DR scripts, load tests, security audit, LDAP mapping | Execution and sign-off |

### 10.2 Required Input Parameters

Before generating artifacts, Claude Code must collect these decisions:

| Parameter | Options | Default |
|---|---|---|
| Cloud Provider | AWS / GCP / Azure / On-Prem | AWS (EKS) |
| Cluster Size | Small (dev) / Medium (pilot) / Large (prod) | Medium |
| Data Volume (Year 1) | < 1TB / 1-10TB / 10-100TB / 100TB+ | 1-10TB |
| Auth Source | LDAP / Active Directory / SAML IdP / Standalone | LDAP |
| Compliance | GDPR / SOC2 / HIPAA / BSI / None | GDPR |
| Git Platform | GitHub / GitLab / Bitbucket | GitHub |

### 10.3 File Generation Manifest

Total files generated: ~100 across 4 phases.

**Phase 1 — Infrastructure:** ~37 files (Terraform modules, Helm charts, NetworkPolicies, cert-manager, Keycloak realm)

**Phase 2 — Data Pipeline:** ~25 files (Hop config, Kafka DDL, dbt project, Airflow DAGs, Trino catalogs)

**Phase 3 — Semantic & Viz:** ~18 files (Cube schema + config, Superset config, Kong, invalidation listener)

**Phase 4 — Governance & Ops:** ~20 files (DataHub, Grafana dashboards, Prometheus rules, k6 scripts, DR scripts, CI/CD workflows)

### 10.4 Build Commands Reference

```bash
# Phase 1: Provision infrastructure
cd infrastructure/terraform && terraform init && terraform plan -var-file=env/dev.tfvars
cd ../../helm && helm dependency update && helm install openinsight . -f values-dev.yaml

# Phase 2: Initialize data pipeline
cd dbt && dbt deps && dbt seed && dbt run && dbt test
kubectl apply -f ../scripts/clickhouse-kafka-tables.sql

# Phase 3: Deploy semantic layer
python scripts/dbt-to-cube-sync.py   # Generate Cube schemas from dbt manifest
helm upgrade openinsight helm/ -f helm/values-dev.yaml

# Phase 4: Deploy observability
helm upgrade openinsight helm/ -f helm/values-dev.yaml --set datahub.enabled=true --set loki.enabled=true

# Local development
docker-compose up -d core   # PostgreSQL, ClickHouse, Keycloak, Redis
docker-compose up -d app    # Superset, Cube, Trino
./scripts/seed.sh           # Load sample data

# Testing
dbt test --select tag:unit
pytest tests/integration/
k6 run tests/load/k6_mixed.js
./scripts/dr-drill.sh
```

---

## 11. Operational Requirements

### 11.1 Team Structure

| Role | Count | Responsibilities |
|---|---|---|
| Platform Engineer | 2 FTE | Kubernetes, Helm, Terraform, monitoring, DR |
| Data Engineer | 2 FTE | dbt, Airflow, Hop, ClickHouse, data modeling |
| Analytics Engineer | 1 FTE | Cube schemas, Superset dashboards, metrics |
| Security Engineer | 0.5 FTE | Network policies, secret rotation, audits |
| DevOps / SRE | 1 FTE | CI/CD, releases, incident response |

### 11.2 Operational Toil

| Activity | Frequency | Time | Automation Potential |
|---|---|---|---|
| Log review and triage | Daily | 30 min | High (Loki alerts) |
| Backup verification | Daily | 15 min | High (automated checks) |
| Performance monitoring | Daily | 30 min | High (Grafana dashboards) |
| dbt model updates | Weekly | 2-4 hours | Medium (CI validates) |
| Security patching | Weekly | 1-2 hours | Medium (Trivy + auto-PR) |
| ClickHouse maintenance | Weekly | 1-2 hours | Low (manual tuning) |
| Keycloak user admin | Weekly | 30 min | High (LDAP sync) |
| K8s cluster upgrades | Quarterly | 4-8 hours | Low (manual with runbook) |
| DR drill | Quarterly | 4-8 hours | Low (scripted but manual) |

---

## 12. Architecture Decision Log

| ADR # | Decision | Rationale | Rejected Alternative |
|---|---|---|---|
| ADR-001 | Add Kafka as message backbone | Backpressure, CDC replay, decoupling | Direct Hop→ClickHouse (no backpressure) |
| ADR-002 | Add Redis Sentinel for Cube cache | Distributed cache, pub/sub invalidation | Cube built-in cache (no invalidation API) |
| ADR-003 | Add API Gateway (Kong/NGINX) | Centralized rate limiting, TLS, routing | Per-service Ingress (no rate limiting) |
| ADR-004 | Add Grafana Loki for logging | Lightweight, Grafana-native | ELK Stack (too complex operationally) |
| ADR-005 | Add Jaeger/Tempo for tracing | Essential for cross-service debugging | No tracing (cannot debug production) |
| ADR-006 | Cube cluster mode + Cube Store | Required for 500-user target | Single Cube (SPOF, no horizontal scale) |
| ADR-007 | Event-driven cache invalidation | Resolves data leakage risk | Short cache TTL (degrades performance) |
| ADR-008 | Patroni for PostgreSQL HA | Auto failover, K8s-native | Manual failover (exceeds 30-min RTO) |
| ADR-009 | Namespace-based network isolation | Defense-in-depth, blast radius | Flat network (lateral movement risk) |
| ADR-010 | Defer DataHub to Phase 4 | Reduces initial complexity | Include Phase 1 (too much integration) |
| ADR-011 | n8n scope: alert routing only | Prevents Airflow overlap | Remove n8n (useful for webhooks) |
| ADR-012 | Monorepo structure | Simpler CI/CD, atomic changes | Multi-repo (cross-repo dependency pain) |

---

## 13. Appendices

### 13.1 Component Version Pinning

| Component | Target Version | Pin Strategy | Upgrade Cadence |
|---|---|---|---|
| Keycloak | 24.x | Major pin; patch auto | Quarterly |
| Superset | 3.x | Minor pin | Quarterly |
| Cube | 0.35.x | Minor pin (pre-1.0) | Monthly review |
| dbt Core | 1.7.x | Minor pin | Quarterly |
| Trino | 435+ | Major pin; test connectors | Quarterly |
| ClickHouse | 24.x | Major pin | Semi-annual |
| PostgreSQL | 16.x | Major pin | Annual |
| Hop | 2.x | Major pin | Quarterly |
| Airflow | 2.8.x | Minor pin | Quarterly |
| Kafka / Redpanda | 3.6.x / 23.x | Major pin | Semi-annual |
| Redis | 7.x | Major pin | Annual |
| DataHub | 0.13.x | Minor pin | Quarterly |

### 13.2 Resource Sizing Guide

| Environment | Nodes | CPU | RAM | Storage | Est. Cloud Cost/mo |
|---|---|---|---|---|---|
| Development | 3 | 24 vCPU | 96 GB | 500 GB SSD | $800-1,200 |
| Staging | 4 | 48 vCPU | 192 GB | 2 TB SSD | $2,000-3,000 |
| Production (Small) | 6 | 96 vCPU | 384 GB | 10 TB NVMe | $6,000-9,000 |
| Production (Large) | 10+ | 160+ vCPU | 640+ GB | 50+ TB NVMe | $15,000-25,000 |

### 13.3 PRD Open Questions — Resolved

| PRD Question | Resolution |
|---|---|
| Multi-tenancy: realm or single realm? | Single realm with group-based isolation. Multi-realm adds disproportionate ops overhead for initial deployment. |
| Air-gapped deployment? | Helm charts support offline install with pre-pulled images. Air-gap guide deferred to Phase 4 docs. |
| n8n: core or add-on? | Add-on, scoped to alert routing and webhooks (ADR-011). Not in critical data path. |
| Pricing model? | Out of scope. Recommendation: per-node licensing aligns with infrastructure value prop. |
| Existing Keycloak deployments? | Support external Keycloak as IdP via OIDC federation. Standalone realm config provided; federation is Phase 4. |

---

*End of Document*
