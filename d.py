import configparser
import requests
from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator  # Airflow 3: airflow.providers.standard.operators.python
from airflow.models import Variable


def report_tables(**_):
    cfg = configparser.ConfigParser()
    cfg.optionxform = str                      # preserve TABLE1 casing
    cfg.read("/path/to/tables.ini")            # or fetch via Azure DevOps REST API
    tables = list(cfg["tables"].keys())
    rows = "\n".join(f"- {t}" for t in tables)
    card = {
        "type": "message",
        "attachments": [{
            "contentType": "application/vnd.microsoft.card.adaptive",
            "content": {
                "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                "type": "AdaptiveCard", "version": "1.4",
                "body": [
                    {"type": "TextBlock", "size": "Large", "weight": "Bolder",
                     "text": f"Ingestion config — {len(tables)} tables"},
                    {"type": "TextBlock", "wrap": True, "text": rows},
                ],
            },
        }],
    }
    r = requests.post(Variable.get("TEAMS_WORKFLOW_URL"), json=card, timeout=30)
    r.raise_for_status()


with DAG(
    dag_id="teams_ingestion_table_report",
    schedule=None,                 # trigger manually, or chain after your ADF copy
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["reporting", "teams", "ingestion"],
) as dag:

    report = PythonOperator(
        task_id="report_tables",
        python_callable=report_tables,
    )
