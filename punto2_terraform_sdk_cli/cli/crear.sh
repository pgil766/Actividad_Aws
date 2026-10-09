#!/usr/bin/env bash
# Punto 2 - Despliegue con AWS CLI: S3 + EC2 + RDS (contraseña administrada en Secrets Manager).
# Uso: bash crear.sh
set -euo pipefail

export AWS_REGION=us-east-2
PREFIJO=p2-cli
TAGS='Key=Proyecto,Value=actividad-aws Key=Punto,Value=2 Key=Metodo,Value=cli'

echo "Identidad: $(aws sts get-caller-identity --query Arn --output text)"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="actividad-aws-p2-${CUENTA}-cli"

# Red: VPC por defecto y sus subredes
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query "sort(Subnets[].SubnetId)" --output text)
SUBNET_EC2=$(echo "$SUBNETS" | awk '{print $1}')
echo "VPC por defecto: $VPC_ID"

# S3
aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging "TagSet=[{Key=Proyecto,Value=actividad-aws},{Key=Punto,Value=2},{Key=Metodo,Value=cli}]"
echo "S3: bucket $BUCKET creado"

# Security groups
EC2_SG=$(aws ec2 create-security-group --group-name "${PREFIJO}-ec2-sg" \
  --description "EC2 del punto 2: sin entradas, solo salida" --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Proyecto,Value=actividad-aws},{Key=Punto,Value=2},{Key=Metodo,Value=cli}]" \
  --query GroupId --output text)
RDS_SG=$(aws ec2 create-security-group --group-name "${PREFIJO}-rds-sg" \
  --description "RDS del punto 2: PostgreSQL solo desde la EC2" --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Proyecto,Value=actividad-aws},{Key=Punto,Value=2},{Key=Metodo,Value=cli}]" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$RDS_SG" \
  --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=${EC2_SG},Description='PostgreSQL desde el SG de la EC2'}]" > /dev/null
echo "Security groups: $EC2_SG (EC2), $RDS_SG (RDS, 5432 desde EC2)"

# EC2 (Amazon Linux 2023 más reciente, sin IPv4 pública)
AMI=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text)
INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.micro --count 1 \
  --network-interfaces "DeviceIndex=0,SubnetId=${SUBNET_EC2},Groups=${EC2_SG},AssociatePublicIpAddress=false" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PREFIJO}-ec2},{Key=Proyecto,Value=actividad-aws},{Key=Punto,Value=2},{Key=Metodo,Value=cli}]" \
  --query "Instances[0].InstanceId" --output text)
echo "EC2: instancia $INSTANCE_ID lanzada"

# RDS: --manage-master-user-password hace que RDS genere la contraseña y la guarde en Secrets Manager
# shellcheck disable=SC2086
aws rds create-db-subnet-group --db-subnet-group-name "${PREFIJO}-db-subnets" \
  --db-subnet-group-description "Subredes de la VPC por defecto" \
  --subnet-ids $SUBNETS --tags $TAGS > /dev/null
# shellcheck disable=SC2086
aws rds create-db-instance \
  --db-instance-identifier "${PREFIJO}-db" \
  --engine postgres \
  --db-instance-class db.t4g.micro \
  --db-name actividad \
  --allocated-storage 20 \
  --storage-type gp3 \
  --storage-encrypted \
  --master-username dbadmin \
  --manage-master-user-password \
  --db-subnet-group-name "${PREFIJO}-db-subnets" \
  --vpc-security-group-ids "$RDS_SG" \
  --no-publicly-accessible \
  --no-multi-az \
  --backup-retention-period 0 \
  --no-deletion-protection \
  --tags $TAGS > /dev/null
echo "RDS: creando ${PREFIJO}-db (tarda unos minutos)..."

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "EC2: running"
aws rds wait db-instance-available --db-instance-identifier "${PREFIJO}-db"
echo "RDS: available"

echo
echo "Salidas:"
echo "  s3_bucket       = $BUCKET"
echo "  ec2_instance_id = $INSTANCE_ID"
echo "  rds_endpoint    = $(aws rds describe-db-instances --db-instance-identifier "${PREFIJO}-db" --query "DBInstances[0].Endpoint.Address" --output text)"
echo "  rds_secret_arn  = $(aws rds describe-db-instances --db-instance-identifier "${PREFIJO}-db" --query "DBInstances[0].MasterUserSecret.SecretArn" --output text)"
