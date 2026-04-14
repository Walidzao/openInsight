FROM apache/superset:3.1.0

# Install drivers:
#   clickhouse-connect: ClickHouse HTTP connector (port 8123)
#   Authlib: OAuth2/OIDC client for Keycloak SSO
USER root
RUN pip install --no-cache-dir clickhouse-connect==0.7.0 Authlib==1.3.0

USER superset
