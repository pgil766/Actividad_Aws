"""Punto 5 - Carga y análisis en Redshift Serverless con Boto3 y la Redshift Data API.

1. Sube los CSV a S3.
2. Crea las tablas y las carga con COPY (Redshift lee S3 con el rol p5-redshift-s3-role).
3. Ejecuta consultas con filtro, unión y agregación.

Las sentencias SQL se envían con la Data API autenticando con el secreto del admin
(SecretArn), que Redshift administra en Secrets Manager: el código no tiene contraseñas.
"""
import os
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


namespace_name = required("REDSHIFT_NAMESPACE")
workgroup_name = required("REDSHIFT_WORKGROUP")
database = required("REDSHIFT_DATABASE")
bucket = required("P5_S3_BUCKET")

session = boto3.session.Session()
s3 = session.client("s3")
data_api = session.client("redshift-data")

# El ARN del secreto y del rol se leen del namespace: no se escriben en el código
namespace = session.client("redshift-serverless").get_namespace(namespaceName=namespace_name)["namespace"]
secret_arn = namespace["adminPasswordSecretArn"]
role_arn = namespace["defaultIamRoleArn"]


def run(sql, title=None):
    """Envía una sentencia con la Data API, espera a que termine y devuelve las filas."""
    statement_id = data_api.execute_statement(
        WorkgroupName=workgroup_name, Database=database, SecretArn=secret_arn, Sql=sql
    )["Id"]
    while True:
        status = data_api.describe_statement(Id=statement_id)
        if status["Status"] in ("FINISHED", "FAILED", "ABORTED"):
            break
        time.sleep(1)
    if status["Status"] != "FINISHED":
        raise RuntimeError(f"{status['Status']}: {status.get('Error')}\nSQL: {sql}")

    seconds = status["Duration"] / 1e9
    if title:
        print(f"[{status['Status']} en {seconds:.2f} s] {title}")
    if not status.get("HasResultSet"):
        return [], []

    columns, rows, token = None, [], None
    while True:
        kwargs = {"Id": statement_id, **({"NextToken": token} if token else {})}
        page = data_api.get_statement_result(**kwargs)
        columns = columns or [column["name"] for column in page["ColumnMetadata"]]
        rows += [[next(iter(field.values())) if not field.get("isNull") else None for field in record]
                 for record in page["Records"]]
        token = page.get("NextToken")
        if not token:
            return columns, rows


def show(title, question, sql):
    columns, rows = run(sql)
    print(f"\n== {title}\n   Pregunta: {question}")
    widths = [max(len(str(c)), *(len(str(r[i])) for r in rows)) for i, c in enumerate(columns)] if rows else []
    print("   " + " | ".join(str(c).ljust(w) for c, w in zip(columns, widths)))
    print("   " + "-+-".join("-" * w for w in widths))
    for row in rows:
        print("   " + " | ".join(str(v).ljust(w) for v, w in zip(row, widths)))


print(f"Identidad AWS: {session.client('sts').get_caller_identity()['Arn']}")
print(f"Workgroup:     {workgroup_name} · base de datos {database}")
print(f"Secreto admin: {secret_arn}")
print(f"Rol para COPY: {role_arn}\n")

# 1. Subir los CSV a S3
for name in ("clientes", "pedidos"):
    s3.upload_file(str(folder / "datos" / f"{name}.csv"), bucket, f"datos/{name}.csv")
    print(f"S3: s3://{bucket}/datos/{name}.csv")
print()

# 2. Crear tablas y cargarlas con COPY
run("DROP TABLE IF EXISTS pedidos", "DROP pedidos")
run("DROP TABLE IF EXISTS clientes", "DROP clientes")
run("""
    CREATE TABLE clientes (
        cliente_id     INTEGER      NOT NULL PRIMARY KEY,
        nombre         VARCHAR(60)  NOT NULL,
        ciudad         VARCHAR(40)  NOT NULL,
        segmento       VARCHAR(20)  NOT NULL,
        fecha_registro DATE         NOT NULL
    ) DISTSTYLE ALL
""", "CREATE TABLE clientes")
run("""
    CREATE TABLE pedidos (
        pedido_id  INTEGER       NOT NULL PRIMARY KEY,
        cliente_id INTEGER       NOT NULL REFERENCES clientes (cliente_id),
        fecha      DATE          NOT NULL,
        categoria  VARCHAR(30)   NOT NULL,
        cantidad   SMALLINT      NOT NULL,
        monto      DECIMAL(12,2) NOT NULL
    ) DISTKEY (cliente_id) SORTKEY (fecha)
""", "CREATE TABLE pedidos")
for name in ("clientes", "pedidos"):
    run(f"""
        COPY {name}
        FROM 's3://{bucket}/datos/{name}.csv'
        IAM_ROLE '{role_arn}'
        FORMAT AS CSV IGNOREHEADER 1 DATEFORMAT 'YYYY-MM-DD' REGION 'us-east-2'
    """, f"COPY {name} desde S3")

show("Validación de la carga", "¿Cuántas filas se cargaron en cada tabla?", """
    SELECT 'clientes' AS tabla, COUNT(*) AS filas FROM clientes
    UNION ALL
    SELECT 'pedidos', COUNT(*) FROM pedidos
""")

# 3. Consultas
show("Consulta 1 · Filtro",
     "¿Qué pedidos de Electrónica superaron 1.000 en el primer semestre de 2026?", """
    SELECT pedido_id, cliente_id, fecha, cantidad, monto
    FROM pedidos
    WHERE categoria = 'Electrónica'
      AND monto > 1000
      AND fecha BETWEEN '2026-01-01' AND '2026-06-30'
    ORDER BY monto DESC
""")

show("Consulta 2 · Unión (JOIN)",
     "¿Quiénes hicieron los 5 pedidos más grandes y de qué ciudad y segmento son?", """
    SELECT p.pedido_id, c.nombre, c.ciudad, c.segmento, p.categoria, p.monto
    FROM pedidos p
    JOIN clientes c ON c.cliente_id = p.cliente_id
    ORDER BY p.monto DESC
    LIMIT 5
""")

show("Consulta 3 · Agregación (con JOIN)",
     "¿Cuánto vende cada ciudad, cuántos pedidos hace y cuál es su ticket promedio?", """
    SELECT c.ciudad,
           COUNT(DISTINCT c.cliente_id)  AS clientes_con_pedidos,
           COUNT(p.pedido_id)            AS pedidos,
           SUM(p.monto)                  AS ventas_totales,
           ROUND(AVG(p.monto), 2)        AS ticket_promedio
    FROM pedidos p
    JOIN clientes c ON c.cliente_id = p.cliente_id
    GROUP BY c.ciudad
    ORDER BY ventas_totales DESC
""")
