#!/bin/bash
set -e

echo "=== OpenInsight Superset Initialization ==="
echo ""

# Drivers (clickhouse-connect, Authlib) are baked into the image via Dockerfile

# Run database migrations
echo "[1/8] Running database migrations..."
docker compose exec -T superset superset db upgrade

# Create fallback admin user (DB auth — useful if Keycloak is down)
echo "[2/8] Creating fallback admin user..."
docker compose exec -T superset superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@openinsight.local \
    --password admin \
    || echo "  Admin user already exists."

# Initialize roles and permissions
echo "[3/8] Initializing roles and permissions..."
docker compose exec -T superset superset init

# Patch Alpha role: add SQL Lab + TabStateView permissions missing after superset init
echo "[4/8] Patching Alpha role with full SQL Lab permissions..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
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
echo "[5/8] Registering ClickHouse database connection..."
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

# Tighten Alpha database access: remove all_database_access, grant ClickHouse only.
# This must run AFTER superset init (step 3) which re-adds all_database_access to Alpha.
echo "[6/8] Tightening Alpha role database access (ClickHouse only)..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from superset.models.core import Database
    from flask_appbuilder.security.sqla.models import Role, PermissionView, Permission, ViewMenu

    alpha = sa_db.session.query(Role).filter_by(name='Alpha').first()
    if not alpha:
        print('  Alpha role not found — skipping.')
    else:
        # Remove all_database_access so Alpha cannot query arbitrary future databases
        all_db_pvs = (
            sa_db.session.query(PermissionView)
            .join(Permission, PermissionView.permission_id == Permission.id)
            .filter(Permission.name == 'all_database_access')
            .all()
        )
        removed = 0
        for pv in all_db_pvs:
            if pv in alpha.permissions:
                alpha.permissions.remove(pv)
                removed += 1

        # Grant access to ClickHouse specifically
        ch_db = sa_db.session.query(Database).filter_by(database_name='ClickHouse').first()
        added = 0
        if ch_db:
            view_menu_name = '[%s].(id:%d)' % (ch_db.database_name, ch_db.id)
            ch_pv = (
                sa_db.session.query(PermissionView)
                .join(ViewMenu)
                .filter(ViewMenu.name == view_menu_name)
                .first()
            )
            if ch_pv and ch_pv not in alpha.permissions:
                alpha.permissions.append(ch_pv)
                added += 1

        sa_db.session.commit()
        print('  Removed %d all_database_access perm(s), added %d ClickHouse-specific perm(s).' % (removed, added))
"

# Create group-based RLS roles and register fct_sales dataset.
# Finance/HR/Engineering/Executive roles are used by Superset RLS to scope rows.
echo "[7/8] Creating group RLS roles and fct_sales dataset..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from superset.models.core import Database
    from flask_appbuilder.security.sqla.models import Role

    # --- Create group RLS roles if they don't exist ---
    rls_roles_spec = [
        'Finance_RLS',
        'HR_RLS',
        'Engineering_RLS',
        'Executive_RLS',
    ]
    for role_name in rls_roles_spec:
        existing = sa_db.session.query(Role).filter_by(name=role_name).first()
        if not existing:
            sa_db.session.add(Role(name=role_name))
            print('  Created role: %s' % role_name)
        else:
            print('  Role already exists: %s' % role_name)
    sa_db.session.commit()

    # --- Register fct_sales as a Superset dataset (SqlaTable) ---
    ch_db = sa_db.session.query(Database).filter_by(database_name='ClickHouse').first()
    if not ch_db:
        print('  ClickHouse database not found — skipping dataset creation.')
    else:
        try:
            from superset.connectors.sqla.models import SqlaTable
            existing_ds = (
                sa_db.session.query(SqlaTable)
                .filter_by(table_name='fct_sales', database_id=ch_db.id)
                .first()
            )
            if existing_ds:
                print('  Dataset fct_sales already exists (id=%d).' % existing_ds.id)
            else:
                ds = SqlaTable(
                    table_name='fct_sales',
                    schema='openinsight',
                    database_id=ch_db.id,
                )
                sa_db.session.add(ds)
                sa_db.session.commit()
                print('  Created dataset fct_sales (id=%d).' % ds.id)
        except Exception as e:
            print('  Dataset creation error: %s' % e)
"

# Create Row Level Security rules for each department group.
# Finance_RLS → department_code = 'FIN'
# HR_RLS      → department_code = 'HR'
# Engineering_RLS → department_code = 'ENG'
# Executive_RLS   → no filter (sees everything — empty clause means bypass)
echo "[8/8] Creating Row Level Security rules for fct_sales..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from superset.models.core import Database
    from flask_appbuilder.security.sqla.models import Role

    ch_db = sa_db.session.query(Database).filter_by(database_name='ClickHouse').first()
    if not ch_db:
        print('  ClickHouse not found — skipping RLS setup.')
    else:
        try:
            from superset.connectors.sqla.models import SqlaTable, RowLevelSecurityFilter
        except ImportError:
            # Fallback import path (varies across Superset builds)
            from superset.models.security import RowLevelSecurityFilter
            from superset.connectors.sqla.models import SqlaTable

        fct_sales = (
            sa_db.session.query(SqlaTable)
            .filter_by(table_name='fct_sales', database_id=ch_db.id)
            .first()
        )
        if not fct_sales:
            print('  fct_sales dataset not found — run step 7 first.')
        else:
            # (role_name, clause)  — Executive_RLS: no filter so execs see all rows
            rules = [
                ('Finance_RLS',     \"department_code = 'FIN'\"),
                ('HR_RLS',          \"department_code = 'HR'\"),
                ('Engineering_RLS', \"department_code = 'ENG'\"),
            ]
            for role_name, clause in rules:
                role = sa_db.session.query(Role).filter_by(name=role_name).first()
                if not role:
                    print('  Role %s not found — skipping.' % role_name)
                    continue
                existing = (
                    sa_db.session.query(RowLevelSecurityFilter)
                    .filter_by(name=('%s filter' % role_name))
                    .first()
                )
                if existing:
                    print('  RLS rule already exists: %s' % role_name)
                    continue
                rls = RowLevelSecurityFilter(
                    name='%s filter' % role_name,
                    filter_type='Regular',
                    clause=clause,
                )
                rls.tables.append(fct_sales)
                rls.roles.append(role)
                sa_db.session.add(rls)
                print('  Created RLS rule: %s → %s' % (role_name, clause))
            sa_db.session.commit()
            print('  RLS rules committed.')
"

echo ""
echo "=== Superset initialization complete (8 steps) ==="
echo ""
echo "Auth: Keycloak OIDC (realm: openinsight, client: superset)"
echo "Login: http://localhost:${SUPERSET_PORT:-8088}/login/keycloak"
echo "Fallback: http://localhost:${SUPERSET_PORT:-8088}/login/ (admin / admin)"
echo ""
echo "Test users (Keycloak SSO):"
echo "  alice.finance    / Test123!DevOps  → Alpha + Finance_RLS (sees FIN dept rows)"
echo "  bob.hr           / Test123!DevOps  → Alpha + HR_RLS (sees HR dept rows)"
echo "  carol.engineering/ Test123!DevOps  → Alpha + Engineering_RLS (sees ENG dept rows)"
echo "  eve.viewer       / Test123!DevOps  → Gamma + Finance_RLS (view-only, FIN rows)"
echo "  dave.executive   / Test123!DevOps  → Admin (bypasses RLS, sees all)"
echo ""
echo "RLS: ROW_LEVEL_SECURITY feature flag enabled"
echo "  fct_sales: Finance_RLS→FIN, HR_RLS→HR, Engineering_RLS→ENG"
echo ""
echo "DB access: Alpha role restricted to ClickHouse (all_database_access removed)"
echo "ClickHouse datasource: registered automatically (clickhousedb+connect://clickhouse:8123/openinsight)"
