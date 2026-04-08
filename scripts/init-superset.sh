#!/bin/bash
set -e

echo "Starting Superset initialization..."

# Install ClickHouse driver
docker compose exec -T superset pip install clickhouse-connect

# Run database setup
docker compose exec -T superset superset db upgrade

# Create default admin user (local fallback)
docker compose exec -T superset superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@openinsight.local \
    --password admin \
    || echo "Admin user already exists."

# Initialize roles and permissions
docker compose exec -T superset superset init

echo ""
echo "Superset initialization complete."
echo ""
echo "Add ClickHouse datasource via UI:"
echo "  1. Open http://localhost:${SUPERSET_PORT:-8088}"
echo "  2. Log in: admin / admin"
echo "  3. Settings → Database Connections → + Database"
echo "  4. Select ClickHouse Connect"
echo "  5. SQLAlchemy URI: clickhousedb+connect://openinsight:openinsight_dev@clickhouse:8123/openinsight"
