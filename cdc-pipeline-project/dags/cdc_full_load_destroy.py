from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2025, 3, 23),
}

with DAG('cdc_full_load_destroy', default_args=default_args, schedule_interval=None) as dag:
    init_terraform = BashOperator(
        task_id='terraform_init',
        bash_command='cd /path/to/terraform && terraform init'
    )

    apply_terraform = BashOperator(
        task_id='terraform_apply',
        bash_command='cd /path/to/terraform && terraform apply -auto-approve'
    )

    destroy_terraform = BashOperator(
        task_id='terraform_destroy',
        bash_command='cd /path/to/terraform && terraform destroy -auto-approve'
    )

    init_terraform >> apply_terraform >> destroy_terraform
