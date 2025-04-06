# Data Location

Local path: `/Users/kartik/myownetl/data`

# CDC Pipeline Project on AWS

This project provisions a Change Data Capture (CDC) pipeline using AWS services, managed with Terraform and orchestrated using Apache Airflow. It extracts changes from a PostgreSQL database and transfers the data through transformation and loading phases, making it ready for analytics in Amazon Redshift.

## Project Overview

The pipeline includes the following steps:

1. A PostgreSQL RDS instance acts as the source system.
2. AWS DMS captures database changes and performs a full load into an S3 bucket (raw zone).
3. AWS Glue transforms the data and writes it to another S3 bucket (staging zone).
4. Amazon Redshift serves as the data warehouse for analytics.
5. A Redshift view is created to expose recent data for dashboards.
6. An architecture diagram (XML format) is provided for visualization.

## Tools and Technologies

- Terraform – Infrastructure as Code
- AWS RDS (PostgreSQL) – Source database
- AWS DMS – Data migration and CDC
- AWS S3 – Storage for raw and staged data
- AWS Glue – ETL processing
- Amazon Redshift – Data warehousing
- Apache Airflow – Workflow orchestration
- Makefile – Command-line automation

## Basic Usage

```bash
cd cdc-pipeline-project

make init      # Initialize Terraform
make apply     # Provision resources
make destroy   # Tear down resources
