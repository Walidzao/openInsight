"""
OpenInsight — dbt Transform DAG

Runs `dbt run` followed by `dbt test` against ClickHouse.
The dbt project is mounted read-only at /opt/airflow/dbt.
Logs and compiled output are redirected to /tmp (writable) to avoid
writing into the read-only mount.
Connection env vars (CH_HOST, CH_USER, etc.) are injected via docker-compose.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

default_args = {
    "owner": "openinsight",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

DBT_PROJECT_DIR = "/opt/airflow/dbt"
# Redirect writable dbt output dirs out of the read-only mount
DBT_FLAGS = (
    f"--profiles-dir {DBT_PROJECT_DIR} "
    f"--project-dir {DBT_PROJECT_DIR} "
    "--log-path /tmp/dbt_logs "
    "--target-path /tmp/dbt_target "
    "--no-partial-parse"
)

with DAG(
    dag_id="dag_dbt_transform",
    description="Run dbt models + tests against ClickHouse",
    default_args=default_args,
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["dbt", "transform", "phase2"],
) as dag:

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=f"dbt run {DBT_FLAGS}",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"dbt test {DBT_FLAGS}",
    )

    dbt_run >> dbt_test
