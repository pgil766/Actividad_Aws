data "aws_caller_identity" "actual" {}

# Red: se usa la VPC por defecto de la región (sin NAT Gateway ni componentes que cobren por hora).
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# ---------- S3 ----------
resource "aws_s3_bucket" "datos" {
  bucket        = "actividad-aws-p2-${data.aws_caller_identity.actual.account_id}-terraform"
  force_destroy = true
}

# ---------- Security groups ----------
resource "aws_security_group" "ec2" {
  name        = "${var.prefijo}-ec2-sg"
  description = "EC2 del punto 2: sin entradas, solo salida"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.prefijo}-rds-sg"
  description = "RDS del punto 2: PostgreSQL solo desde la EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL desde el SG de la EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
}

# ---------- EC2 ----------
resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = false # evita el cobro por IPv4 pública

  tags = {
    Name = "${var.prefijo}-ec2"
  }
}

# ---------- RDS ----------
resource "aws_db_subnet_group" "rds" {
  name       = "${var.prefijo}-db-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.prefijo}-db"
  engine         = "postgres"
  instance_class = var.db_instance_class
  db_name        = "actividad"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  username = var.db_username
  # RDS genera la contraseña y la guarda en Secrets Manager:
  # en el tfstate solo queda el ARN del secreto, nunca la contraseña.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}
