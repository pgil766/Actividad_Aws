#!/usr/bin/env bash
# Comprueba con AWS CLI que no quedan recursos del punto 2 de un método.
# Uso: bash verificar_eliminacion.sh <terraform|boto3|cli> [arn_del_secreto_de_rds]
set -uo pipefail

export AWS_REGION=us-east-2
METODO="${1:?Uso: bash verificar_eliminacion.sh <terraform|boto3|cli>}"
PREFIJO="p2-${METODO}"
CUENTA=$(aws sts get-caller-identity --query Account --output text)

echo "== Identidad: $(aws sts get-caller-identity --query Arn --output text)"

echo "== RDS ${PREFIJO}-db"
aws rds describe-db-instances --db-instance-identifier "${PREFIJO}-db" 2>&1 | tail -1

echo "== RDS subnet group ${PREFIJO}-db-subnets"
aws rds describe-db-subnet-groups --db-subnet-group-name "${PREFIJO}-db-subnets" 2>&1 | tail -1

echo "== EC2 ${PREFIJO}-ec2 (debe estar terminated o no aparecer)"
aws ec2 describe-instances --filters "Name=tag:Name,Values=${PREFIJO}-ec2" \
  --query "Reservations[].Instances[].[InstanceId,State.Name]" --output text

echo "== Security groups ${PREFIJO}-*"
aws ec2 describe-security-groups --filters "Name=group-name,Values=${PREFIJO}-ec2-sg,${PREFIJO}-rds-sg" \
  --query "length(SecurityGroups)"

echo "== S3 actividad-aws-p2-${CUENTA}-${METODO}"
aws s3api head-bucket --bucket "actividad-aws-p2-${CUENTA}-${METODO}" 2>&1 | tail -1

if [ -n "${2:-}" ]; then
  echo "== Secreto de RDS $2"
  aws secretsmanager describe-secret --secret-id "$2" 2>&1 | tail -1
fi
