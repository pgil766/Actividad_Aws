#!/usr/bin/env bash
# Punto 6 - Elimina el crawler, las tablas, la base de datos de Glue y el bucket (datos + resultados de Athena).
# El rol p6-glue-crawler-role y la política Punto6GlueAthena los elimina un administrador (no cobran).
# Uso: bash eliminar.sh
set -uo pipefail

export AWS_REGION=us-east-2
DATABASE=p6_ventas
CRAWLER=p6-crawler-ventas
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="actividad-aws-p6-${CUENTA}"

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"

aws glue delete-crawler --name "$CRAWLER" && echo "Glue: crawler $CRAWLER eliminado"

for TABLA in $(aws glue get-tables --database-name "$DATABASE" --query "TableList[].Name" --output text); do
  aws glue delete-table --database-name "$DATABASE" --name "$TABLA" && echo "Glue: tabla $DATABASE.$TABLA eliminada"
done
aws glue delete-database --name "$DATABASE" && echo "Glue: base de datos $DATABASE eliminada"

# Borra los CSV y los resultados de Athena (athena-resultados/), luego el bucket
aws s3 rb "s3://${BUCKET}" --force > /dev/null && echo "S3: bucket $BUCKET eliminado"

echo
echo "######## Verificación"
echo "== Crawler";        aws glue get-crawler --name "$CRAWLER" 2>&1 | tail -1
echo "== Base de datos";  aws glue get-database --name "$DATABASE" 2>&1 | tail -1
echo "== Bucket";         aws s3api head-bucket --bucket "$BUCKET" 2>&1 | tail -1
