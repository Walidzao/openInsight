"""
OpenInsight — dbt Transform DAG

Runs `dbt run` followed by `dbt test` against ClickHouse. Placeholder scaffold;
wired to manual trigger until dbt is containerised or scheduled directly.
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
        bash_command=(
            f"echo 'Placeholder: dbt run would execute against {DBT_PROJECT_DIR}'; "
            "echo 'Follow-up: mount dbt project + install dbt-clickhouse in container'"
        ),
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"echo 'Placeholder: dbt test would execute against {DBT_PROJECT_DIR}'"
        ),
    )

    dbt_run >> dbt_test
