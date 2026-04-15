#!/bin/bash
set -e

echo "=== OpenInsight Superset Initialization ==="
echo ""

# Drivers (clickhouse-connect, Authlib) are baked into the image via Dockerfile

# Run database migrations
echo "[1/4] Running database migrations..."
docker compose exec -T superset superset db upgrade

# Create fallback admin user (DB auth — useful if Keycloak is down)
echo "[2/4] Creating fallback admin user..."
docker compose exec -T superset superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@openinsight.local \
    --password admin \
    || echo "  Admin user already exists."

# Initialize roles and permissions
echo "[3/4] Initializing roles and permissions..."
docker compose exec -T superset superset init

# Patch Alpha role: add SQL Lab + TabStateView permissions missing after superset init
echo "[4/5] Patching Alpha role with full SQL Lab permissions..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from flask_appbuilder.models.sqla.interface import SQLAInterface
    from flask_appbuilder.security.sqla.models import (
        Role, PermissionView, ViewMenu, Permission
    )
    alpha = sa_db.session.query(Role).filter_by(name='Alpha').first()
    if not alpha:
        print('  Alpha role not found — skipping.')
    else:
        target_views = ['TabStateView', 'SQLLab', 'SqlLab', 'SQL Lab']
        pvs = (
            sa_db.session.query(PermissionView)
            .join(ViewMenu)
            .filter(ViewMenu.name.in_(target_views))
            .all()
        )
        added = 0
        for pv in pvs:
            if pv not in alpha.permissions:
                alpha.permissions.append(pv)
                added += 1
        sa_db.session.commit()
        print('  Added %d permission(s) to Alpha role.' % added)
"

# Register ClickHouse as a database connection (idempotent)
echo "[5/5] Registering ClickHouse database connection..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from superset.models.core import Database
    existing = sa_db.session.query(Database).filter_by(database_name='ClickHouse').first()
    if existing:
        print('  ClickHouse connection already exists (id=%d).' % existing.id)
    else:
        conn = Database(
            database_name='ClickHouse',
            sqlalchemy_uri='clickhousedb+connect://openinsight:openinsight_dev@clickhouse:8123/openinsight',
            expose_in_sqllab=True,
        )
        sa_db.session.add(conn)
        sa_db.session.commit()
        print('  ClickHouse connection created (id=%d).' % conn.id)
"

echo ""
echo "=== Superset initialization complete (5 steps) ==="
echo ""
echo "Auth: Keycloak OIDC (realm: openinsight, client: superset)"
echo "Login: http://localhost:${SUPERSET_PORT:-8088}/login/keycloak"
echo "Fallback: http://localhost:${SUPERSET_PORT:-8088}/login/ (admin / admin)"
echo ""
echo "Test users (Keycloak SSO):"
echo "  alice.finance    / Test123!DevOps  → Alpha role (SQL Lab + dashboards)"
echo "  bob.hr           / Test123!DevOps  → Alpha role"
echo "  eve.viewer       / Test123!DevOps  → Gamma role (view only)"
echo "  dave.executive   / Test123!DevOps  → Admin role"
echo ""
echo "ClickHouse datasource: registered automatically (clickhousedb+connect://clickhouse:8123/openinsight)"
