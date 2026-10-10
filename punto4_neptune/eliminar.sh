#!/usr/bin/env bash
# Punto 4 - Elimina Neptune (instancia, clúster sin snapshot, subnet group) y el security group.
# Uso: bash eliminar.sh
set -uo pipefail

export AWS_REGION=us-east-2
CLUSTER_ID=p4-neptune

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"

INSTANCIAS=$(aws neptune describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" \
  --query "DBClusters[0].DBClusterMembers[].DBInstanceIdentifier" --output text 2>/dev/null)

for INSTANCIA in $INSTANCIAS; do
  aws neptune delete-db-instance --db-instance-identifier "$INSTANCIA" > /dev/null \
    && echo "Neptune: eliminando instancia $INSTANCIA..."
done
for INSTANCIA in $INSTANCIAS; do
  until aws neptune wait db-instance-deleted --db-instance-identifier "$INSTANCIA"; do
    echo "Neptune: la instancia sigue eliminándose..."
  done
  echo "Neptune: instancia $INSTANCIA eliminada"
done

aws neptune delete-db-cluster --db-cluster-identifier "$CLUSTER_ID" --skip-final-snapshot > /dev/null \
  && echo "Neptune: eliminando clúster $CLUSTER_ID..."
while aws neptune describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" > /dev/null 2>&1; do
  sleep 20
done
echo "Neptune: clúster eliminado"

aws neptune delete-db-subnet-group --db-subnet-group-name p4-neptune-subnets \
  && echo "Subnet group p4-neptune-subnets eliminado"

SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=p4-neptune-sg \
  --query "SecurityGroups[0].GroupId" --output text)
if [ "$SG_ID" != "None" ]; then
  aws ec2 delete-security-group --group-id "$SG_ID" > /dev/null && echo "Security group p4-neptune-sg eliminado"
fi

echo
echo "######## Verificación"
echo "== Clúster";       aws neptune describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" 2>&1 | tail -1
for INSTANCIA in $INSTANCIAS; do
  echo "== Instancia $INSTANCIA"; aws neptune describe-db-instances --db-instance-identifier "$INSTANCIA" 2>&1 | tail -1
done
echo "== Subnet group";  aws neptune describe-db-subnet-groups --db-subnet-group-name p4-neptune-subnets 2>&1 | tail -1
echo "== Security group p4-neptune-sg"
aws ec2 describe-security-groups --filters Name=group-name,Values=p4-neptune-sg --query "length(SecurityGroups)"
echo "== Snapshots manuales"
aws neptune describe-db-cluster-snapshots --db-cluster-identifier "$CLUSTER_ID" --snapshot-type manual \
  --query "length(DBClusterSnapshots)" 2>&1 | tail -1
