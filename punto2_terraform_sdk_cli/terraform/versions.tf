terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Las credenciales NO van aquí: el proveedor usa la cadena estándar del SDK
# (~/.aws/credentials, perfil de user_cli).
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Proyecto = "actividad-aws"
      Punto    = "2"
      Metodo   = "terraform"
    }
  }
}
