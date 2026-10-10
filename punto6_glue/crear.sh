#!/usr/bin/env bash
# Punto 6 - Sube el CSV a S3, crea la base de datos de Glue y el crawler, y lo ejecuta.
# Requisito previo: rol p6-glue-crawler-role (AWSGlueServiceRole + lectura del bucket).
# Uso: bash crear.sh
set -euo pipefail

export AWS_REGION=us-east-2
DATABASE=p6_ventas
CRAWLER=p6-crawler-ventas
CARPETA="$(cd "$(dirname "$0")" && pwd)"

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="actividad-aws-p6-${CUENTA}"

# 1. Datos en S3: cada tabla es una carpeta; aquí solo va la primera parte (24 registros)
if ! aws s3api head-bucket --bucket "$BUCKET" > /dev/null 2>&1; then
  aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null
  echo "S3: bucket $BUCKET creado"
fi
aws s3 cp "$CARPETA/datos/ventas_parte1.csv" "s3://${BUCKET}/datos/ventas/ventas_parte1.csv" > /dev/null
echo "S3: s3://${BUCKET}/datos/ventas/ventas_parte1.csv"

# 2. Base de datos del Data Catalog (solo metadatos)
aws glue create-database --database-input "Name=${DATABASE},Description=Punto 6 - ventas en S3" > /dev/null
echo "Glue: base de datos $DATABASE creada"

# 3. Crawler. UpdateBehavior=LOG: en ejecuciones posteriores NO reescribe el esquema de la tabla,
#    así no se pierden las correcciones manuales de tipos (solo registra los cambios en el log).
aws glue create-crawler \
  --name "$CRAWLER" \
  --role "arn:aws:iam::${CUENTA}:role/p6-glue-crawler-role" \
  --database-name "$DATABASE" \
  --targets "{\"S3Targets\":[{\"Path\":\"s3://${BUCKET}/datos/ventas/\"}]}" \
  --schema-change-policy UpdateBehavior=LOG,DeleteBehavior=LOG \
  --recrawl-policy RecrawlBehavior=CRAWL_EVERYTHING > /dev/null
echo "Glue: crawler $CRAWLER creado"

bash "$CARPETA/ejecutar_crawler.sh"
