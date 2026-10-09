#!/usr/bin/env bash
# Punto 3 - Túnel SSH hacia DocumentDB a través de la EC2 bastión.
#
#   PC (localhost:27017) --SSH:22--> bastión (subred pública) --27017+TLS--> DocumentDB (VPC)
#
# Uso:  bash tunel.sh            # deja el túnel abierto en primer plano (Ctrl+C para cerrarlo)
# Requisitos: AWS CLI con user_cli, llave privada del par de claves del bastión.
set -euo pipefail

export AWS_REGION=us-east-2
LLAVE="${LLAVE_SSH:-$HOME/pgm-mv.pem}"
CLUSTER_ID="${DOCDB_CLUSTER_ID:-p3-docdb}"
CARPETA="$(cd "$(dirname "$0")" && pwd)"

# Certificado de AWS para validar el TLS de DocumentDB
if [ ! -f "$CARPETA/global-bundle.pem" ]; then
  curl -sSo "$CARPETA/global-bundle.pem" https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
  echo "Certificado descargado: $CARPETA/global-bundle.pem"
fi

# Se consultan en AWS para no dejar IPs ni endpoints escritos en el código
BASTION_IP=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=p3-bastion Name=instance-state-name,Values=running \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
DOCDB_ENDPOINT=$(aws docdb describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" \
  --query "DBClusters[0].Endpoint" --output text)

echo "Bastión:    ec2-user@${BASTION_IP}"
echo "DocumentDB: ${DOCDB_ENDPOINT}:27017"
echo "Túnel:      localhost:27017 -> ${DOCDB_ENDPOINT}:27017 (Ctrl+C para cerrar)"

exec ssh -i "$LLAVE" -N \
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L "27017:${DOCDB_ENDPOINT}:27017" "ec2-user@${BASTION_IP}"
