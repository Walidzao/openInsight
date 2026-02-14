#!/usr/bin/env bash
set -euo pipefail

# OpenInsight Local Dev - Seed Data Loader
# Usage: ./scripts/seed.sh
#
# Prerequisites:
#   - docker compose core stack running
#   - .env file configured (or defaults used)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.env"
fi

# Defaults
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
CLICKHOUSE_HTTP_PORT="${CLICKHOUSE_HTTP_PORT:-8123}"
CLICKHOUSE_USER="${CLICKHOUSE_USER:-openinsight}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-openinsight_dev}"

echo "=== OpenInsight Seed Data Loader ==="
echo ""

# Check connectivity
echo "[1/4] Checking PostgreSQL connectivity..."
docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres pg_isready -U "${POSTGRES_USER:-openinsight}" || {
    echo "ERROR: PostgreSQL is not ready. Run 'docker compose up -d' first."
    exit 1
}

echo "[2/4] Checking ClickHouse connectivity..."
curl -sf "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_HTTP_PORT}/ping" > /dev/null || {
    echo "ERROR: ClickHouse is not ready. Run 'docker compose up -d' first."
    exit 1
}

echo "[3/4] Seeding PostgreSQL..."
# TODO: Add PostgreSQL seed data (dimension tables, lookup tables)
echo "  (no seed data defined yet -- will be added with dbt models)"

echo "[4/4] Seeding ClickHouse..."
# TODO: Add ClickHouse seed data (fact tables, sample events)
echo "  (no seed data defined yet -- will be added with dbt models)"

echo ""
echo "=== Seed complete ==="
