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

# Register target-scoped ClickHouse database connections (idempotent)
echo "[5/8] Registering target-scoped ClickHouse database connections..."
docker compose exec -T superset python -c "
import os
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from superset.models.core import Database
    openinsight_uri = (
        'clickhousedb+connect://superset_openinsight_ro:%s@clickhouse:8123/openinsight'
        % os.environ.get('CLICKHOUSE_SUPERSET_OPENINSIGHT_PASSWORD', 'superset_openinsight_dev')
    )
    engineering_uri = (
        'clickhousedb+connect://superset_engineering_ro:%s@clickhouse:8123/engineering_data'
        % os.environ.get('CLICKHOUSE_SUPERSET_ENGINEERING_PASSWORD', 'superset_engineering_dev')
    )

    openinsight = sa_db.session.query(Database).filter_by(database_name='ClickHouse OpenInsight').first()
    legacy = sa_db.session.query(Database).filter_by(database_name='ClickHouse').first()
    if openinsight:
        openinsight.sqlalchemy_uri = openinsight_uri
        openinsight.expose_in_sqllab = True
        print('  ClickHouse OpenInsight connection already exists (id=%d).' % openinsight.id)
    elif legacy:
        legacy.database_name = 'ClickHouse OpenInsight'
        legacy.sqlalchemy_uri = openinsight_uri
        legacy.expose_in_sqllab = True
        openinsight = legacy
        print('  Renamed legacy ClickHouse connection to ClickHouse OpenInsight (id=%d).' % openinsight.id)
    else:
        openinsight = Database(
            database_name='ClickHouse OpenInsight',
            sqlalchemy_uri=openinsight_uri,
            expose_in_sqllab=True,
        )
        sa_db.session.add(openinsight)
        print('  Created ClickHouse OpenInsight connection.')

    engineering = sa_db.session.query(Database).filter_by(database_name='ClickHouse Engineering').first()
    if engineering:
        engineering.sqlalchemy_uri = engineering_uri
        engineering.expose_in_sqllab = True
        print('  ClickHouse Engineering connection already exists (id=%d).' % engineering.id)
    else:
        engineering = Database(
            database_name='ClickHouse Engineering',
            sqlalchemy_uri=engineering_uri,
            expose_in_sqllab=True,
        )
        sa_db.session.add(engineering)
        print('  Created ClickHouse Engineering connection.')

    sa_db.session.commit()
"

# Tighten Alpha database access, create DB roles, and clone AlphaPilot.
# This must run AFTER superset init (step 3) which re-adds all_database_access to Alpha.
echo "[6/8] Tightening Alpha role database access and creating pilot DB roles..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from superset.models.core import Database
    from flask_appbuilder.security.sqla.models import Role, PermissionView, Permission, ViewMenu

    alpha = sa_db.session.query(Role).filter_by(name='Alpha').first()
    alpha_pilot = sa_db.session.query(Role).filter_by(name='AlphaPilot').first()
    db_openinsight = sa_db.session.query(Role).filter_by(name='DB_OpenInsight').first()
    db_engineering = sa_db.session.query(Role).filter_by(name='DB_Engineering').first()
    if not alpha:
        print('  Alpha role not found — skipping.')
    else:
        if not alpha_pilot:
            alpha_pilot = Role(name='AlphaPilot')
            sa_db.session.add(alpha_pilot)
        if not db_openinsight:
            db_openinsight = Role(name='DB_OpenInsight')
            sa_db.session.add(db_openinsight)
        if not db_engineering:
            db_engineering = Role(name='DB_Engineering')
            sa_db.session.add(db_engineering)
        sa_db.session.commit()

        # Remove all_database_access so Alpha cannot query arbitrary future databases
        all_db_pvs = (
            sa_db.session.query(PermissionView)
            .join(Permission, PermissionView.permission_id == Permission.id)
            .filter(Permission.name == 'all_database_access')
            .all()
        )
        dbs = {
            db.database_name: db
            for db in sa_db.session.query(Database).filter(
                Database.database_name.in_(['ClickHouse OpenInsight', 'ClickHouse Engineering'])
            )
        }

        def db_perm(db_name):
            db = dbs.get(db_name)
            if not db:
                return None
            return (
                sa_db.session.query(PermissionView)
                .join(ViewMenu)
                .filter(ViewMenu.name == ('[%s].(id:%d)' % (db.database_name, db.id)))
                .first()
            )

        openinsight_pv = db_perm('ClickHouse OpenInsight')
        engineering_pv = db_perm('ClickHouse Engineering')
        db_specific_pvs = [pv for pv in [openinsight_pv, engineering_pv] if pv]
        removed = 0
        for pv in all_db_pvs:
            if pv in alpha.permissions:
                alpha.permissions.remove(pv)
                removed += 1
        for pv in db_specific_pvs:
            if pv in alpha.permissions and pv is not openinsight_pv:
                alpha.permissions.remove(pv)

        added = 0
        if openinsight_pv and openinsight_pv not in alpha.permissions:
            alpha.permissions.append(openinsight_pv)
            added += 1

        db_openinsight.permissions = []
        db_engineering.permissions = []
        if openinsight_pv:
            db_openinsight.permissions.append(openinsight_pv)
        if engineering_pv:
            db_engineering.permissions.append(engineering_pv)

        alpha_pilot.permissions = []
        for pv in alpha.permissions:
            if pv in all_db_pvs or pv in db_specific_pvs:
                continue
            alpha_pilot.permissions.append(pv)

        sa_db.session.commit()
        print('  Removed %d all_database_access perm(s), added %d ClickHouse OpenInsight DB perm(s).' % (removed, added))
        print('  DB roles ensured: DB_OpenInsight, DB_Engineering.')
        print('  AlphaPilot cloned from Alpha with DB access stripped.')
"

# Create group-based RLS roles and register target datasets.
# Finance/HR/Engineering roles are used by Superset RLS to scope rows.
echo "[7/8] Creating group RLS roles and target datasets..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from superset.models.core import Database
    from flask_appbuilder.security.sqla.models import (
        Role, PermissionView, Permission, ViewMenu
    )

    # --- Create group RLS roles if they don't exist ---
    rls_roles_spec = [
        'Finance_RLS',
        'HR_RLS',
        'Engineering_RLS',
    ]
    for role_name in rls_roles_spec:
        existing = sa_db.session.query(Role).filter_by(name=role_name).first()
        if not existing:
            sa_db.session.add(Role(name=role_name))
            print('  Created role: %s' % role_name)
        else:
            print('  Role already exists: %s' % role_name)
    sa_db.session.commit()

    db_specs = [
        ('ClickHouse OpenInsight', 'openinsight'),
        ('ClickHouse Engineering', 'engineering_data'),
    ]
    openinsight_ds = None
    try:
        from superset.connectors.sqla.models import SqlaTable
        for db_name, schema_name in db_specs:
            db = sa_db.session.query(Database).filter_by(database_name=db_name).first()
            if not db:
                print('  %s database not found — skipping dataset creation.' % db_name)
                continue
            existing_ds = (
                sa_db.session.query(SqlaTable)
                .filter_by(table_name='fct_sales', database_id=db.id)
                .first()
            )
            if existing_ds:
                ds = existing_ds
                ds.schema = schema_name
                print('  Dataset fct_sales already exists for %s (id=%d).' % (db_name, ds.id))
            else:
                ds = SqlaTable(
                    table_name='fct_sales',
                    schema=schema_name,
                    database_id=db.id,
                )
                sa_db.session.add(ds)
                sa_db.session.commit()
                print('  Created dataset fct_sales for %s (id=%d).' % (db_name, ds.id))
            try:
                ds.fetch_metadata()
                sa_db.session.commit()
                print('  Column metadata synced for %s (%d columns).' % (db_name, len(ds.columns)))
            except Exception as sync_err:
                print('  Column sync warning for %s (non-fatal): %s' % (db_name, sync_err))
            if db_name == 'ClickHouse OpenInsight':
                openinsight_ds = ds

        gamma = sa_db.session.query(Role).filter_by(name='Gamma').first()
        if gamma and openinsight_ds and openinsight_ds.perm:
            vm = sa_db.session.query(ViewMenu).filter_by(name=openinsight_ds.perm).first()
            if vm:
                ds_pv = (
                    sa_db.session.query(PermissionView)
                    .join(Permission)
                    .filter(Permission.name == 'datasource_access')
                    .filter(PermissionView.view_menu_id == vm.id)
                    .first()
                )
                if ds_pv and ds_pv not in gamma.permissions:
                    gamma.permissions.append(ds_pv)
                    sa_db.session.commit()
                    print('  Granted Gamma datasource_access on %s.' % openinsight_ds.perm)
                elif ds_pv:
                    print('  Gamma already has datasource_access on %s.' % openinsight_ds.perm)
                else:
                    print('  datasource_access perm not found for %s.' % openinsight_ds.perm)
            else:
                print('  ViewMenu not found for %s — Gamma grant skipped.' % openinsight_ds.perm)
        elif not gamma:
            print('  Gamma role not found — dataset access grant skipped.')
    except Exception as e:
        print('  Dataset creation error: %s' % e)
"

# Create Row Level Security rules for each department group.
# Finance_RLS     → department_code = 'FIN'
# HR_RLS          → department_code = 'HR'
# Engineering_RLS → department_code = 'ENG'
# Executives have no RLS role — they use superset-admin which bypasses RLS.
echo "[8/8] Creating Row Level Security rules for fct_sales..."
docker compose exec -T superset python -c "
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db as sa_db
    from superset.models.core import Database
    from flask_appbuilder.security.sqla.models import Role

    ch_db = sa_db.session.query(Database).filter_by(database_name='ClickHouse OpenInsight').first()
    if not ch_db:
        print('  ClickHouse not found — skipping RLS setup.')
    else:
        from superset.connectors.sqla.models import SqlaTable, RowLevelSecurityFilter

        fct_sales = (
            sa_db.session.query(SqlaTable)
            .filter_by(table_name='fct_sales', database_id=ch_db.id)
            .first()
        )
        if not fct_sales:
            print('  fct_sales dataset not found — run step 7 first.')
        else:
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
echo "  carol.engineering/ Test123!DevOps  → AlphaPilot + Engineering_RLS + target-scoped DB role"
echo "  eve.viewer       / Test123!DevOps  → Gamma + Finance_RLS (view-only, FIN rows)"
echo "  dave.executive   / Test123!DevOps  → Admin (bypasses RLS, sees all)"
echo ""
echo "RLS: ROW_LEVEL_SECURITY feature flag enabled"
echo "  fct_sales: Finance_RLS→FIN, HR_RLS→HR, Engineering_RLS→ENG"
echo ""
echo "DB access: Alpha role restricted to ClickHouse OpenInsight; AlphaPilot uses session-scoped DB roles"
echo "ClickHouse datasources: ClickHouse OpenInsight and ClickHouse Engineering registered automatically"
