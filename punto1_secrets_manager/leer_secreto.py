import json
import os
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError
from dotenv import load_dotenv


load_dotenv(Path(__file__).resolve().parents[1] / ".env")


def required(name):
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def mask(value):
    return value[:3] + "*" * (len(value) - 3)


# Se puede pasar otro nombre como argumento para probar que el acceso está restringido.
secret_name = sys.argv[1] if len(sys.argv) > 1 else required("PUNTO1_SECRET_NAME")

session = boto3.session.Session()
identity = session.client("sts").get_caller_identity()["Arn"]
secrets_manager = session.client("secretsmanager")

print(f"Identidad: {identity}")
print(f"Región:    {session.region_name}")
print(f"Secreto:   {secret_name}")

try:
    # Sin VersionId ni VersionStage, Secrets Manager devuelve la versión AWSCURRENT.
    response = secrets_manager.get_secret_value(SecretId=secret_name)
except ClientError as error:
    code = error.response["Error"]["Code"]
    print(f"No se pudo leer el secreto: {code}")
    print(error.response["Error"]["Message"])
    sys.exit(1)

secret = json.loads(response["SecretString"])

print(f"Versión:   {response['VersionId']} {response['VersionStages']}")
print(f"Creada:    {response['CreatedDate']:%Y-%m-%d %H:%M:%S %Z}")
print(f"Usuario:   {secret['username']}")
print(f"Password:  {mask(secret['password'])}")
