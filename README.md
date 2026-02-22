# OpenInsight

Enterprise-grade BI platform built on open-source components.

## Quick Start (Local Development)

### Prerequisites

- Docker Desktop (or Docker Engine + Docker Compose v2)
- 16 GB RAM, 4 CPU cores, 20 GB free disk
- Git

### Setup

1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd openinsight
   ```

2. Create environment file:
   ```bash
   cp .env.example .env
   ```

3. Start core services:
   ```bash
   docker compose up -d
   ```

4. Verify services are running:
   ```bash
   ./scripts/check-health.sh
   ```

5. (Optional) Load sample data:
   ```bash
   ./scripts/seed.sh
   ```

6. (Optional) Start pipeline stack (Apache Hop visual ETL):
   ```bash
   docker compose --profile pipeline up -d
   ```

### Service Endpoints

| Service | URL | Credentials |
|---|---|---|
| PostgreSQL | `localhost:5432` | openinsight / openinsight_dev |
| ClickHouse (HTTP) | `http://localhost:8123` | openinsight / openinsight_dev |
| ClickHouse (Native) | `localhost:9000` | openinsight / openinsight_dev |
| Keycloak Admin | `http://localhost:8080` | admin / admin |
| Redis | `localhost:6379` | (no auth in dev) |
| Redpanda (Kafka API) | `localhost:19092` | (no auth in dev) |
| Redpanda Console | `http://localhost:8888` | (no auth) |
| Hop Web (pipeline) | `http://localhost:8090/ui` | (no auth) |

### Keycloak Test Users

| Username | Password | Group | Role |
|---|---|---|---|
| admin | Admin123!DevOps | — | Platform admin |
| alice.finance | Test123!DevOps | Finance | Data analyst |
| bob.hr | Test123!DevOps | HR | Data analyst |
| carol.engineering | Test123!DevOps | Engineering | Data engineer |
| dave.executive | Test123!DevOps | Executive | Admin |
| eve.viewer | Test123!DevOps | Finance | Viewer only |

### Keycloak Admin Console

Keycloak is the central identity provider for all OpenInsight applications. Manage users, roles, groups, and OIDC clients at:

- **URL:** `http://localhost:8080/admin`
- **Credentials:** admin / admin
- **Realm:** Select `openinsight` from the top-left dropdown

### Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical specification.

## Project Structure

```
openinsight/
├── infrastructure/terraform/  # GKE infrastructure (Phase 1)
├── helm/                      # Kubernetes Helm charts
├── dbt/                       # Data transformation models
├── cube/                      # Semantic layer config
├── airflow/dags/              # Orchestration DAGs
├── hop/                       # Apache Hop ETL projects + pipelines
├── keycloak/                  # Realm config + SPI extensions
├── superset/                  # Visualization config
├── scripts/                   # Operational scripts
├── tests/                     # Integration + load tests
├── monitoring/                # Grafana dashboards, Prometheus rules
├── docs/                      # ADRs, runbooks
├── docker-compose.yml         # Local dev environment
└── ARCHITECTURE.md            # Technical specification
```

## License

TBD
