#!/usr/bin/env bash
# Verifica con AWS CLI los recursos del punto 2 de un método (terraform, boto3 o cli).
# Uso: bash verificar.sh <metodo>
set -uo pipefail

METODO="${1:?Uso: bash verificar.sh <terraform|boto3|cli>}"
PREFIJO="p2-${METODO}"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="actividad-aws-p2-${CUENTA}-${METODO}"

echo "== Identidad"
aws sts get-caller-identity --query Arn --output text

echo; echo "== S3"
aws s3api head-bucket --bucket "$BUCKET" >/dev/null && echo "Bucket $BUCKET existe"

echo; echo "== EC2"
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PREFIJO}-ec2" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].{Id:InstanceId,Tipo:InstanceType,Estado:State.Name,IpPrivada:PrivateIpAddress,IpPublica:PublicIpAddress}" \
  --output table

echo; echo "== Security groups"
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PREFIJO}-ec2-sg,${PREFIJO}-rds-sg" \
  --query "SecurityGroups[].{Nombre:GroupName,Id:GroupId,Entradas:length(IpPermissions)}" \
  --output table

echo; echo "== RDS"
aws rds describe-db-instances --db-instance-identifier "${PREFIJO}-db" \
  --query "DBInstances[0].{Estado:DBInstanceStatus,Motor:Engine,Version:EngineVersion,Clase:DBInstanceClass,Publica:PubliclyAccessible,Cifrada:StorageEncrypted,SubnetGroup:DBSubnetGroup.DBSubnetGroupName,Secreto:MasterUserSecret.SecretArn,EstadoSecreto:MasterUserSecret.SecretStatus}" \
  --output table

echo; echo "== Secreto administrado por RDS (solo metadatos, nunca el valor)"
SECRETO=$(aws rds describe-db-instances --db-instance-identifier "${PREFIJO}-db" \
  --query "DBInstances[0].MasterUserSecret.SecretArn" --output text)
aws secretsmanager describe-secret --secret-id "$SECRETO" \
  --query "{Nombre:Name,ServicioPropietario:OwningService,RotacionActiva:RotationEnabled,DiasRotacion:RotationRules.AutomaticallyAfterDays}" \
  --output table
