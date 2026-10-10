"""Punto 4 - Grafo en Amazon Neptune consultado desde Python con openCypher.

Conexión: endpoint público de Neptune (motor >= 1.4.6) con autenticación IAM.
El cliente `neptunedata` de boto3 firma cada petición con SigV4 usando las
credenciales de user_cli: no hay usuarios ni contraseñas de base de datos.
"""
import json
import os
from pathlib import Path

import boto3
from botocore.config import Config
from dotenv import load_dotenv


load_dotenv(Path(__file__).resolve().parents[1] / ".env")


def required(name):
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


cluster_id = required("NEPTUNE_CLUSTER_ID")

session = boto3.session.Session()
cluster = session.client("neptune").describe_db_clusters(DBClusterIdentifier=cluster_id)["DBClusters"][0]
endpoint_url = f"https://{cluster['Endpoint']}:{cluster['Port']}"

neptune = session.client(
    "neptunedata",
    endpoint_url=endpoint_url,
    config=Config(retries={"max_attempts": 1}, read_timeout=120),
)


def cypher(query, **parameters):
    request = {"openCypherQuery": query}
    if parameters:
        request["parameters"] = json.dumps(parameters)
    return neptune.execute_open_cypher_query(**request)["results"]


# ---------- Datos del grafo: 12 vértices y 19 aristas ----------
PERSONAS = [
    ("Ana", 22, "Medellín"),
    ("Bruno", 24, "Bogotá"),
    ("Carla", 21, "Medellín"),
    ("Diego", 23, "Cali"),
    ("Elena", 25, "Bogotá"),
    ("Felipe", 22, "Cali"),
]
CIUDADES = ["Medellín", "Bogotá", "Cali"]
CURSOS = ["Ingeniería de Datos", "Bases de Datos NoSQL", "Cloud Computing"]
AMISTADES = [
    ("Ana", "Bruno"),
    ("Ana", "Carla"),
    ("Bruno", "Carla"),
    ("Carla", "Diego"),
    ("Diego", "Elena"),
    ("Elena", "Felipe"),
]
INSCRIPCIONES = [
    ("Ana", "Ingeniería de Datos"),
    ("Ana", "Bases de Datos NoSQL"),
    ("Bruno", "Ingeniería de Datos"),
    ("Carla", "Cloud Computing"),
    ("Diego", "Bases de Datos NoSQL"),
    ("Elena", "Ingeniería de Datos"),
    ("Felipe", "Cloud Computing"),
]


def cargar_grafo():
    # Se borra lo cargado antes por este programa para que la carga sea repetible
    cypher("MATCH (n {proyecto: 'p4'}) DETACH DELETE n")

    for nombre in CIUDADES:
        cypher("CREATE (:Ciudad {nombre: $nombre, proyecto: 'p4'})", nombre=nombre)
    for nombre in CURSOS:
        cypher("CREATE (:Curso {nombre: $nombre, proyecto: 'p4'})", nombre=nombre)
    for nombre, edad, ciudad in PERSONAS:
        cypher(
            "MATCH (c:Ciudad {nombre: $ciudad}) "
            "CREATE (:Persona {nombre: $nombre, edad: $edad, proyecto: 'p4'})-[:VIVE_EN]->(c)",
            nombre=nombre, edad=edad, ciudad=ciudad,
        )
    for origen, destino in AMISTADES:
        cypher(
            "MATCH (a:Persona {nombre: $origen}), (b:Persona {nombre: $destino}) "
            "CREATE (a)-[:AMIGO_DE]->(b)",
            origen=origen, destino=destino,
        )
    for persona, curso in INSCRIPCIONES:
        cypher(
            "MATCH (p:Persona {nombre: $persona}), (c:Curso {nombre: $curso}) "
            "CREATE (p)-[:INSCRITO_EN]->(c)",
            persona=persona, curso=curso,
        )


def imprimir(titulo, filas):
    print(f"\n== {titulo}")
    for fila in filas:
        print("  ", fila)


print(f"Identidad AWS: {session.client('sts').get_caller_identity()['Arn']}")
print(f"Endpoint:      {endpoint_url}")
estado = neptune.get_engine_status()
print(f"Neptune:       {estado['status']} · motor {estado['dbEngineVersion']} · "
      f"IAM {estado['features']['IAMAuthentication']}")

cargar_grafo()

conteo = cypher(
    "MATCH (n {proyecto: 'p4'}) WITH count(n) AS vertices "
    "MATCH ({proyecto: 'p4'})-[r]->({proyecto: 'p4'}) RETURN vertices, count(r) AS aristas"
)[0]
print(f"\nGrafo cargado: {conteo['vertices']} vértices y {conteo['aristas']} aristas")
imprimir("Aristas por tipo", cypher(
    "MATCH ({proyecto: 'p4'})-[r]->() RETURN type(r) AS tipo, count(r) AS cantidad ORDER BY tipo"
))

# Consulta 1: recorre 2 saltos de AMIGO_DE (amigos de amigos que aún no son amigos)
imprimir("Consulta 1 · Amigos de amigos de Ana (posibles nuevas amistades)", cypher(
    "MATCH (a:Persona {nombre: 'Ana'})-[:AMIGO_DE]-(amigo:Persona)-[:AMIGO_DE]-(sugerido:Persona) "
    "WHERE sugerido <> a AND NOT (a)-[:AMIGO_DE]-(sugerido) "
    "RETURN sugerido.nombre AS sugerido, collect(DISTINCT amigo.nombre) AS en_comun"
))

# Consulta 2: recorre INSCRITO_EN de ida y vuelta y luego VIVE_EN
imprimir("Consulta 2 · Compañeros de curso de Ana y la ciudad donde viven", cypher(
    "MATCH (a:Persona {nombre: 'Ana'})-[:INSCRITO_EN]->(c:Curso)<-[:INSCRITO_EN]-(p:Persona)-[:VIVE_EN]->(ci:Ciudad) "
    "RETURN c.nombre AS curso, p.nombre AS companero, ci.nombre AS ciudad ORDER BY curso, companero"
))

# Consulta 3: recorrido de longitud variable por AMIGO_DE (camino más corto)
imprimir("Consulta 3 · Cadena de amistad más corta entre Ana y Felipe", cypher(
    "MATCH camino = (a:Persona {nombre: 'Ana'})-[:AMIGO_DE*1..6]-(f:Persona {nombre: 'Felipe'}) "
    "RETURN [n IN nodes(camino) | n.nombre] AS cadena, length(camino) AS saltos "
    "ORDER BY saltos LIMIT 1"
))
