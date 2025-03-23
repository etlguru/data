#!/bin/bash

# Create project directory
PROJECT_DIR="cdc-pipeline-project"
mkdir -p "$PROJECT_DIR/terraform" "$PROJECT_DIR/dags" "$PROJECT_DIR/diagrams"

# 1. Generate Terraform file
cat << 'EOF' > "$PROJECT_DIR/terraform/main.tf"
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "subnet2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
}

resource "aws_s3_bucket" "raw" {
  bucket = "cdc-raw-bucket-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "staging" {
  bucket = "cdc-staging-bucket-${random_id.suffix.hex}"
}

resource "random_id" "suffix" {
  byte_length = 8
}

resource "aws_db_instance" "source" {
  identifier           = "cdc-source-db"
  engine               = "postgres"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  username             = "admin"
  password             = "password123"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name  = aws_db_subnet_group.main.name
  skip_final_snapshot   = true
}

resource "aws_db_subnet_group" "main" {
  name       = "cdc-db-subnet-group"
  subnet_ids = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_dms_replication_instance" "cdc" {
  replication_instance_id     = "cdc-replication-instance"
  replication_instance_class  = "dms.t3.medium"
  allocated_storage           = 50
  vpc_security_group_ids      = [aws_security_group.dms_sg.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id
}

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id = "cdc-dms-subnet-group"
  subnet_ids                  = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}

resource "aws_security_group" "dms_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_dms_endpoint" "source" {
  endpoint_id   = "cdc-source-endpoint"
  endpoint_type = "source"
  engine_name   = "postgres"
  username      = "admin"
  password      = "password123"
  server_name   = aws_db_instance.source.address
  port          = 5432
}

resource "aws_dms_endpoint" "target" {
  endpoint_id   = "cdc-target-endpoint"
  endpoint_type = "target"
  engine_name   = "s3"
  s3_settings {
    bucket_name = aws_s3_bucket.raw.bucket
    service_access_role_arn = aws_iam_role.dms_s3_role.arn
  }
}

resource "aws_dms_replication_task" "full_load" {
  replication_task_id      = "cdc-full-load-task"
  migration_type           = "full-load"
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn
  replication_instance_arn = aws_dms_replication_instance.cdc.replication_instance_arn
  table_mappings           = jsonencode({
    "rules": [{
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "1",
      "object-locator": {
        "schema-name": "%",
        "table-name": "%"
      },
      "rule-action": "include"
    }]
  })
}

resource "aws_iam_role" "dms_s3_role" {
  name = "dms-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "dms.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "dms_s3_policy" {
  role = aws_iam_role.dms_s3_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.raw.arn,
        "${aws_s3_bucket.raw.arn}/*"
      ]
    }]
  })
}

resource "aws_redshift_cluster" "cdc" {
  cluster_identifier  = "cdc-redshift-cluster"
  node_type           = "dc2.large"
  number_of_nodes     = 1
  master_username     = "admin"
  master_password     = "Password123"
  skip_final_snapshot = true
  vpc_security_group_ids = [aws_security_group.redshift_sg.id]
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
}

resource "aws_redshift_subnet_group" "main" {
  name       = "cdc-redshift-subnet-group"
  subnet_ids = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}

resource "aws_security_group" "redshift_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_glue_job" "staging_job" {
  name     = "cdc-staging-job"
  role_arn = aws_iam_role.glue_role.arn
  command {
    script_location = "s3://${aws_s3_bucket.staging.bucket}/scripts/staging_script.py"
    name            = "glueetl"
    python_version  = "3"
  }
  default_arguments = {
    "--job-language" = "python"
  }
  max_retries = 0
  timeout     = 60
}

resource "aws_iam_role" "glue_role" {
  name = "cdc-glue-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "glue_policy" {
  role = aws_iam_role.glue_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:*", "glue:*", "redshift:*"]
      Resource = ["*"]
    }]
  })
}
EOF

# 2. Generate Airflow DAGs
cat << 'EOF' > "$PROJECT_DIR/dags/cdc_full_load_destroy.py"
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
EOF

cat << 'EOF' > "$PROJECT_DIR/dags/cdc_glue_staging.py"
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
EOF

cat << 'EOF' > "$PROJECT_DIR/dags/cdc_redshift_view.py"
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
EOF

# 3. Generate XML Diagram
cat << 'EOF' > "$PROJECT_DIR/diagrams/architecture.xml"
<?xml version="1.0" encoding="UTF-8"?>
<mxGraphModel>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <mxCell id="2" value="RDS (Source)" style="rounded=1;fillColor=#FFCC99;strokeColor=#000000" vertex="1" parent="1">
      <mxGeometry x="50" y="50" width="100" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="3" value="AWS DMS" style="rounded=1;fillColor=#99CCFF;strokeColor=#000000" vertex="1" parent="1">
      <mxGeometry x="200" y="50" width="100" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="4" value="S3 (Raw)" style="rounded=1;fillColor=#CCFFCC;strokeColor=#000000" vertex="1" parent="1">
      <mxGeometry x="350" y="50" width="100" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="5" value="AWS Glue" style="rounded=1;fillColor=#FFFF99;strokeColor=#000000" vertex="1" parent="1">
      <mxGeometry x="500" y="50" width="100" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="6" value="S3 (Staging)" style="rounded=1;fillColor=#CCFFCC;strokeColor=#000000" vertex="1" parent="1">
      <mxGeometry x="650" y="50" width="100" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="7" value="Redshift" style="rounded=1;fillColor=#FF9999;strokeColor=#000000" vertex="1" parent="1">
      <mxGeometry x="800" y="50" width="100" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="8" value="Dashboard" style="rounded=1;fillColor=#CCCCFF;strokeColor=#000000" vertex="1" parent="1">
      <mxGeometry x="950" y="50" width="100" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="9" edge="1" source="2" target="3" style="edgeStyle=orthogonalEdgeStyle">
      <mxGeometry relative="1" as="geometry"/>
    </mxCell>
    <mxCell id="10" edge="1" source="3" target="4" style="edgeStyle=orthogonalEdgeStyle">
      <mxGeometry relative="1" as="geometry"/>
    </mxCell>
    <mxCell id="11" edge="1" source="4" target="5" style="edgeStyle=orthogonalEdgeStyle">
      <mxGeometry relative="1" as="geometry"/>
    </mxCell>
    <mxCell id="12" edge="1" source="5" target="6" style="edgeStyle=orthogonalEdgeStyle">
      <mxGeometry relative="1" as="geometry"/>
    </mxCell>
    <mxCell id="13" edge="1" source="6" target="7" style="edgeStyle=orthogonalEdgeStyle">
      <mxGeometry relative="1" as="geometry"/>
    </mxCell>
    <mxCell id="14" edge="1" source="7" target="8" style="edgeStyle=orthogonalEdgeStyle">
      <mxGeometry relative="1" as="geometry"/>
    </mxCell>
  </root>
</mxGraphModel>
EOF

# 4. Generate Makefile
cat << 'EOF' > "$PROJECT_DIR/Makefile"
.PHONY: all init apply destroy dags clean

all: init apply dags

init:
	cd terraform && terraform init

apply:
	cd terraform && terraform apply -auto-approve

destroy:
	cd terraform && terraform destroy -auto-approve

dags:
	@echo "Copying DAGs to Airflow DAGs directory (update path as needed)"
	# cp dags/*.py /path/to/airflow/dags/

clean:
	rm -rf terraform/.terraform terraform/terraform.tfstate* terraform/.terraform.lock.hcl
EOF

# Make the script executable
chmod +x "$PROJECT_DIR/generate_project.sh"

echo "Project files generated in $PROJECT_DIR/"
