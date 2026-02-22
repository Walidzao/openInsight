#!/usr/bin/env bash
set -euo pipefail

# OpenInsight - Redpanda/Kafka Topic Initialization
# Usage: ./scripts/init-redpanda.sh
#
# Creates all topics required by the platform with appropriate
# retention and partition settings. Idempotent — safe to re-run.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== OpenInsight Topic Initialization ==="
echo ""

RPK="docker compose -f $PROJECT_ROOT/docker-compose.yml exec -T redpanda rpk"

create_topic() {
    local topic=$1
    local partitions=$2
    local retention_ms=$3
    local description=$4

    printf "  %-40s" "$topic"
    if $RPK topic create "$topic" \
        --partitions "$partitions" \
        --topic-config "retention.ms=$retention_ms" \
        2>&1 | grep -q "TOPIC_ALREADY_EXISTS"; then
        echo "EXISTS"
    else
        echo "CREATED  (partitions=$partitions, retention=${retention_ms}ms)"
    fi
}

echo "--- Cache Invalidation ---"
# Keycloak user/group change events for Cube cache eviction
# Low volume, short retention — only need recent events
create_topic "keycloak.events" 3 86400000 "Keycloak user/group change events (1d retention)"

echo ""
echo "--- Data Ingestion (Hop output) ---"
# Raw ingestion topics — Hop writes here, ClickHouse Kafka Engine reads
# Higher partitions for parallelism, 7-day retention for replay
create_topic "ingest.raw.events" 6 604800000 "Raw event data from sources (7d retention)"
create_topic "ingest.raw.transactions" 6 604800000 "Raw transaction data from sources (7d retention)"
create_topic "ingest.raw.dimensions" 3 604800000 "Raw dimension/reference data (7d retention)"

echo ""
echo "--- Dead Letter ---"
# Failed messages land here for inspection and replay
# Long retention so nothing is lost
create_topic "dlq.ingest" 3 2592000000 "Dead letter queue for ingestion failures (30d retention)"
create_topic "dlq.events" 1 2592000000 "Dead letter queue for event processing failures (30d retention)"

echo ""
echo "--- Pipeline Coordination ---"
# Signals between pipeline stages (e.g., Airflow notifying dbt run complete)
create_topic "pipeline.status" 1 259200000 "Pipeline run status events (3d retention)"

echo ""
echo "--- Verifying topics ---"
$RPK topic list

echo ""
echo "=== Topic initialization complete ==="
