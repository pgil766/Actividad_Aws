"""Punto 2 - Despliegue con Boto3: S3 + EC2 + RDS (contraseña administrada en Secrets Manager).

Uso:
    python desplegar.py crear
    python desplegar.py eliminar

Las credenciales se toman del perfil de user_cli (~/.aws/credentials); el código no
contiene contraseñas. Los recursos se ubican por nombre, igual que en la versión Terraform.
"""
import sys

import boto3
from botocore.exceptions import ClientError


REGION = "us-east-2"
PREFIJO = "p2-boto3"
EC2_INSTANCE_TYPE = "t3.micro"
DB_INSTANCE_CLASS = "db.t4g.micro"
DB_USERNAME = "dbadmin"
TAGS = [
    {"Key": "Proyecto", "Value": "actividad-aws"},
    {"Key": "Punto", "Value": "2"},
    {"Key": "Metodo", "Value": "boto3"},
]

session = boto3.session.Session(region_name=REGION)
sts = session.client("sts")
s3 = session.client("s3")
ec2 = session.client("ec2")
rds = session.client("rds")

account_id = sts.get_caller_identity()["Account"]
bucket_name = f"actividad-aws-p2-{account_id}-boto3"


def default_network():
    vpc_id = ec2.describe_vpcs(Filters=[{"Name": "isDefault", "Values": ["true"]}])["Vpcs"][0]["VpcId"]
    subnets = ec2.describe_subnets(Filters=[{"Name": "vpc-id", "Values": [vpc_id]}])["Subnets"]
    return vpc_id, sorted(subnet["SubnetId"] for subnet in subnets)


def latest_amazon_linux_ami():
    images = ec2.describe_images(
        Owners=["amazon"],
        Filters=[
            {"Name": "name", "Values": ["al2023-ami-2023*-x86_64"]},
            {"Name": "state", "Values": ["available"]},
        ],
    )["Images"]
    return max(images, key=lambda image: image["CreationDate"])["ImageId"]


def find_security_group(name):
    groups = ec2.describe_security_groups(Filters=[{"Name": "group-name", "Values": [name]}])["SecurityGroups"]
    return groups[0]["GroupId"] if groups else None


def find_instances():
    reservations = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Name", "Values": [f"{PREFIJO}-ec2"]},
            {"Name": "instance-state-name", "Values": ["pending", "running", "stopping", "stopped"]},
        ]
    )["Reservations"]
    return [instance["InstanceId"] for reservation in reservations for instance in reservation["Instances"]]


def crear():
    print(f"Identidad: {sts.get_caller_identity()['Arn']}")
    vpc_id, subnet_ids = default_network()
    print(f"VPC por defecto: {vpc_id} ({len(subnet_ids)} subredes)")

    # S3
    s3.create_bucket(Bucket=bucket_name, CreateBucketConfiguration={"LocationConstraint": REGION})
    s3.put_bucket_tagging(Bucket=bucket_name, Tagging={"TagSet": TAGS})
    print(f"S3: bucket {bucket_name} creado")

    # Security groups
    ec2_sg = ec2.create_security_group(
        GroupName=f"{PREFIJO}-ec2-sg",
        Description="EC2 del punto 2: sin entradas, solo salida",
        VpcId=vpc_id,
        TagSpecifications=[{"ResourceType": "security-group", "Tags": TAGS}],
    )["GroupId"]
    rds_sg = ec2.create_security_group(
        GroupName=f"{PREFIJO}-rds-sg",
        Description="RDS del punto 2: PostgreSQL solo desde la EC2",
        VpcId=vpc_id,
        TagSpecifications=[{"ResourceType": "security-group", "Tags": TAGS}],
    )["GroupId"]
    ec2.authorize_security_group_ingress(
        GroupId=rds_sg,
        IpPermissions=[{
            "IpProtocol": "tcp",
            "FromPort": 5432,
            "ToPort": 5432,
            "UserIdGroupPairs": [{"GroupId": ec2_sg, "Description": "PostgreSQL desde el SG de la EC2"}],
        }],
    )
    print(f"Security groups: {ec2_sg} (EC2), {rds_sg} (RDS, 5432 desde EC2)")

    # EC2 (sin IPv4 pública para evitar su cobro)
    instance_id = ec2.run_instances(
        ImageId=latest_amazon_linux_ami(),
        InstanceType=EC2_INSTANCE_TYPE,
        MinCount=1,
        MaxCount=1,
        NetworkInterfaces=[{
            "DeviceIndex": 0,
            "SubnetId": subnet_ids[0],
            "Groups": [ec2_sg],
            "AssociatePublicIpAddress": False,
        }],
        TagSpecifications=[{"ResourceType": "instance", "Tags": TAGS + [{"Key": "Name", "Value": f"{PREFIJO}-ec2"}]}],
    )["Instances"][0]["InstanceId"]
    print(f"EC2: instancia {instance_id} lanzada")

    # RDS: ManageMasterUserPassword hace que RDS genere la contraseña y la guarde en Secrets Manager
    rds.create_db_subnet_group(
        DBSubnetGroupName=f"{PREFIJO}-db-subnets",
        DBSubnetGroupDescription="Subredes de la VPC por defecto",
        SubnetIds=subnet_ids,
        Tags=TAGS,
    )
    rds.create_db_instance(
        DBInstanceIdentifier=f"{PREFIJO}-db",
        Engine="postgres",
        DBInstanceClass=DB_INSTANCE_CLASS,
        DBName="actividad",
        AllocatedStorage=20,
        StorageType="gp3",
        StorageEncrypted=True,
        MasterUsername=DB_USERNAME,
        ManageMasterUserPassword=True,
        DBSubnetGroupName=f"{PREFIJO}-db-subnets",
        VpcSecurityGroupIds=[rds_sg],
        PubliclyAccessible=False,
        MultiAZ=False,
        BackupRetentionPeriod=0,
        DeletionProtection=False,
        Tags=TAGS,
    )
    print(f"RDS: creando {PREFIJO}-db (tarda unos minutos)...")

    ec2.get_waiter("instance_running").wait(InstanceIds=[instance_id])
    print("EC2: running")
    rds.get_waiter("db_instance_available").wait(
        DBInstanceIdentifier=f"{PREFIJO}-db", WaiterConfig={"Delay": 30, "MaxAttempts": 80}
    )
    db = rds.describe_db_instances(DBInstanceIdentifier=f"{PREFIJO}-db")["DBInstances"][0]
    print("RDS: available")

    print("\nSalidas:")
    print(f"  s3_bucket       = {bucket_name}")
    print(f"  ec2_instance_id = {instance_id}")
    print(f"  rds_endpoint    = {db['Endpoint']['Address']}")
    print(f"  rds_secret_arn  = {db['MasterUserSecret']['SecretArn']}")


def eliminar():
    print(f"Identidad: {sts.get_caller_identity()['Arn']}")

    # RDS (borra también el secreto administrado por RDS)
    try:
        rds.delete_db_instance(
            DBInstanceIdentifier=f"{PREFIJO}-db", SkipFinalSnapshot=True, DeleteAutomatedBackups=True
        )
        print(f"RDS: eliminando {PREFIJO}-db...")
    except rds.exceptions.DBInstanceNotFoundFault:
        print("RDS: no existe")

    # EC2
    instance_ids = find_instances()
    if instance_ids:
        ec2.terminate_instances(InstanceIds=instance_ids)
        print(f"EC2: terminando {', '.join(instance_ids)}...")
        ec2.get_waiter("instance_terminated").wait(InstanceIds=instance_ids)
        print("EC2: terminated")

    rds.get_waiter("db_instance_deleted").wait(
        DBInstanceIdentifier=f"{PREFIJO}-db", WaiterConfig={"Delay": 30, "MaxAttempts": 80}
    )
    print("RDS: eliminada")

    try:
        rds.delete_db_subnet_group(DBSubnetGroupName=f"{PREFIJO}-db-subnets")
        print("RDS: subnet group eliminado")
    except rds.exceptions.DBSubnetGroupNotFoundFault:
        pass

    # Primero el SG de RDS, porque referencia al de la EC2
    for name in (f"{PREFIJO}-rds-sg", f"{PREFIJO}-ec2-sg"):
        group_id = find_security_group(name)
        if group_id:
            ec2.delete_security_group(GroupId=group_id)
            print(f"Security group {name} eliminado")

    # S3: se vacía y se elimina
    try:
        s3_resource = session.resource("s3")
        s3_resource.Bucket(bucket_name).objects.all().delete()
        s3.delete_bucket(Bucket=bucket_name)
        print(f"S3: bucket {bucket_name} eliminado")
    except ClientError as error:
        if error.response["Error"]["Code"] != "NoSuchBucket":
            raise


if __name__ == "__main__":
    acciones = {"crear": crear, "eliminar": eliminar}
    if len(sys.argv) != 2 or sys.argv[1] not in acciones:
        raise SystemExit("Uso: python desplegar.py crear|eliminar")
    acciones[sys.argv[1]]()
