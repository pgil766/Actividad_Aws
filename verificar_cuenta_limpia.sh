#!/usr/bin/env bash
# Cierre del taller - Inventario de recursos facturables en us-east-2 creados por los puntos 1 a 6.
# Uso: bash verificar_cuenta_limpia.sh
export AWS_REGION=us-east-2

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"
echo "Fecha:     $(date '+%Y-%m-%d %H:%M %Z')"

echo; echo "== EC2 en ejecución o detenidas (cobran cómputo o EBS)"
aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query "Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key=='Name']|[0].Value]" --output text
echo "== Volúmenes EBS";        aws ec2 describe-volumes --query "length(Volumes)"
echo "== IP elásticas";         aws ec2 describe-addresses --query "length(Addresses)"
echo "== NAT Gateways activos"; aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query "length(NatGateways)"
echo "== Security groups del taller (p2-*, p3-*, p4-*)"
aws ec2 describe-security-groups --filters "Name=group-name,Values=p2-*,p3-*,p4-*" --query "length(SecurityGroups)"

echo; echo "== RDS / DocumentDB / Neptune: instancias";  aws rds describe-db-instances --query "DBInstances[].[DBInstanceIdentifier,Engine]" --output text
echo "== RDS / DocumentDB / Neptune: clústeres";     aws rds describe-db-clusters --query "DBClusters[].[DBClusterIdentifier,Engine]" --output text
echo "== Snapshots manuales de clúster";              aws rds describe-db-cluster-snapshots --snapshot-type manual --query "length(DBClusterSnapshots)"
echo "== Snapshots manuales de instancia";            aws rds describe-db-snapshots --snapshot-type manual --query "length(DBSnapshots)"

echo; echo "== Redshift Serverless: namespaces"; aws redshift-serverless list-namespaces --query "namespaces[].namespaceName" --output text
echo "== Redshift Serverless: workgroups";       aws redshift-serverless list-workgroups --query "workgroups[].workgroupName" --output text

echo; echo "== Glue: crawlers del taller";        aws glue list-crawlers --query "CrawlerNames[?starts_with(@, 'p6')]" --output text
echo "== Glue: base de datos p6_ventas";          aws glue get-database --name p6_ventas 2>&1 | tail -1

echo; echo "== Buckets S3 del taller (actividad-aws-*)"
aws s3api list-buckets --query "Buckets[?starts_with(Name, 'actividad-aws')].Name" --output text
echo "(fin del inventario: las listas vacías significan que no queda nada)"
