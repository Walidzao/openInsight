-- ClickHouse read-only service accounts for Superset target switching

CREATE USER IF NOT EXISTS superset_openinsight_ro
IDENTIFIED BY '__OPENINSIGHT_RO_PASSWORD__';

ALTER USER superset_openinsight_ro
IDENTIFIED BY '__OPENINSIGHT_RO_PASSWORD__';

CREATE USER IF NOT EXISTS superset_engineering_ro
IDENTIFIED BY '__ENGINEERING_RO_PASSWORD__';

ALTER USER superset_engineering_ro
IDENTIFIED BY '__ENGINEERING_RO_PASSWORD__';

GRANT SELECT ON openinsight.* TO superset_openinsight_ro;
GRANT SELECT ON engineering_data.* TO superset_engineering_ro;
