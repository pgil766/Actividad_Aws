# Actividad AWS – Ingeniería de Datos 2026-2

Taller práctico de servicios de datos de AWS: Secrets Manager, infraestructura como código, DocumentDB, Neptune, Redshift y Glue Data Catalog.

- **Región única:** `us-east-2` (Ohio).
- **Identidad de trabajo:** usuario IAM `user_cli`. No se usó la cuenta raíz para crear recursos. Las políticas IAM las creó un administrador, y su JSON está en la carpeta `iam/` de cada punto.
- **Sin contraseñas en el código.** Todas las credenciales de bases de datos viven en **AWS Secrets Manager**, administradas por el propio servicio cuando lo permite (RDS, DocumentDB, Redshift), y los programas las leen en tiempo de ejecución. El archivo `.env` solo guarda nombres de recursos.
- **Todos los recursos se eliminaron** al terminar cada punto. El inventario final está en [verificacion_cuenta_limpia.txt](verificacion_cuenta_limpia.txt).

## Contenido

| Punto | Servicio | Investigación y costos | Código | Evidencias |
|---|---|---|---|---|
| 1 | AWS Secrets Manager | [consulta](punto1_secrets_manager/consulta.md) | [leer_secreto.py](punto1_secrets_manager/leer_secreto.py) · [política](punto1_secrets_manager/politica_acceso.json) | [evidencias](punto1_secrets_manager/evidencias) |
| 2 | Terraform, Boto3 y AWS CLI (S3 + EC2 + RDS) | [consulta](punto2_terraform_sdk_cli/consulta.md) | [terraform/](punto2_terraform_sdk_cli/terraform) · [boto3/](punto2_terraform_sdk_cli/boto3) · [cli/](punto2_terraform_sdk_cli/cli) · [iam/](punto2_terraform_sdk_cli/iam) | [evidencias](punto2_terraform_sdk_cli/evidencias) |
| 3 | Amazon DocumentDB (túnel SSH + Compass + Python) | [consulta](punto3_documentdb/consulta.md) · [diagrama de conexión](punto3_documentdb/diagrama_conexion.md) | [tunel.sh](punto3_documentdb/tunel.sh) · [docdb_operaciones.py](punto3_documentdb/docdb_operaciones.py) | [evidencias](punto3_documentdb/evidencias) |
| 4 | Amazon Neptune (endpoint público + IAM) | [consulta](punto4_neptune/consulta.md) · [modelo y arquitectura](punto4_neptune/modelo_y_arquitectura.md) | [crear.sh](punto4_neptune/crear.sh) · [neptune_grafo.py](punto4_neptune/neptune_grafo.py) | [evidencias](punto4_neptune/evidencias) |
| 5 | Amazon Redshift Serverless (COPY + Data API) | [consulta](punto5_redshift/consulta.md) | [crear.sh](punto5_redshift/crear.sh) · [redshift_pipeline.py](punto5_redshift/redshift_pipeline.py) · [datos/](punto5_redshift/datos) | [evidencias](punto5_redshift/evidencias) |
| 6 | AWS Glue Data Catalog + Athena | [consulta](punto6_glue/consulta.md) | [crear.sh](punto6_glue/crear.sh) · [glue_athena.py](punto6_glue/glue_athena.py) · [datos/](punto6_glue/datos) | [evidencias](punto6_glue/evidencias) |

Cada `consulta.md` contiene la investigación teórica, las respuestas a las preguntas de costos, lo que se hizo en la práctica y el costo real.

## Preparar el entorno

Probado en WSL (Ubuntu 24.04) con:
- Python 3.12 (entorno Conda `aws`);
- AWS CLI v2;
- Terraform 1.16;
- MongoDB Compass, solo para el punto 3.

```bash
git clone https://github.com/pgil766/Actividad_Aws.git
cd Actividad_Aws

conda create -n aws python=3.12 -y && conda activate aws
pip install -r requirements.txt

aws configure                 # Access Key de user_cli, región us-east-2 (nunca la cuenta raíz)
aws sts get-caller-identity   # debe mostrar arn:aws:iam::<cuenta>:user/user_cli

cp .env.example .env          # solo nombres de recursos; no contiene contraseñas
```

Los comandos de cada punto se ejecutan **desde la raíz del repositorio**.

## Cómo reproducir cada punto

### 1. AWS Secrets Manager
1. **Crear el secreto (consola):** en Secrets Manager, crear el secreto `taller/punto1/demo` con `{"username": "...", "password": "..."}` ficticios.
2. **Dar acceso (consola, admin):** asociar a `user_cli` la política [politica_acceso.json](punto1_secrets_manager/politica_acceso.json), que permite solo `GetSecretValue` sobre ese ARN.
3. **Leer el secreto:**
   ```bash
   python punto1_secrets_manager/leer_secreto.py                 # lee la versión AWSCURRENT
   python punto1_secrets_manager/leer_secreto.py otro/secreto    # debe dar AccessDenied
   ```
4. **Cambiar el valor (consola)** y volver a ejecutar sin tocar el código: aparece el nuevo `VersionId`.
5. **Eliminar el secreto.**

### 2. Terraform, Boto3 y AWS CLI
Las tres versiones despliegan los mismos recursos:
- un bucket S3;
- una EC2 `t3.micro` sin IP pública;
- una RDS PostgreSQL `db.t4g.micro` privada, con **contraseña administrada en Secrets Manager**;
- dos security groups y un DB subnet group.

Se ejecutan **una después de otra**, eliminando cada una antes de la siguiente. `user_cli` necesita, además de sus políticas FullAccess, [politica_complemento_user_cli.json](punto2_terraform_sdk_cli/iam/politica_complemento_user_cli.json).

```bash
# Versión A: Terraform
cd punto2_terraform_sdk_cli/terraform
terraform init && terraform plan -out=tfplan && terraform apply tfplan
bash ../cli/verificar.sh terraform
terraform destroy
cd ../../

# Versión B: Boto3
python punto2_terraform_sdk_cli/boto3/desplegar.py crear
bash punto2_terraform_sdk_cli/cli/verificar.sh boto3
python punto2_terraform_sdk_cli/boto3/desplegar.py eliminar

# Versión C: AWS CLI
bash punto2_terraform_sdk_cli/cli/crear.sh
bash punto2_terraform_sdk_cli/cli/verificar.sh cli
bash punto2_terraform_sdk_cli/cli/eliminar.sh

bash punto2_terraform_sdk_cli/cli/verificar_eliminacion.sh <terraform|boto3|cli>
```

El estado de Terraform (`terraform.tfstate`) no se sube al repositorio y no contiene contraseñas: solo el ARN del secreto.

### 3. Amazon DocumentDB
1. **Permiso (consola, admin):** asociar a `user_cli` [politica_leer_secreto_docdb.json](punto3_documentdb/iam/politica_leer_secreto_docdb.json).
2. **Red y recursos (consola, como `user_cli`):**
   - SG `p3-bastion-sg`: entrada 22 desde tu IP;
   - SG `p3-docdb-sg`: entrada 27017 desde `p3-bastion-sg`;
   - EC2 `p3-bastion` (`t3.micro`, IP pública, par de claves propio) en la VPC por defecto;
   - clúster DocumentDB `p3-docdb`: 1 instancia `db.t3.medium`, motor 5.0.0, contraseña administrada en Secrets Manager, SG `p3-docdb-sg`.
3. **Túnel, consultas y limpieza:**
   ```bash
   LLAVE_SSH=~/mi-llave.pem bash punto3_documentdb/tunel.sh   # deja el túnel abierto (otra terminal)
   python punto3_documentdb/docdb_operaciones.py              # inserta 10 documentos; filtro, orden y agregación
   bash punto3_documentdb/eliminar.sh                          # cerrar antes el túnel
   ```
   `tunel.sh` también descarga `global-bundle.pem`.
4. **Compass:** conectarse a `localhost:27017` con TLS, el CA `global-bundle.pem`, `tlsAllowInvalidHostnames`, `directConnection` y `retryWrites=false`. Detalles en [diagrama_conexion.md](punto3_documentdb/diagrama_conexion.md).

### 4. Amazon Neptune
1. **Permiso (consola, admin):** asociar a `user_cli` [politica_datos_neptune.json](punto4_neptune/iam/politica_datos_neptune.json), que da acceso `neptune-db:*` con IAM.
2. **SG (consola):** `p4-neptune-sg`, con entrada TCP 8182 solo desde tu IP.
3. **Crear, consultar y eliminar:**
   ```bash
   bash punto4_neptune/crear.sh            # db.t4g.medium, motor 1.4.8.1, acceso público + autenticación IAM
   python punto4_neptune/neptune_grafo.py  # 12 vértices, 19 aristas y 3 consultas openCypher que recorren relaciones
   bash punto4_neptune/eliminar.sh
   ```

### 5. Amazon Redshift Serverless
1. **Permisos (consola, admin):**
   - política administrada [politica_user_cli_redshift.json](punto5_redshift/iam/politica_user_cli_redshift.json) para `user_cli`;
   - rol `p5-redshift-s3-role`, con [confianza](punto5_redshift/iam/rol_redshift_confianza.json) y [lectura de S3](punto5_redshift/iam/rol_redshift_permisos_s3.json).
2. **Crear, cargar, consultar y eliminar:**
   ```bash
   bash punto5_redshift/crear.sh                # bucket + namespace (admin en Secrets Manager) + workgroup de 4 RPU
   python punto5_redshift/redshift_pipeline.py  # S3 -> CREATE TABLE -> COPY -> filtro, JOIN y agregación por la Data API
   bash punto5_redshift/eliminar.sh
   ```

### 6. AWS Glue Data Catalog + Athena
1. **Permisos (consola, admin):**
   - política administrada [politica_user_cli_glue_athena.json](punto6_glue/iam/politica_user_cli_glue_athena.json) para `user_cli`;
   - rol `p6-glue-crawler-role` con `AWSGlueServiceRole` y [lectura del bucket](punto6_glue/iam/rol_crawler_permisos_s3.json).
2. **Crear, consultar y eliminar:**
   ```bash
   bash punto6_glue/crear.sh                     # sube 24 registros, crea la base p6_ventas y el crawler, y lo ejecuta
   python punto6_glue/glue_athena.py corregir    # fecha: string -> date; codigo_tienda: bigint -> string
   python punto6_glue/glue_athena.py consultas   # filtro y GROUP BY en Athena
   python punto6_glue/glue_athena.py agregar     # +10 registros
   bash punto6_glue/ejecutar_crawler.sh          # actualiza el catálogo (conserva el esquema corregido)
   python punto6_glue/glue_athena.py consultas   # el conteo pasa de 24 a 34
   python punto6_glue/glue_athena.py manual      # misma tabla con DDL y comparación con la del crawler
   bash punto6_glue/eliminar.sh
   ```

Este punto no requiere secretos: S3, Glue y Athena se autorizan solo con IAM. La justificación está en la [consulta](punto6_glue/consulta.md).

## Resumen de costos reales

| Punto | Costo aproximado | Nota |
|---|---|---|
| 1 | < USD 0.01 | Secreto de prueba con 30 días gratis |
| 2 | ≈ USD 0.07 | 3 despliegues de unos 30–45 min cada uno |
| 3 | ≈ USD 0.03 | Solo el bastión; DocumentDB `db.t3.medium` dentro de la prueba gratuita |
| 4 | ≈ USD 0 | Neptune `db.t4g.medium` dentro de la prueba gratuita; sin EC2 gracias al endpoint público |
| 5 | USD 0 | Cubierto por el crédito de prueba de Redshift Serverless (≈ USD 0.20 de referencia) |
| 6 | ≈ USD 0.15 | 2 ejecuciones del crawler (mínimo de 10 min cada una); Athena ≈ 0 |
| **Total** | **≈ USD 0.25** | |

## Verificación final
```bash
bash verificar_cuenta_limpia.sh
```
Revisa que no queden EC2, EBS, IP elásticas, NAT, bases de datos, snapshots, Redshift, crawlers ni buckets del taller. El resultado está en [verificacion_cuenta_limpia.txt](verificacion_cuenta_limpia.txt).
