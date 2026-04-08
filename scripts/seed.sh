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
PG_USER="${POSTGRES_USER:-openinsight}"
PG_DB="${POSTGRES_DB:-openinsight}"
CH_HOST="${CLICKHOUSE_HOST:-localhost}"
CH_PORT="${CLICKHOUSE_HTTP_PORT:-8123}"
CH_USER="${CLICKHOUSE_USER:-openinsight}"
CH_PASS="${CLICKHOUSE_PASSWORD:-openinsight_dev}"

echo "=== OpenInsight Seed Data Loader ==="
echo ""

# Check connectivity
echo "[1/5] Checking PostgreSQL connectivity..."
docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres pg_isready -U "$PG_USER" || {
    echo "ERROR: PostgreSQL is not ready. Run 'docker compose up -d' first."
    exit 1
}

echo "[2/5] Checking ClickHouse connectivity..."
curl -sf "http://${CH_HOST}:${CH_PORT}/ping" > /dev/null || {
    echo "ERROR: ClickHouse is not ready. Run 'docker compose up -d' first."
    exit 1
}

echo "[3/5] Initializing Redpanda topics..."
if docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T redpanda rpk cluster health > /dev/null 2>&1; then
    bash "$SCRIPT_DIR/init-redpanda.sh"
else
    echo "  Redpanda not running — skipping topic init"
fi

echo "[4/5] Seeding PostgreSQL (dimensions, customers)..."
docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    psql -U "$PG_USER" -d "$PG_DB" -f /dev/stdin < "$SCRIPT_DIR/seed-postgres.sql"
echo "  PostgreSQL seed complete"

echo "[5/5] Seeding ClickHouse (facts, events)..."
# ClickHouse HTTP API requires one statement per request.
# Split SQL file on semicolons and send each statement individually.
while IFS= read -r stmt; do
    # Skip empty statements and comments
    trimmed=$(echo "$stmt" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [ -n "$trimmed" ] && ! echo "$trimmed" | grep -q '^--'; then
        curl -sf "http://${CH_HOST}:${CH_PORT}/" \
            --user "${CH_USER}:${CH_PASS}" \
            --data "$trimmed" || {
            echo "  ERROR executing: ${trimmed:0:80}..."
            exit 1
        }
    fi
done < <(sed 's/--.*$//' "$SCRIPT_DIR/seed-clickhouse.sql" | tr '\n' ' ' | sed 's/;/;\n/g')
echo "  ClickHouse seed complete"

echo "  Applying ClickHouse Kafka Engine MVs..."
while IFS= read -r stmt; do
    trimmed=$(echo "$stmt" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [ -n "$trimmed" ] && ! echo "$trimmed" | grep -q '^--'; then
        curl -sf "http://${CH_HOST}:${CH_PORT}/" \
            --user "${CH_USER}:${CH_PASS}" \
            --data "$trimmed" || {
            echo "  ERROR executing Kafka Engine DDL: ${trimmed:0:80}..."
            exit 1
        }
    fi
done < <(sed 's/--.*$//' "$SCRIPT_DIR/clickhouse-kafka-tables.sql" | tr '\n' ' ' | sed 's/;/;\n/g')
echo "  Kafka DDL applied."

echo ""
echo "--- Verification ---"
PG_COUNT=$(docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    psql -U "$PG_USER" -d "$PG_DB" -t -c "SELECT count(*) FROM customers;" 2>/dev/null | tr -d ' ')
CH_SALES=$(curl -sf "http://${CH_HOST}:${CH_PORT}/" \
    --user "${CH_USER}:${CH_PASS}" \
    --data "SELECT count() FROM openinsight.fct_sales" 2>/dev/null | tr -d ' ')
CH_EVENTS=$(curl -sf "http://${CH_HOST}:${CH_PORT}/" \
    --user "${CH_USER}:${CH_PASS}" \
    --data "SELECT count() FROM openinsight.fct_events" 2>/dev/null | tr -d ' ')

echo "  PostgreSQL customers: ${PG_COUNT:-0} rows"
echo "  ClickHouse fct_sales: ${CH_SALES:-0} rows"
echo "  ClickHouse fct_events: ${CH_EVENTS:-0} rows"

echo ""
echo "=== Seed complete ==="
