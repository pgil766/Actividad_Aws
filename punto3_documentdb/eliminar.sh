#!/usr/bin/env bash
# Punto 3 - Elimina DocumentDB, el bastión y los security groups, y verifica que no quede nada.
# Uso: bash eliminar.sh   (cerrar antes el túnel SSH)
set -uo pipefail

export AWS_REGION=us-east-2
CLUSTER_ID=p3-docdb

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"

SECRETO=$(aws docdb describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" \
  --query "DBClusters[0].MasterUserSecret.SecretArn" --output text 2>/dev/null)
INSTANCIAS=$(aws docdb describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" \
  --query "DBClusters[0].DBClusterMembers[].DBInstanceIdentifier" --output text 2>/dev/null)

# 1. DocumentDB: primero las instancias, luego el clúster (sin snapshot final)
for INSTANCIA in $INSTANCIAS; do
  aws docdb delete-db-instance --db-instance-identifier "$INSTANCIA" > /dev/null \
    && echo "DocumentDB: eliminando instancia $INSTANCIA..."
done

# 2. Bastión (en paralelo mientras se borra DocumentDB)
BASTION=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=p3-bastion Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$BASTION" ]; then
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --instance-ids $BASTION > /dev/null && echo "EC2: terminando bastión $BASTION..."
fi

for INSTANCIA in $INSTANCIAS; do
  until aws docdb wait db-instance-deleted --db-instance-identifier "$INSTANCIA"; do
    echo "DocumentDB: la instancia sigue eliminándose..."
  done
  echo "DocumentDB: instancia $INSTANCIA eliminada"
done

aws docdb delete-db-cluster --db-cluster-identifier "$CLUSTER_ID" --skip-final-snapshot > /dev/null \
  && echo "DocumentDB: eliminando clúster $CLUSTER_ID..."
while aws docdb describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" > /dev/null 2>&1; do
  sleep 20
done
echo "DocumentDB: clúster eliminado"

if [ -n "$BASTION" ]; then
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $BASTION && echo "EC2: bastión terminado"
fi

# 3. Security groups: primero el de DocumentDB, porque referencia al del bastión
for NOMBRE in p3-docdb-sg p3-bastion-sg; do
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${NOMBRE}" \
    --query "SecurityGroups[0].GroupId" --output text)
  if [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group --group-id "$SG_ID" > /dev/null && echo "Security group $NOMBRE eliminado"
  fi
done

# 4. Verificación
echo
echo "######## Verificación"
echo "== Clúster DocumentDB";  aws docdb describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" 2>&1 | tail -1
for INSTANCIA in $INSTANCIAS; do
  echo "== Instancia $INSTANCIA"; aws docdb describe-db-instances --db-instance-identifier "$INSTANCIA" 2>&1 | tail -1
done
echo "== Bastión"
aws ec2 describe-instances --filters Name=tag:Name,Values=p3-bastion \
  --query "Reservations[].Instances[].[InstanceId,State.Name]" --output text
echo "== Security groups p3-*"
aws ec2 describe-security-groups --filters Name=group-name,Values=p3-docdb-sg,p3-bastion-sg \
  --query "length(SecurityGroups)"
if [ -n "$SECRETO" ] && [ "$SECRETO" != "None" ]; then
  echo "== Secreto $SECRETO"
  aws secretsmanager describe-secret --secret-id "$SECRETO" \
    --query "{Nombre:Name,FechaEliminacion:DeletedDate}" --output text 2>&1 | tail -1
fi
echo "== Snapshots manuales del clúster"
aws docdb describe-db-cluster-snapshots --db-cluster-identifier "$CLUSTER_ID" --snapshot-type manual \
  --query "length(DBClusterSnapshots)" 2>&1 | tail -1
