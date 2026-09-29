# Checklist – Actividad AWS (Ingeniería de Datos 2026-2)

Marca cada tarea cambiando `[ ]` por `[x]`. En GitHub también se pueden marcar con clic si editas el archivo.

**Reglas que aplican a TODO el taller**
- Una sola región para todo: **us-east-2 (Ohio)**, la configurada en el perfil de `user_cli`.
- Todas las contraseñas de bases de datos van en **Secrets Manager**. Nunca escritas en el código.
- Antes de desplegar algo, anota cuánto cuesta por hora. Al terminar, **borra todo** y toma una captura como evidencia.
- En capturas y en el repo **nunca** deben aparecer valores de secretos, Access Keys, llaves `.pem` ni archivos `terraform.tfstate`.
- Cada punto va en su carpeta con su propio `README.md` (qué se hizo, cómo reproducirlo, respuestas y costos).

---

## Punto 0 – Preparación (una sola vez)

### Herramientas en tu PC
- [ ] Instalar AWS CLI v2 (`aws --version`)
- [ ] Instalar Terraform (`terraform -version`)
- [ ] Verificar Python (`py --version`) y crear un entorno virtual: `py -m venv .venv`
- [ ] Instalar librerías: `boto3`, `pymongo`, `gremlinpython` y/o `requests` (para Neptune)
- [ ] Instalar MongoDB Compass

### Cuenta AWS
- [ ] Activar MFA en la cuenta raíz y **no volver a usarla** para el taller
- [ ] Crear una alerta de presupuesto en AWS Budgets (por ejemplo USD 10) con aviso a tu correo
- [x] Crear el usuario IAM `user_cli` y configurar sus credenciales en el perfil `default` (verificado: `user/user_cli`, región us-east-2)

### Repositorio
- [ ] Clonar o vincular https://github.com/pgil766/Actividad_Aws.git
- [ ] Crear un `.gitignore` con: `*.tfstate*`, `.terraform/`, `*.pem`, `.env`, `.venv/`, `__pycache__/`
- [ ] Crear la estructura de carpetas:
  ```
  punto1_secrets_manager/
  punto2_terraform_sdk_cli/{terraform,boto3,cli,iam}
  punto3_documentdb/
  punto4_neptune/
  punto5_redshift/
  punto6_glue/
  (cada una con evidencias/ y README.md)
  ```
- [ ] Hacer el repo público o agregar como colaborador a **smm-0216**
- [ ] Crear el `README.md` raíz con un índice de los 6 puntos

---

## Punto 1 – AWS Secrets Manager

### Investigación (va en el README)
- [ ] Qué es Secrets Manager y qué tipo de información guarda
- [ ] Cómo se controla quién lee un secreto (políticas IAM, política de recurso, KMS)
- [ ] Diferencia entre **crear**, **recuperar desde una aplicación** y **rotar** un secreto

### Práctica
- [ ] Crear un secreto de prueba (por ejemplo `taller/punto1/demo`) con `{"username": "...", "password": "..."}` ficticios
- [ ] Crear una política IAM que permita `secretsmanager:GetSecretValue` **solo** sobre el ARN de ese secreto
- [ ] Escribir `leer_secreto.py` con Boto3 para recuperarlo
- [ ] Ejecutarlo y ver el valor v1
- [ ] Cambiar el valor del secreto (consola o `put-secret-value`)
- [ ] Ejecutar de nuevo, **sin tocar el código**, y ver el valor v2
- [ ] Eliminar el secreto (`delete-secret`, con o sin ventana de recuperación)

### Preguntas de costos
- [ ] ¿Cómo se cobran los secretos almacenados y las llamadas a la API?
- [ ] ¿Qué pasa con el costo si el programa consulta el mismo secreto muchas veces?
- [ ] ¿Cuándo conviene guardar el valor temporalmente en memoria (caché)?

### Evidencias a entregar
- [ ] Código `leer_secreto.py`
- [ ] JSON de la política de acceso
- [ ] Captura o salida de la ejecución antes y después del cambio (valores ficticios; aun así puedes enmascararlos)
- [ ] Explicación de por qué el programa obtiene la versión nueva (`AWSCURRENT`)
- [ ] Estimación de costos
- [ ] Captura de la eliminación del secreto

---

## Punto 2 – Terraform, Boto3 y AWS CLI (Terraform es obligatorio aquí)

### Investigación
- [ ] Qué es Terraform y el flujo `init` → `plan` → `apply` → `destroy`
- [ ] Cómo se autentica `user_cli` en las tres herramientas (Access Keys en `~/.aws/credentials` / perfil, cadena de credenciales)
- [ ] Por qué **no** se guardan las Access Keys en Secrets Manager: para leer un secreto primero hay que estar autenticado
- [ ] Qué guarda `terraform.tfstate` y cómo evitar que tenga contraseñas (`manage_master_user_password = true` en RDS)

### IAM
- [ ] Crear `user_cli` con permisos mínimos para S3, EC2, RDS, red (VPC, subnets, SG), Secrets Manager (lo que usa RDS) y KMS si aplica
- [ ] Documentar cada permiso y para qué sirve
- [ ] Verificar que todo se hace con `user_cli` (`aws sts get-caller-identity --profile user_cli`)

### Versión A – Terraform
- [ ] Escribir los `.tf`: S3 bucket, EC2 (t3.micro/t2.micro) y RDS (db.t3.micro/db.t4g.micro, 20 GB, sin Multi-AZ) + red/SG
- [ ] Configurar RDS con `manage_master_user_password = true`
- [ ] `terraform plan` → `terraform apply`
- [ ] Captura de los recursos creados y del secreto que creó RDS
- [ ] `terraform destroy` + captura

### Versión B – Boto3
- [ ] Script Python que crea los mismos tres recursos (RDS con `ManageMasterUserPassword=True`)
- [ ] Script o función para eliminarlos
- [ ] Capturas de la creación y la eliminación

### Versión C – AWS CLI
- [ ] Archivo `comandos.sh` / `.ps1` con los comandos de creación (`--manage-master-user-password`)
- [ ] Comandos de eliminación
- [ ] Capturas de la creación y la eliminación

### Comparación
- [ ] Tabla comparando Terraform, Boto3 y CLI (declarativo vs imperativo, estado, repetibilidad, borrado, facilidad)

### Preguntas de costos
- [ ] Costo de mantener los recursos 1 hora y 1 semana
- [ ] ¿Qué sigue cobrando sin tráfico? (RDS, EBS, IP pública, almacenamiento, snapshots)
- [ ] ¿Cuánto añade el secreto de RDS?

### Evidencias a entregar
- [ ] Política IAM (JSON)
- [ ] Archivos de Terraform (**sin** tfstate)
- [ ] Programa Python
- [ ] Comandos CLI
- [ ] Respuestas a las preguntas
- [ ] Estimación de costos
- [ ] Capturas de creación y eliminación de **las tres versiones**

---

## Punto 3 – Amazon DocumentDB

### Investigación
- [ ] Al menos 3 diferencias entre DocumentDB y MongoDB que afecten una app existente
- [ ] Comparar el precio de una instancia aprovisionada con Serverless (mínimo 0,5 DCU) y justificar la opción más barata

### Despliegue
- [ ] Crear el clúster DocumentDB con la configuración más barata y la contraseña administrada en Secrets Manager
- [ ] Crear una EC2 pequeña en la **misma VPC** (bastión) con su key pair
- [ ] Configurar los Security Groups: tu IP → EC2:22 y SG de la EC2 → DocumentDB:27017
- [ ] Descargar el certificado `global-bundle.pem` (TLS)
- [ ] Abrir el túnel SSH: `ssh -i llave.pem -L 27017:<endpoint-docdb>:27017 ec2-user@<ip-ec2> -N`
- [ ] Conectar con MongoDB Compass a través del túnel (TLS + CA + `tlsAllowInvalidHostnames`, `directConnection`)
- [ ] Conectar desde Python (pymongo) leyendo la contraseña desde Secrets Manager

### Práctica con Python
- [ ] Crear una base de datos y una colección
- [ ] Insertar al menos **10 documentos**
- [ ] Búsqueda con filtro
- [ ] Ordenación
- [ ] Agregación

### Limpieza
- [ ] Borrar el clúster (sin snapshot final), la EC2, la key pair y los SG + capturas

### Preguntas de costos
- [ ] ¿Qué opción de DocumentDB cuesta menos para esta práctica?
- [ ] ¿Cuánto agrega la EC2 del túnel?

### Evidencias a entregar
- [ ] Respuestas y cálculo de costos
- [ ] **Diagrama de conexión** (PC → SSH → EC2 → DocumentDB, con puertos, SG y TLS)
- [ ] Código Python y consultas
- [ ] Resultados (salidas y captura de Compass conectado)
- [ ] Capturas de la eliminación

---

## Punto 4 – Amazon Neptune

### Investigación
- [ ] Comparar Neptune y Neo4j: modelo de datos (property graph / RDF), lenguajes (Gremlin, openCypher, SPARQL vs Cypher) y herramientas
- [ ] Justificar aprovisionado vs Serverless
- [ ] Comparar el túnel SSH por EC2 con el endpoint público de Neptune (si tu versión lo permite)
- [ ] Responder: ¿es necesaria la EC2? ¿Hay otra forma? (endpoint público con IAM, VPN, Neptune Notebook/Workbench, Lambda, etc.)

### Despliegue
- [ ] Crear el clúster Neptune con la configuración más barata
- [ ] Configurar el acceso elegido (EC2 + túnel al puerto 8182, o endpoint público)
- [ ] Documentar VPC, subnets, tablas de rutas, SG y autenticación (IAM o ninguna)

### Práctica con Python
- [ ] Diseñar un grafo con al menos **10 vértices** y **15 aristas** (hacer el dibujo del modelo)
- [ ] Insertar los datos
- [ ] 3 consultas que **recorran relaciones** (por ejemplo amigos de amigos o caminos)

### Limpieza
- [ ] Borrar el clúster, las instancias, la EC2 si se usó y los SG + capturas

### Preguntas de costos
- [ ] ¿Cuánto cuestan el cómputo y el almacenamiento?
- [ ] ¿Tu método de conexión agrega una EC2?
- [ ] ¿Qué se sigue cobrando mientras no ejecutas consultas?

### Evidencias a entregar
- [ ] Respuestas a las preguntas
- [ ] Modelo del grafo (diagrama)
- [ ] Diagrama de la arquitectura de acceso
- [ ] Costos
- [ ] Código, consultas y resultados
- [ ] Capturas de la eliminación

---

## Punto 5 – Amazon Redshift

### Investigación
- [ ] Qué es Redshift, para qué análisis se usa y sus componentes (líder/cómputo o workgroup/namespace, RMS, COPY, etc.)
- [ ] Comparar con RDS (OLAP vs OLTP) y dar un caso de uso para cada uno
- [ ] Serverless vs aprovisionado: justificar la elección (revisar si tu cuenta tiene créditos de prueba de Serverless)

### Despliegue
- [ ] Crear Redshift (Serverless: namespace + workgroup con la base RPU mínima) y la contraseña de admin **administrada en Secrets Manager**
- [ ] Crear un rol IAM que permita a Redshift leer de S3 y asociarlo

### Datos y programa Python (Boto3)
- [ ] Preparar un dataset con al menos **2 tablas relacionadas** (CSV)
- [ ] El programa sube los CSV a S3
- [ ] Crea las tablas (`CREATE TABLE`)
- [ ] Carga los datos con `COPY`
- [ ] Ejecuta consultas con **filtro**, **JOIN** y **agregación**
- [ ] Usa la **Redshift Data API** (`execute_statement` → `describe_statement` → `get_statement_result`) con `SecretArn`
- [ ] (Opcional) Revisar en Query Editor v2

### Análisis
- [ ] Explicar qué pregunta responde cada consulta e interpretar los resultados
- [ ] (Opcional) Si te conectas con un cliente SQL, documentar la red y el SG

### Limpieza
- [ ] Borrar el workgroup y el namespace (o el clúster), los snapshots, el bucket S3 y el rol + capturas

### Preguntas de costos
- [ ] ¿Qué modalidad cuesta menos?
- [ ] ¿Cómo se cobran el cómputo y el almacenamiento?
- [ ] ¿Qué puede seguir cobrando después de las consultas?

### Evidencias a entregar
- [ ] Respuestas a las preguntas
- [ ] Dataset (CSV)
- [ ] Instrucciones de carga (`COPY`)
- [ ] Consultas SQL
- [ ] Resultados interpretados
- [ ] Comparación con RDS
- [ ] Estimación de costos
- [ ] Capturas de la eliminación

---

## Punto 6 – AWS Glue Data Catalog

### Investigación
- [ ] Qué almacena el Data Catalog: datos en S3 vs **metadatos** en el catálogo
- [ ] Qué hacen las bases de datos, las tablas y los *crawlers*

### Práctica
- [ ] Crear un CSV o JSON con al menos **20 registros** y subirlo a S3 (en una carpeta propia, no en la raíz del bucket)
- [ ] Crear una base de datos en Glue
- [ ] Crear el rol IAM del crawler y el crawler, y ejecutarlo
- [ ] Revisar el esquema inferido y **corregir los errores** (tipos, encabezados, etc.)
- [ ] Configurar la carpeta de resultados de Athena en S3
- [ ] Consulta en Athena con **filtro**
- [ ] Consulta en Athena con **GROUP BY**
- [ ] Agregar registros (nuevo archivo), volver a correr el crawler y verificar los resultados
- [ ] Crear la misma tabla de forma **manual** (DDL en Athena o consola) y compararla con el crawler

### Credenciales
- [ ] Explicar por qué no hace falta un secreto nuevo si solo usas S3, Glue y Athena con IAM (o guardarlo en Secrets Manager si usas una conexión JDBC)

### Limpieza
- [ ] Borrar el crawler, las tablas, la base de datos, los objetos y el bucket S3 (incluidos los resultados de Athena) y el rol + capturas

### Preguntas de costos
- [ ] ¿Qué se cobra por el crawler (DPU-hora), el catálogo, S3 y Athena (por TB escaneado)?
- [ ] ¿Qué efecto tiene el volumen de datos examinados?

### Evidencias a entregar
- [ ] Respuestas a las preguntas
- [ ] Datos
- [ ] Configuración (crawler, rol)
- [ ] Esquema (antes y después de corregirlo)
- [ ] Consultas y resultados
- [ ] Costos
- [ ] Capturas de la eliminación

---

## Cierre y entrega
- [ ] Revisar en **Billing / Cost Explorer** y en **Tag Editor / Resource Groups** que no queden recursos facturables (EBS, snapshots, IP elásticas, NAT, secretos, buckets)
- [ ] Revisar que el repo no tenga secretos: buscar `AKIA`, `password`, `.pem`, `tfstate`
- [ ] README raíz completo con enlaces a cada punto
- [ ] Repo público o compartido con **smm-0216**
- [ ] Enviar el enlace al profe
