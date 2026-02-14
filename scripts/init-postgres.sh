#!/bin/bash
set -e

# Create additional databases needed by platform components
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE keycloak;
    CREATE DATABASE superset;
    CREATE DATABASE airflow;
    GRANT ALL PRIVILEGES ON DATABASE keycloak TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE superset TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE airflow TO $POSTGRES_USER;
EOSQL

echo "=== OpenInsight: Additional databases created (keycloak, superset, airflow) ==="
