#!/usr/bin/env bash
# Punto 5 - Crea el bucket S3 y Redshift Serverless (namespace + workgroup de 4 RPU).
# La contraseña del admin la genera Redshift y la guarda en Secrets Manager (--manage-admin-password).
# Requisito previo: rol IAM p5-redshift-s3-role (lectura del bucket) creado por un administrador.
# Uso: bash crear.sh
set -euo pipefail

export AWS_REGION=us-east-2
NAMESPACE=p5-namespace
WORKGROUP=p5-workgroup

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="actividad-aws-p5-${CUENTA}"
ROL_ARN="arn:aws:iam::${CUENTA}:role/p5-redshift-s3-role"

if aws s3api head-bucket --bucket "$BUCKET" > /dev/null 2>&1; then
  echo "S3: bucket $BUCKET ya existe"
else
  aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null
  echo "S3: bucket $BUCKET creado"
fi

aws redshift-serverless create-namespace \
  --namespace-name "$NAMESPACE" \
  --db-name actividad \
  --admin-username rsadmin \
  --manage-admin-password \
  --iam-roles "$ROL_ARN" \
  --default-iam-role-arn "$ROL_ARN" \
  --tags key=Proyecto,value=actividad-aws key=Punto,value=5 > /dev/null
echo "Namespace $NAMESPACE creado (contraseña de admin administrada en Secrets Manager)"

VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query "Subnets[].SubnetId" --output text)
# shellcheck disable=SC2086
aws redshift-serverless create-workgroup \
  --workgroup-name "$WORKGROUP" \
  --namespace-name "$NAMESPACE" \
  --base-capacity 4 \
  --no-publicly-accessible \
  --subnet-ids $SUBNETS \
  --tags key=Proyecto,value=actividad-aws key=Punto,value=5 > /dev/null
echo "Workgroup $WORKGROUP (4 RPU, no público) creándose..."

until [ "$(aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP" --query workgroup.status --output text)" = "AVAILABLE" ]; do
  sleep 20
done
echo "Workgroup disponible"
echo

aws redshift-serverless get-namespace --namespace-name "$NAMESPACE" \
  --query "namespace.{Namespace:namespaceName,Estado:status,BaseDeDatos:dbName,Admin:adminUsername,SecretoAdmin:adminPasswordSecretArn,RolPorDefecto:defaultIamRoleArn}" \
  --output table
aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP" \
  --query "workgroup.{Workgroup:workgroupName,Estado:status,CapacidadBaseRPU:baseCapacity,Publico:publiclyAccessible,Endpoint:endpoint.address}" \
  --output table
