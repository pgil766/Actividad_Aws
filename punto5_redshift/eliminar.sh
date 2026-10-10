#!/usr/bin/env bash
# Punto 5 - Elimina el workgroup, el namespace (sin snapshot final) y el bucket S3, y verifica.
# El rol IAM p5-redshift-s3-role y la política Punto5Redshift los elimina un administrador.
# Uso: bash eliminar.sh
set -uo pipefail

export AWS_REGION=us-east-2
NAMESPACE=p5-namespace
WORKGROUP=p5-workgroup
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="actividad-aws-p5-${CUENTA}"

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"
SECRETO=$(aws redshift-serverless get-namespace --namespace-name "$NAMESPACE" \
  --query namespace.adminPasswordSecretArn --output text 2>/dev/null)

# 1. Workgroup (cómputo). El namespace no se puede borrar mientras tenga un workgroup.
aws redshift-serverless delete-workgroup --workgroup-name "$WORKGROUP" > /dev/null \
  && echo "Workgroup $WORKGROUP: eliminando..."
while aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP" > /dev/null 2>&1; do
  sleep 15
done
echo "Workgroup eliminado"

# 2. Namespace (datos). Sin snapshot final: un snapshot seguiría cobrando almacenamiento.
aws redshift-serverless delete-namespace --namespace-name "$NAMESPACE" > /dev/null \
  && echo "Namespace $NAMESPACE: eliminando..."
while aws redshift-serverless get-namespace --namespace-name "$NAMESPACE" > /dev/null 2>&1; do
  sleep 15
done
echo "Namespace eliminado"

# 3. Bucket con los CSV (--force lo vacía antes de borrarlo)
aws s3 rb "s3://${BUCKET}" --force > /dev/null && echo "S3: bucket $BUCKET eliminado"

echo
echo "######## Verificación"
echo "== Workgroup";  aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP" 2>&1 | tail -1
echo "== Namespace";  aws redshift-serverless get-namespace --namespace-name "$NAMESPACE" 2>&1 | tail -1
echo "== Snapshots de Redshift Serverless"
aws redshift-serverless list-snapshots --namespace-name "$NAMESPACE" --query "length(snapshots)" 2>&1 | tail -1
echo "== Bucket $BUCKET"; aws s3api head-bucket --bucket "$BUCKET" 2>&1 | tail -1
if [ -n "$SECRETO" ] && [ "$SECRETO" != "None" ]; then
  echo "== Secreto del admin $SECRETO"
  aws secretsmanager describe-secret --secret-id "$SECRETO" --query "[Name,DeletedDate]" --output text 2>&1 | tail -1
fi
echo "== Secreto huérfano del primer intento fallido (redshift!p5-namespace-awsadmin)"
aws secretsmanager describe-secret --secret-id 'redshift!p5-namespace-awsadmin' --query "[Name,DeletedDate]" --output text 2>&1 | tail -1
