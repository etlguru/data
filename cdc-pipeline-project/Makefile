.PHONY: all init plan plan-rds apply apply-rds setup-and-connect destroy dags clean

all: setup-and-connect

init:
	cd terraform && terraform init

plan:
	cd terraform && terraform plan -var-file=../vars.json

plan-rds:
	cd terraform && terraform plan -var-file=../vars.json -target=aws_db_instance.source

apply:
	cd terraform && terraform apply -auto-approve -var-file=../vars.json

apply-rds:
	cd terraform && terraform apply -auto-approve -var-file=../vars.json -target=aws_db_instance.source

setup-and-connect:
	./setup_and_connect.sh

destroy:
	cd terraform && terraform destroy -auto-approve -var-file=../vars.json

dags:
	@echo "Copying DAGs to Airflow DAGs directory (update path as needed)"
	# cp dags/*.py /path/to/airflow/dags/  # Uncomment and update path as needed

clean:
	rm -rf terraform/.terraform terraform/terraform.tfstate* terraform/.terraform.lock.hcl