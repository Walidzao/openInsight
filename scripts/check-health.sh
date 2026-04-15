#!/usr/bin/env bash
set -euo pipefail

# OpenInsight - Service Health Check
# Usage: ./scripts/check-health.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.env"
fi

POSTGRES_PORT="${POSTGRES_PORT:-5432}"
CLICKHOUSE_HTTP_PORT="${CLICKHOUSE_HTTP_PORT:-8123}"
KEYCLOAK_PORT="${KEYCLOAK_PORT:-8080}"
REDIS_PORT="${REDIS_PORT:-6379}"

echo "=== OpenInsight Service Health Check ==="
echo ""

FAILED=0

check_service() {
    local name=$1
    local check_cmd=$2
    printf "  %-25s" "$name"
    if eval "$check_cmd" > /dev/null 2>&1; then
        echo "OK"
    else
        echo "FAIL"
        FAILED=$((FAILED + 1))
    fi
}

check_service "PostgreSQL (:$POSTGRES_PORT)" \
    "docker compose -f '$PROJECT_ROOT/docker-compose.yml' exec -T postgres pg_isready -U ${POSTGRES_USER:-openinsight}"

check_service "ClickHouse (:$CLICKHOUSE_HTTP_PORT)" \
    "curl -sf http://localhost:${CLICKHOUSE_HTTP_PORT}/ping"

check_service "Keycloak (:$KEYCLOAK_PORT)" \
    "curl -sf http://localhost:${KEYCLOAK_PORT}/health/ready"

check_service "Redis (:$REDIS_PORT)" \
    "docker compose -f '$PROJECT_ROOT/docker-compose.yml' exec -T redis redis-cli ping"

check_service "Redpanda (:19092)" \
    "docker compose -f '$PROJECT_ROOT/docker-compose.yml' exec -T redpanda rpk cluster health"

check_service "Redpanda Console (:${REDPANDA_CONSOLE_PORT:-8888})" \
    "curl -sf http://localhost:${REDPANDA_CONSOLE_PORT:-8888}/"

# --- Pipeline profile services (conditional) ---
HOP_WEB_PORT="${HOP_WEB_PORT:-8090}"
AIRFLOW_PORT="${AIRFLOW_PORT:-8081}"
if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps --format '{{.Names}}' 2>/dev/null | grep -qE 'hop-web|airflow'; then
    echo ""
    echo "--- Pipeline Stack ---"
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps --format '{{.Names}}' 2>/dev/null | grep -q 'hop-web'; then
        check_service "Hop Web (:$HOP_WEB_PORT)" \
            "curl -sf http://localhost:${HOP_WEB_PORT}/ui"
    fi
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps --format '{{.Names}}' 2>/dev/null | grep -q 'airflow'; then
        check_service "Airflow (:$AIRFLOW_PORT)" \
            "curl -sf http://localhost:${AIRFLOW_PORT}/health | grep -q '\"status\": \"healthy\"'"
    fi
fi

# --- App profile services (conditional) ---
SUPERSET_PORT="${SUPERSET_PORT:-8088}"
TRINO_PORT="${TRINO_PORT:-8085}"
if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps --format '{{.Names}}' 2>/dev/null | grep -qE 'superset|trino'; then
    echo ""
    echo "--- App Stack ---"
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps --format '{{.Names}}' 2>/dev/null | grep -q 'superset'; then
        check_service "Superset (:$SUPERSET_PORT)" \
            "curl -sf http://localhost:${SUPERSET_PORT}/health"
    fi
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps --format '{{.Names}}' 2>/dev/null | grep -q 'trino'; then
        check_service "Trino (:$TRINO_PORT)" \
            "curl -sf http://localhost:${TRINO_PORT}/v1/info | grep -q '\"starting\":false'"
    fi
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "=== All services healthy ==="
else
    echo "=== $FAILED service(s) unhealthy ==="
    exit 1
fi
