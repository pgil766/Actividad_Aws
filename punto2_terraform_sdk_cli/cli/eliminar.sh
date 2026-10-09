#!/usr/bin/env bash
# Punto 2 - Elimina con AWS CLI los recursos creados por crear.sh.
# Uso: bash eliminar.sh
set -uo pipefail

export AWS_REGION=us-east-2
PREFIJO=p2-cli

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="actividad-aws-p2-${CUENTA}-cli"

# RDS (borra también el secreto administrado por RDS)
aws rds delete-db-instance --db-instance-identifier "${PREFIJO}-db" \
  --skip-final-snapshot --delete-automated-backups > /dev/null \
  && echo "RDS: eliminando ${PREFIJO}-db..."

# EC2
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PREFIJO}-ec2" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$INSTANCE_IDS" ]; then
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS > /dev/null
  echo "EC2: terminando $INSTANCE_IDS..."
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
  echo "EC2: terminated"
fi

# El waiter de la CLI se rinde a los 30 min; se reintenta por si RDS tarda más.
until aws rds wait db-instance-deleted --db-instance-identifier "${PREFIJO}-db"; do
  echo "RDS: sigue eliminándose..."
done
echo "RDS: eliminada"

aws rds delete-db-subnet-group --db-subnet-group-name "${PREFIJO}-db-subnets" \
  && echo "RDS: subnet group eliminado"

# Primero el SG de RDS, porque referencia al de la EC2
for NOMBRE in "${PREFIJO}-rds-sg" "${PREFIJO}-ec2-sg"; do
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${NOMBRE}" \
    --query "SecurityGroups[0].GroupId" --output text)
  if [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group --group-id "$SG_ID" > /dev/null && echo "Security group $NOMBRE eliminado"
  fi
done

# S3: --force vacía el bucket antes de borrarlo
aws s3 rb "s3://${BUCKET}" --force > /dev/null && echo "S3: bucket $BUCKET eliminado"
