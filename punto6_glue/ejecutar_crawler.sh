#!/usr/bin/env bash
# Punto 6 - Ejecuta el crawler, espera a que termine y muestra el resultado y el esquema de la tabla.
# Uso: bash ejecutar_crawler.sh
set -euo pipefail

export AWS_REGION=us-east-2
DATABASE=p6_ventas
CRAWLER=p6-crawler-ventas

aws glue start-crawler --name "$CRAWLER"
echo "Glue: crawler $CRAWLER en ejecución..."
sleep 15
until [ "$(aws glue get-crawler --name "$CRAWLER" --query Crawler.State --output text)" = "READY" ]; do
  sleep 15
done

aws glue get-crawler --name "$CRAWLER" \
  --query "Crawler.LastCrawl.{Estado:Status,Inicio:StartTime,Mensaje:ErrorMessage}" --output table
aws glue get-crawler-metrics --crawler-name-list "$CRAWLER" \
  --query "CrawlerMetricsList[0].{SegundosUltimaEjecucion:LastRuntimeSeconds,TablasCreadas:TablesCreated,TablasActualizadas:TablesUpdated}" \
  --output table

echo "== Tablas en $DATABASE"
aws glue get-tables --database-name "$DATABASE" --query "TableList[].Name" --output text
echo "== Esquema de la tabla ventas"
aws glue get-table --database-name "$DATABASE" --name ventas \
  --query "Table.{Ubicacion:StorageDescriptor.Location,SerDe:StorageDescriptor.SerdeInfo.SerializationLibrary,Clasificacion:Parameters.classification,Encabezado:Parameters.\"skip.header.line.count\",Registros:Parameters.recordCount}" \
  --output table
aws glue get-table --database-name "$DATABASE" --name ventas \
  --query "Table.StorageDescriptor.Columns[].[Name,Type]" --output table
