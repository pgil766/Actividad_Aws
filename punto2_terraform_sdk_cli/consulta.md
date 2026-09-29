# Punto 2 – Despliegue con Terraform, SDK y AWS CLI: consulta

> Precios de **US East (Ohio) – us-east-2**, tomados de la AWS Price List API el 2026-09-29 (EC2 y S3: tarifas públicas on-demand). Los montos son estimaciones; los reales se ven en Billing.

## 1. ¿Qué es Terraform?

Terraform (de HashiCorp) es una herramienta de **Infraestructura como Código (IaC)**. La infraestructura se describe en archivos `.tf` con el lenguaje **HCL**, de forma **declarativa**: se escribe *qué* se quiere tener (un bucket, una EC2, una base de datos) y Terraform calcula *cómo* llegar ahí.

Funciona con **proveedores** (plugins). El proveedor `hashicorp/aws` traduce los recursos a llamadas a la API de AWS.

### Cómo se usa para definir, planificar, crear y eliminar

| Paso | Comando | Qué hace |
|---|---|---|
| Definir | (editar `.tf`) | Declarar `provider`, `resource`, `variable`, `output` y `data` |
| Inicializar | `terraform init` | Descarga los proveedores y prepara el *backend* donde se guarda el estado |
| Validar/formatear | `terraform fmt` / `terraform validate` | Revisa la sintaxis y la coherencia |
| Planificar | `terraform plan` | Compara el código con el **estado** y con lo que existe en AWS, y muestra qué va a crear (+), cambiar (~) o destruir (-). No modifica nada |
| Crear/actualizar | `terraform apply` | Ejecuta el plan en el orden correcto según las dependencias entre recursos |
| Eliminar | `terraform destroy` | Borra todo lo que Terraform administra, en orden inverso de dependencias |

### El archivo de estado (`terraform.tfstate`)
Terraform guarda en un JSON el **mapa entre el código y los recursos reales**: IDs, ARNs, IPs, endpoints y **todos los atributos** de cada recurso. Por eso:
- **Puede contener datos sensibles.** Si se pasa `password = "..."` a `aws_db_instance`, o se usa `random_password`, ese valor queda **en texto plano** en el estado. Marcarlo como `sensitive` solo lo oculta en pantalla, no en el archivo.
- **Cómo evitarlo:** usar `manage_master_user_password = true` en RDS. Así RDS genera la contraseña y la guarda en Secrets Manager, y en el estado solo queda el **ARN del secreto** (`master_user_secret`), nunca la contraseña.
- El estado **no se sube al repositorio** (`.gitignore`: `*.tfstate*`, `.terraform/`). En equipos se guarda en un backend remoto cifrado (S3 con bloqueo).

## 2. ¿Cómo se autentica `user_cli` en las herramientas?

Las tres herramientas (AWS CLI, Boto3 y el proveedor AWS de Terraform) usan la misma **cadena de proveedores de credenciales** del SDK de AWS. Buscan en este orden:

1. Variables de entorno (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`)
2. Archivos compartidos `~/.aws/credentials` y `~/.aws/config` (perfil `default` o el indicado con `--profile`, `profile_name=` o `profile =`)
3. IAM Identity Center (SSO) o roles asumidos definidos en el perfil
4. Rol de la instancia o del contenedor, si el código corre dentro de AWS

En este taller, `user_cli` tiene una **Access Key** (ID + secreto) guardada en `~/.aws/credentials`, perfil `default`, con la región `us-east-2` en `~/.aws/config`. Con esas claves, cada petición a AWS se **firma con SigV4** y AWS verifica que la firma corresponde a `user_cli` y aplica sus políticas IAM.

Para verificarlo: `aws sts get-caller-identity` → `arn:aws:iam::<cuenta>:user/user_cli`. **Ningún** paso usa la cuenta raíz.

### ¿Por qué NO guardar las Access Keys en Secrets Manager?

Para leer un secreto hay que llamar a `GetSecretValue`, y esa llamada **ya tiene que estar autenticada** en AWS. Si las claves de `user_cli` estuvieran dentro de Secrets Manager, las herramientas necesitarían credenciales para obtener… sus propias credenciales. Es un problema circular: el "huevo y la gallina". Las credenciales de acceso a AWS son la **raíz de confianza** y se manejan con los mecanismos del SDK (perfiles, SSO, roles). Secrets Manager es para lo que la aplicación usa **después** de autenticarse, como las contraseñas de bases de datos.

## 3. Permisos que necesita `user_cli`

Lista mínima para crear y eliminar **S3 + EC2 + RDS + red**. Donde sea posible, se restringe por región (`aws:RequestedRegion = us-east-2`) y por prefijo de nombre.

| Servicio | Acciones | Para qué |
|---|---|---|
| **STS** | `sts:GetCallerIdentity` | Verificar la identidad (lo usa Terraform al iniciar) |
| **S3** | `s3:CreateBucket`, `s3:DeleteBucket`, `s3:ListBucket`, `s3:GetBucket*`, `s3:PutBucketTagging`, `s3:PutBucketPublicAccessBlock`, `s3:PutBucketOwnershipControls`, `s3:PutBucketVersioning`, `s3:PutEncryptionConfiguration`, `s3:GetEncryptionConfiguration`, `s3:GetLifecycleConfiguration`, `s3:GetReplicationConfiguration`, `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListAllMyBuckets` | Crear o borrar el bucket. Terraform **lee** muchas configuraciones del bucket al refrescar el estado (por eso los `Get*`) |
| **EC2 – instancias** | `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:DescribeInstances`, `ec2:DescribeInstanceTypes`, `ec2:DescribeInstanceAttribute`, `ec2:DescribeInstanceCreditSpecifications`, `ec2:DescribeImages`, `ec2:DescribeVolumes`, `ec2:DescribeTags`, `ec2:CreateTags`, `ec2:CreateKeyPair`/`ImportKeyPair`, `ec2:DeleteKeyPair`, `ec2:DescribeKeyPairs` | Lanzar, describir y terminar la EC2 |
| **EC2 – red (VPC)** | `ec2:CreateVpc`/`DeleteVpc`, `ec2:CreateSubnet`/`DeleteSubnet`, `ec2:CreateInternetGateway`/`AttachInternetGateway`/`DetachInternetGateway`/`DeleteInternetGateway`, `ec2:CreateRouteTable`/`CreateRoute`/`AssociateRouteTable`/`DisassociateRouteTable`/`DeleteRouteTable`, `ec2:ModifyVpcAttribute`, `ec2:ModifySubnetAttribute`, `ec2:CreateSecurityGroup`/`DeleteSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`/`Egress`, `ec2:RevokeSecurityGroupIngress`/`Egress`, `ec2:Describe*` (VPCs, Subnets, RouteTables, InternetGateways, SecurityGroups, NetworkInterfaces, AvailabilityZones, AccountAttributes) | Crear la red. Si se usa la **VPC por defecto**, basta con los `Describe*` y la gestión de security groups |
| **RDS** | `rds:CreateDBInstance`, `rds:DeleteDBInstance`, `rds:DescribeDBInstances`, `rds:ModifyDBInstance`, `rds:CreateDBSubnetGroup`/`DeleteDBSubnetGroup`/`DescribeDBSubnetGroups`, `rds:AddTagsToResource`, `rds:ListTagsForResource`, `rds:DescribeDBEngineVersions`, `rds:DescribeOrderableDBInstanceOptions` | Crear y borrar la instancia y su grupo de subredes |
| **Secrets Manager** (lo usa RDS) | `secretsmanager:CreateSecret`, `secretsmanager:TagResource`, `secretsmanager:DescribeSecret`, `secretsmanager:RotateSecret`, `secretsmanager:DeleteSecret` (con condición `secretsmanager:ResourceTag/aws:secretsmanager:owningService = rds`), `secretsmanager:GetSecretValue` (solo para comprobar la conexión) | Con `ManageMasterUserPassword`, RDS crea el secreto **en nombre del usuario que llama**, por eso el usuario necesita estos permisos |
| **KMS** | `kms:DescribeKey`, `kms:CreateGrant`, `kms:Decrypt`, `kms:GenerateDataKey` | Cifrado del secreto de RDS y del almacenamiento. Con las llaves administradas por AWS suele bastar `DescribeKey`/`CreateGrant` |
| **IAM** | `iam:CreateServiceLinkedRole` (condición `iam:AWSServiceName = rds.amazonaws.com`) | Solo la primera vez que se usa RDS en la cuenta |

> Se recomienda arrancar con esta lista y ajustarla con los errores `AccessDenied` que salgan (el mensaje indica la acción faltante). También sirve el *IAM Access Analyzer → Generate policy* a partir de CloudTrail. **No** usar `AdministratorAccess`.

## 4. Comparación de los tres métodos

| Criterio | Terraform | Boto3 (Python) | AWS CLI |
|---|---|---|---|
| Paradigma | **Declarativo**: describes el estado final | **Imperativo**: programas cada paso | **Imperativo**: un comando por paso |
| Estado | Guarda `tfstate`; sabe qué creó | No guarda nada; hay que guardar IDs a mano | No guarda nada |
| Dependencias y orden | Automáticas (grafo) | Manuales (esperar con *waiters*) | Manuales (`aws ... wait`) |
| Idempotencia | Sí: `apply` dos veces no duplica | Solo si se programa | No: repetir `create` falla o duplica |
| Ver cambios antes | `terraform plan` | No (salvo `DryRun` en EC2) | No (salvo `--dry-run` en EC2) |
| Eliminación | `terraform destroy` borra todo en orden | Hay que escribir el borrado | Hay que escribir cada comando de borrado |
| Lógica y flexibilidad | Limitada (HCL) | Total (Python) | Media (scripts de shell) |
| Curva de aprendizaje | Media | Media (requiere programar) | Baja para tareas puntuales |
| Mejor uso | Infraestructura reproducible y versionada | Automatizaciones dentro de aplicaciones o pipelines de datos | Tareas rápidas, pruebas, scripts cortos |

## 5. Preguntas de costos

Configuración de menor costo propuesta:
- **EC2** `t3.micro` o `t4g.micro` con 8 GB gp3 e IP pública
- **RDS** `db.t4g.micro` PostgreSQL/MySQL Single-AZ con 20 GB gp3, sin Multi-AZ y con retención de backups de 1 día
- **S3** vacío
- **Red:** VPC por defecto, **sin NAT Gateway**

| Componente | Tarifa us-east-2 | Por hora |
|---|---|---|
| EC2 t3.micro | USD 0.0104/h | 0.0104 |
| IPv4 pública de la EC2 | USD 0.005/h | 0.0050 |
| EBS 8 GB gp3 | USD 0.08/GB-mes | 0.0009 |
| RDS db.t4g.micro Single-AZ | USD 0.016/h | 0.0160 |
| RDS 20 GB gp3 | USD 0.115/GB-mes | 0.0032 |
| Secreto de RDS | USD 0.40/mes | 0.0005 |
| S3 (vacío o pocos KB) | USD 0.023/GB-mes | ≈ 0 |
| **Total** | | **≈ USD 0.036/h** |

### ¿Cuánto costaría mantener los recursos durante una hora y durante una semana?
- **1 hora:** ≈ **USD 0.04**
- **1 semana (168 h):** ≈ 0.036 × 168 ≈ **USD 6.10**
- Como referencia, **30 días** ≈ USD 26.

Si la cuenta tiene capa gratuita o créditos de plan gratuito, gran parte puede quedar cubierta, pero la estimación se reporta sin descuentos.

### ¿Qué componentes seguirían generando cargos sin recibir tráfico?
Casi todo se cobra **por tiempo encendido o por espacio reservado**, no por uso:
- **RDS:** la instancia cobra por hora aunque nadie se conecte. El almacenamiento aprovisionado también. Una instancia *detenida* deja de cobrar cómputo pero sigue cobrando almacenamiento, y AWS la vuelve a encender sola a los 7 días.
- **EC2:** cobra por hora mientras esté en `running`. Detenida, sigue cobrando el **volumen EBS**.
- **IPv4 pública / Elastic IP:** cobra por hora esté asociada o no.
- **Snapshots y backups:** el snapshot final de RDS o los snapshots de EBS siguen cobrando después de borrar la instancia.
- **Secreto de RDS:** USD 0.40/mes mientras exista (se borra junto con la instancia cuando es administrado por RDS).
- **S3:** por GB almacenado; vacío es ≈ 0.
- (Si se creara) **NAT Gateway:** ≈ USD 0.045/h aunque no pase tráfico. Por eso no se usa.

### ¿Qué costo añade el secreto de RDS?
**USD 0.40 al mes**, prorrateado (≈ USD 0.00055/h, unos 9 centavos por semana), más USD 0.05 por cada 10 000 llamadas a la API. RDS lo rota por defecto cada 7 días; la rotación administrada no tiene costo extra de Lambda. Para este punto el costo es prácticamente **USD 0.00**, y el secreto se elimina automáticamente al borrar la instancia.

## Fuentes
- [Terraform – What is Terraform?](https://developer.hashicorp.com/terraform/intro)
- [Terraform – Sensitive data in state](https://developer.hashicorp.com/terraform/language/state/sensitive-data)
- [Terraform AWS provider – aws_db_instance (`manage_master_user_password`)](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance)
- [Password management with Amazon RDS and AWS Secrets Manager](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [AWS SDKs and Tools – Credential provider chain](https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html)
- [Amazon EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/) · [Amazon VPC Pricing (IPv4)](https://aws.amazon.com/vpc/pricing/) · [Amazon RDS Pricing](https://aws.amazon.com/rds/pricing/)
- AWS Price List API, `AmazonRDS` y `AWSSecretsManager`, región us-east-2 (consultada el 2026-09-29)
