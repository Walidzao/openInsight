#!/usr/bin/env bash
set -e

# OpenInsight Airflow Entrypoint
# Runs db migrate + admin user creation, then starts webserver + scheduler
# in the same container (LocalExecutor, single-node dev setup).

echo "[airflow] Running database migrations..."
airflow db migrate

echo "[airflow] Ensuring admin user exists..."
airflow users create \
    --username "${AIRFLOW_ADMIN_USERNAME:-admin}" \
    --password "${AIRFLOW_ADMIN_PASSWORD:-admin}" \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email "${AIRFLOW_ADMIN_EMAIL:-admin@openinsight.local}" \
    2>/dev/null || echo "  Admin user already exists."

echo "[airflow] Starting scheduler in background..."
airflow scheduler &

echo "[airflow] Starting webserver in foreground..."
exec airflow webserver
