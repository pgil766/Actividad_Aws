"""Punto 6 - Glue Data Catalog + Athena con Boto3.

Uso:
    python glue_athena.py corregir    # corrige los tipos que el crawler infirió mal
    python glue_athena.py consultas   # conteo, filtro y agrupación en Athena
    python glue_athena.py agregar     # sube la segunda parte de los datos (10 registros nuevos)
    python glue_athena.py manual      # crea la misma tabla con DDL en Athena y compara con la del crawler

No usa secretos: S3, Glue y Athena se autorizan con los permisos IAM de user_cli.
"""
import os
import sys
import time
from pathlib import Path

import boto3
from dotenv import load_dotenv


folder = Path(__file__).resolve().parent
load_dotenv(folder.parent / ".env")


def required(name):
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


database = required("GLUE_DATABASE")
bucket = required("P6_S3_BUCKET")
table = "ventas"
results_location = f"s3://{bucket}/athena-resultados/"

session = boto3.session.Session()
glue = session.client("glue")
athena = session.client("athena")
s3 = session.client("s3")


def athena_query(sql, title=None):
    """Ejecuta una consulta en Athena, espera a que termine y devuelve columnas, filas y MB escaneados."""
    query_id = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": database},
        ResultConfiguration={"OutputLocation": results_location},
        WorkGroup="primary",
    )["QueryExecutionId"]
    while True:
        execution = athena.get_query_execution(QueryExecutionId=query_id)["QueryExecution"]
        state = execution["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(1)
    if state != "SUCCEEDED":
        raise RuntimeError(f"{state}: {execution['Status'].get('StateChangeReason')}\nSQL: {sql}")

    scanned_mb = execution["Statistics"].get("DataScannedInBytes", 0) / 1024 / 1024
    rows = []
    for page in athena.get_paginator("get_query_results").paginate(QueryExecutionId=query_id):
        rows += [[field.get("VarCharValue") for field in row["Data"]] for row in page["ResultSet"]["Rows"]]
    columns, data = (rows[0], rows[1:]) if rows else ([], [])
    if title:
        print(f"\n== {title}  [{scanned_mb:.4f} MB escaneados]")
        print(f"   SQL: {' '.join(sql.split())}")
        widths = [max(len(str(c)), *(len(str(r[i])) for r in data)) for i, c in enumerate(columns)] if data else []
        if data:
            print("   " + " | ".join(str(c).ljust(w) for c, w in zip(columns, widths)))
            print("   " + "-+-".join("-" * w for w in widths))
            for row in data:
                print("   " + " | ".join(str(v).ljust(w) for v, w in zip(row, widths)))
    return columns, data


def print_schema(name):
    columns = glue.get_table(DatabaseName=database, Name=name)["Table"]["StorageDescriptor"]["Columns"]
    print(f"Esquema de {database}.{name}: " + ", ".join(f"{c['Name']} {c['Type']}" for c in columns))


def corregir():
    """Corrige los tipos inferidos: fecha (string -> date) y codigo_tienda (bigint -> string)."""
    correcciones = {"fecha": "date", "codigo_tienda": "string"}
    current = glue.get_table(DatabaseName=database, Name=table)["Table"]
    print("Antes:   ", end=""); print_schema(table)

    editable = {"Name", "Description", "Owner", "Retention", "StorageDescriptor",
                "PartitionKeys", "TableType", "Parameters"}
    table_input = {key: value for key, value in current.items() if key in editable}
    for column in table_input["StorageDescriptor"]["Columns"]:
        if column["Name"] in correcciones:
            column["Type"] = correcciones[column["Name"]]
    glue.update_table(DatabaseName=database, TableInput=table_input)
    print("Después: ", end=""); print_schema(table)


def consultas():
    athena_query(f"SELECT COUNT(*) AS registros FROM {table}", "Conteo de registros")
    athena_query(f"SELECT * FROM {table} ORDER BY venta_id LIMIT 3",
                 "Muestra: codigo_tienda conserva los ceros y fecha es DATE")
    athena_query(f"""
        SELECT venta_id, fecha, codigo_tienda, ciudad, producto, cantidad,
               cantidad * precio_unitario AS total
        FROM {table}
        WHERE categoria = 'Electrónica' AND fecha >= DATE '2026-02-01'
        ORDER BY total DESC
    """, "Filtro: ventas de Electrónica desde el 1 de febrero de 2026")
    athena_query(f"""
        SELECT ciudad, codigo_tienda,
               COUNT(*)                          AS ventas,
               SUM(cantidad)                     AS unidades,
               SUM(cantidad * precio_unitario)   AS ingresos
        FROM {table}
        GROUP BY ciudad, codigo_tienda
        ORDER BY ingresos DESC
    """, "Agrupación: ventas, unidades e ingresos por ciudad/tienda")


def agregar():
    key = "datos/ventas/ventas_parte2.csv"
    s3.upload_file(str(folder / "datos" / "ventas_parte2.csv"), bucket, key)
    print(f"S3: s3://{bucket}/{key} (10 registros nuevos)")


def manual():
    athena_query("DROP TABLE IF EXISTS ventas_manual")
    athena_query(f"""
        CREATE EXTERNAL TABLE ventas_manual (
            venta_id        INT,
            fecha           DATE,
            codigo_tienda   STRING,
            ciudad          STRING,
            producto        STRING,
            categoria       STRING,
            cantidad        INT,
            precio_unitario BIGINT
        )
        ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
        STORED AS TEXTFILE
        LOCATION 's3://{bucket}/datos/ventas/'
        TBLPROPERTIES ('skip.header.line.count' = '1')
    """, "DDL manual: CREATE EXTERNAL TABLE ventas_manual")
    print_schema("ventas")
    print_schema("ventas_manual")
    athena_query(f"""
        SELECT 'crawler' AS tabla, COUNT(*) AS registros, MIN(fecha) AS desde, MAX(fecha) AS hasta FROM {table}
        UNION ALL
        SELECT 'manual', COUNT(*), MIN(fecha), MAX(fecha) FROM ventas_manual
    """, "Comparación: las dos tablas leen los mismos archivos")


if __name__ == "__main__":
    acciones = {"corregir": corregir, "consultas": consultas, "agregar": agregar, "manual": manual}
    if len(sys.argv) != 2 or sys.argv[1] not in acciones:
        raise SystemExit("Uso: python glue_athena.py corregir|consultas|agregar|manual")
    print(f"Identidad AWS: {session.client('sts').get_caller_identity()['Arn']}")
    acciones[sys.argv[1]]()
