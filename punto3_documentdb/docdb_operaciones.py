import json
import os
from pathlib import Path
from pprint import pprint
from uuid import uuid4

import boto3
from dotenv import load_dotenv
from pymongo import MongoClient


folder = Path(__file__).resolve().parent
load_dotenv(folder.parent / ".env")


def required(name):
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


cluster_id = required("DOCDB_CLUSTER_ID")
database_name = required("DOCDB_NAME")
collection_name = required("DOCDB_COLLECTION")
host = os.getenv("DOCDB_HOST", "localhost")  # localhost = extremo local del túnel SSH
port = int(os.getenv("DOCDB_PORT", "27017"))


# 1. Contraseña: se pide a Secrets Manager en tiempo de ejecución.
#    El ARN del secreto se obtiene del propio clúster (lo administra DocumentDB).
session = boto3.session.Session()
cluster = session.client("docdb").describe_db_clusters(DBClusterIdentifier=cluster_id)["DBClusters"][0]
secret_arn = cluster["MasterUserSecret"]["SecretArn"]
secret = json.loads(
    session.client("secretsmanager").get_secret_value(SecretId=secret_arn)["SecretString"]
)
print(f"Identidad AWS: {session.client('sts').get_caller_identity()['Arn']}")
print(f"Secreto:       {secret_arn}")
print(f"Usuario DB:    {secret['username']}")

# 2. Conexión por el túnel con TLS.
#    tlsAllowInvalidHostnames: el certificado es para *.docdb.amazonaws.com y nos conectamos a localhost.
#    retryWrites=False: DocumentDB no soporta retryable writes.
client = MongoClient(
    host=host,
    port=port,
    username=secret["username"],
    password=secret["password"],
    tls=True,
    tlsCAFile=str(folder / "global-bundle.pem"),
    tlsAllowInvalidHostnames=True,
    directConnection=True,
    retryWrites=False,
    serverSelectionTimeoutMS=10000,
)

data_file = folder / "datos" / "customers.json"
with data_file.open(encoding="utf-8") as file:
    documents = json.load(file)

load_id = str(uuid4())
for document in documents:
    document["load_id"] = load_id

try:
    info = client.server_info()
    print(f"Conectado a DocumentDB (API MongoDB {info['version']}) en {host}:{port}\n")

    collection = client[database_name][collection_name]

    # 3. Inserción y validación
    collection.insert_many(documents)
    loaded_documents = collection.count_documents({"load_id": load_id})
    if loaded_documents != len(documents):
        raise RuntimeError(
            f"Validation failed: expected {len(documents)} documents, found {loaded_documents}."
        )
    print(f"Base de datos '{database_name}', colección '{collection_name}': "
          f"{loaded_documents} documentos insertados (load_id={load_id})\n")

    # 4. Búsqueda con filtro: clientes activos mayores de 30 años
    print("== Filtro: clientes activos con más de 30 años")
    for document in collection.find(
        {"load_id": load_id, "status": "active", "age": {"$gt": 30}},
        {"_id": 0, "name": 1, "city": 1, "age": 1, "amount": 1},
    ):
        print(document)

    # 5. Ordenación: los 5 clientes con mayor monto
    print("\n== Ordenación: top 5 por monto (descendente)")
    for document in (
        collection.find({"load_id": load_id}, {"_id": 0, "name": 1, "city": 1, "amount": 1})
        .sort("amount", -1)
        .limit(5)
    ):
        print(document)

    # 6. Agregación: clientes, monto total y promedio por ciudad
    print("\n== Agregación: resumen por ciudad")
    pipeline = [
        {"$match": {"load_id": load_id}},
        {"$group": {
            "_id": "$city",
            "clientes": {"$sum": 1},
            "monto_total": {"$sum": "$amount"},
            "monto_promedio": {"$avg": "$amount"},
            "edad_promedio": {"$avg": "$age"},
        }},
        {"$sort": {"monto_total": -1}},
    ]
    for row in collection.aggregate(pipeline):
        row["monto_promedio"] = round(row["monto_promedio"], 2)
        row["edad_promedio"] = round(row["edad_promedio"], 1)
        pprint(row, sort_dicts=False)
finally:
    client.close()
