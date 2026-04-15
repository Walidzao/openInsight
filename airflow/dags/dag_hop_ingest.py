"""
OpenInsight — Hop Ingest DAG

Triggers the sample Apache Hop pipeline (PostgreSQL customers → Redpanda).
Placeholder scaffold; schedule remains manual until we build end-to-end
alerting around Hop exit codes.
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

HOP_CONTAINER = "openinsight-hop-web"
HOP_RUN = "/usr/local/tomcat/webapps/ROOT/hop-run.sh"
HOP_PROJECT = "openinsight"
HOP_ENVIRONMENT = "local-dev"
HOP_PIPELINE = "/project/pipelines/sample-ingest-to-kafka.hpl"

with DAG(
    dag_id="dag_hop_ingest",
    description="Run sample Hop pipeline (PG customers → Redpanda)",
    default_args=default_args,
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["hop", "ingest", "phase2"],
) as dag:

    run_sample_pipeline = BashOperator(
        task_id="run_sample_ingest_to_kafka",
        bash_command=(
            f"docker exec {HOP_CONTAINER} {HOP_RUN} "
            f"--project={HOP_PROJECT} "
            f"--environment={HOP_ENVIRONMENT} "
            f"--file={HOP_PIPELINE} "
            f"--level=Basic"
        ),
    )
