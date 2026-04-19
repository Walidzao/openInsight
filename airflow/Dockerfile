FROM apache/airflow:2.8.4-python3.11

# Install Authlib for Keycloak OIDC OAuth support.
# Install dbt-clickhouse for the dbt transform DAG.
# Must run as the airflow user (apache/airflow image forbids pip-as-root).
RUN pip install --no-cache-dir authlib==1.3.0 "dbt-clickhouse>=1.8,<2"
