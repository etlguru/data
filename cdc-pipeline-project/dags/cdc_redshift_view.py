from airflow import DAG
from airflow.providers.amazon.aws.operators.redshift import RedshiftSQLOperator
from datetime import datetime

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2025, 3, 23),
}

with DAG('cdc_redshift_view', default_args=default_args, schedule_interval='@daily') as dag:
    create_view = RedshiftSQLOperator(
        task_id='create_redshift_view',
        redshift_conn_id='redshift_default',
        sql="""
        CREATE OR REPLACE VIEW dashboard_view AS
        SELECT * FROM staging_table
        WHERE date >= CURRENT_DATE - INTERVAL '7 days';
        """
    )

    create_view
