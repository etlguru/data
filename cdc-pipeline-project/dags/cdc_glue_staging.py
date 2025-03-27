from airflow import DAG
from airflow.providers.amazon.aws.operators.glue import AwsGlueJobOperator
from datetime import datetime

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2025, 3, 23),
}

with DAG('cdc_glue_staging', default_args=default_args, schedule_interval='@daily') as dag:
    run_glue_job = AwsGlueJobOperator(
        task_id='run_glue_staging_job',
        job_name='cdc-staging-job',
        region_name='us-east-1'
    )

    run_glue_job
