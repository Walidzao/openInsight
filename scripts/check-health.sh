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

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "=== All services healthy ==="
else
    echo "=== $FAILED service(s) unhealthy ==="
    exit 1
fi
