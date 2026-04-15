FROM apache/airflow:2.8.4-python3.11

# Install Authlib for Keycloak OIDC OAuth support.
# Must run as the airflow user (apache/airflow image forbids pip-as-root).
RUN pip install --no-cache-dir authlib==1.3.0
