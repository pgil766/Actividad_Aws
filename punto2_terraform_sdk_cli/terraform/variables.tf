variable "region" {
  description = "Región única del taller"
  type        = string
  default     = "us-east-2"
}

variable "prefijo" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "p2-terraform"
}

variable "ec2_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_username" {
  description = "Usuario administrador de RDS. La contraseña la genera RDS y la guarda en Secrets Manager."
  type        = string
  default     = "dbadmin"
}
