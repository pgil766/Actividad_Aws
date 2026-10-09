output "identidad" {
  value = data.aws_caller_identity.actual.arn
}

output "s3_bucket" {
  value = aws_s3_bucket.datos.bucket
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "rds_secret_arn" {
  description = "Secreto con la contraseña de RDS, administrado por RDS en Secrets Manager"
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}
