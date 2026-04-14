#!/bin/bash
set -e

echo "=== OpenInsight Superset Initialization ==="
echo ""

# Drivers (clickhouse-connect, Authlib) are baked into the image via Dockerfile

# Run database migrations
echo "[1/3] Running database migrations..."
docker compose exec -T superset superset db upgrade

# Create fallback admin user (DB auth — useful if Keycloak is down)
echo "[2/3] Creating fallback admin user..."
docker compose exec -T superset superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@openinsight.local \
    --password admin \
    || echo "  Admin user already exists."

# Initialize roles and permissions
echo "[3/3] Initializing roles and permissions..."
docker compose exec -T superset superset init

echo ""
echo "=== Superset initialization complete ==="
echo ""
echo "Auth: Keycloak OIDC (realm: openinsight, client: superset)"
echo "Login: http://localhost:${SUPERSET_PORT:-8088}/login/keycloak"
echo ""
echo "Test users:"
echo "  alice.finance    / Test123!DevOps  → Alpha role (SQL Lab + dashboards)"
echo "  bob.hr           / Test123!DevOps  → Alpha role"
echo "  eve.viewer       / Test123!DevOps  → Gamma role (view only)"
echo "  dave.executive   / Test123!DevOps  → Admin role"
echo ""
echo "Add ClickHouse datasource after login:"
echo "  Settings → Database Connections → + Database → ClickHouse Connect"
echo "  URI: clickhousedb+connect://openinsight:openinsight_dev@clickhouse:8123/openinsight"
