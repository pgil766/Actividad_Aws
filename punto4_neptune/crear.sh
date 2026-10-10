#!/usr/bin/env bash
# Punto 4 - Crea el clúster Neptune con endpoint público y autenticación IAM.
# Requisito previo: security group p4-neptune-sg (entrada 8182 desde la IP del PC).
# Uso: bash crear.sh
set -euo pipefail

export AWS_REGION=us-east-2
CLUSTER_ID=p4-neptune
INSTANCIA=p4-neptune-instancia
VERSION=1.4.8.1   # el endpoint público requiere 1.4.6 o superior

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"

VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)
# Subredes por defecto: públicas (ruta 0.0.0.0/0 -> Internet Gateway), requisito del endpoint público
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query "Subnets[].SubnetId" --output text)
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=p4-neptune-sg \
  --query "SecurityGroups[0].GroupId" --output text)
echo "VPC: $VPC_ID · SG: $SG_ID"

# shellcheck disable=SC2086
aws neptune create-db-subnet-group --db-subnet-group-name p4-neptune-subnets \
  --db-subnet-group-description "Subredes publicas de la VPC por defecto" \
  --subnet-ids $SUBNETS > /dev/null
echo "Subnet group p4-neptune-subnets creado"

aws neptune create-db-cluster \
  --db-cluster-identifier "$CLUSTER_ID" \
  --engine neptune \
  --engine-version "$VERSION" \
  --db-subnet-group-name p4-neptune-subnets \
  --vpc-security-group-ids "$SG_ID" \
  --enable-iam-database-authentication \
  --storage-encrypted \
  --backup-retention-period 1 \
  --no-deletion-protection > /dev/null
echo "Clúster $CLUSTER_ID creado (IAM obligatoria, cifrado)"

aws neptune create-db-instance \
  --db-instance-identifier "$INSTANCIA" \
  --db-cluster-identifier "$CLUSTER_ID" \
  --engine neptune \
  --db-instance-class db.t4g.medium \
  --publicly-accessible > /dev/null
echo "Instancia $INSTANCIA (db.t4g.medium, acceso público) creándose..."

until aws neptune wait db-instance-available --db-instance-identifier "$INSTANCIA"; do
  echo "Neptune: sigue creándose..."
done
echo "Neptune: disponible"
echo

aws neptune describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" \
  --query "DBClusters[0].{Estado:Status,Version:EngineVersion,Endpoint:Endpoint,Puerto:Port,AutenticacionIAM:IAMDatabaseAuthenticationEnabled,Cifrado:StorageEncrypted,SG:VpcSecurityGroups[0].VpcSecurityGroupId}" \
  --output table
aws neptune describe-db-instances --db-instance-identifier "$INSTANCIA" \
  --query "DBInstances[0].{Instancia:DBInstanceIdentifier,Clase:DBInstanceClass,Estado:DBInstanceStatus,AccesoPublico:PubliclyAccessible,Zona:AvailabilityZone}" \
  --output table
