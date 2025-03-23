provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
}

resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet1_cidr_block
  availability_zone = var.subnet1_az
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet2_cidr_block
  availability_zone = var.subnet2_az
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
  identifier           = var.rds_identifier
  engine               = var.rds_engine
  instance_class       = var.rds_instance_class
  allocated_storage    = var.rds_allocated_storage
  username             = var.rds_username
  password             = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name  = aws_db_subnet_group.main.name
  skip_final_snapshot   = true
  db_name              = var.rds_database_name
  publicly_accessible  = true  # Allows external access
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
    ipv6_cidr_blocks = ["2405:201:600d:7983:cd99:77be:e5ff:c21a/128"]  # Your IPv6 address
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DMS VPC Role (required for DMS Serverless to work with VPC)
resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role"
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

resource "aws_iam_role_policy_attachment" "dms_vpc_policy" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# DMS Serverless Replication Config (includes table mappings)
resource "aws_dms_replication_config" "cdc" {
  replication_config_identifier = var.dms_replication_config_identifier
  replication_type              = var.dms_replication_type
  source_endpoint_arn           = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn           = aws_dms_endpoint.target.endpoint_arn
  table_mappings                = jsonencode({
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
  compute_config {
    max_capacity_units = var.dms_max_capacity_units
    min_capacity_units = var.dms_min_capacity_units
    replication_subnet_group_id = aws_dms_replication_subnet_group.main.id
    vpc_security_group_ids      = [aws_security_group.dms_sg.id]
  }
  depends_on = [aws_iam_role_policy_attachment.dms_vpc_policy]
}

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "cdc-dms-subnet-group"
  replication_subnet_group_description = "DMS subnet group for CDC pipeline"
  subnet_ids                           = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
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
  endpoint_id   = var.dms_source_endpoint_id
  endpoint_type = "source"
  engine_name   = var.rds_engine
  username      = var.rds_username
  password      = var.rds_password
  server_name   = aws_db_instance.source.address
  port          = 5432
  database_name = var.rds_database_name
}

resource "aws_dms_endpoint" "target" {
  endpoint_id   = var.dms_target_endpoint_id
  endpoint_type = "target"
  engine_name   = "s3"
  s3_settings {
    bucket_name = aws_s3_bucket.raw.bucket
    service_access_role_arn = aws_iam_role.dms_s3_role.arn
  }
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
  cluster_identifier        = var.redshift_cluster_identifier
  node_type                 = var.redshift_node_type
  number_of_nodes           = var.redshift_number_of_nodes
  master_username           = var.redshift_username
  master_password           = var.redshift_password
  skip_final_snapshot       = true
  vpc_security_group_ids    = [aws_security_group.redshift_sg.id]
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  publicly_accessible       = false
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
  name     = var.glue_job_name
  role_arn = aws_iam_role.glue_role.arn
  command {
    script_location = "s3://${aws_s3_bucket.staging.bucket}/scripts/staging_script.py"
    name            = "glueetl"
    python_version  = "3"
  }
  default_arguments = {
    "--job-language" = "python"
  }
  max_retries    = 0
  timeout        = var.glue_timeout
  worker_type    = "Standard"
  number_of_workers = 2
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

# Define variables
variable "aws_region" {}
variable "vpc_cidr_block" {}
variable "subnet1_cidr_block" {}
variable "subnet1_az" {}
variable "subnet2_cidr_block" {}
variable "subnet2_az" {}
variable "rds_identifier" {}
variable "rds_engine" {}
variable "rds_instance_class" {}
variable "rds_allocated_storage" {}
variable "rds_username" {}
variable "rds_password" {}
variable "rds_database_name" {}
variable "dms_source_endpoint_id" {}
variable "dms_target_endpoint_id" {}
variable "dms_replication_config_identifier" {}
variable "dms_replication_type" {}
variable "dms_max_capacity_units" {}
variable "dms_min_capacity_units" {}
variable "redshift_cluster_identifier" {}
variable "redshift_node_type" {}
variable "redshift_number_of_nodes" {}
variable "redshift_username" {}
variable "redshift_password" {}
variable "glue_job_name" {}
variable "glue_timeout" {}