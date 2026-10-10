# Punto 5 – Amazon Redshift: consulta

> Precios de **US East (Ohio) – us-east-2**, tomados de la AWS Price List API el 2026-09-29.

## 1. ¿Qué es Amazon Redshift?

Es el **data warehouse** administrado de AWS: una base de datos **columnar** y de **procesamiento masivamente paralelo (MPP)**, diseñada para consultas analíticas (**OLAP**) sobre grandes volúmenes de datos, de gigabytes a petabytes. Usa SQL compatible con PostgreSQL.

### ¿Para qué tipo de análisis se utiliza?
- Consultas con **agregaciones pesadas** (`SUM`, `COUNT`, `GROUP BY`) y **JOINs** entre tablas de hechos y dimensiones
- Reportes y dashboards de **BI** (QuickSight, Power BI, Tableau)
- Análisis histórico y de tendencias (ventas por mes, cohortes, KPIs)
- Consultar datos del *data lake* en S3 sin cargarlos (**Redshift Spectrum**)
- Procesos ELT: cargar datos crudos con `COPY` y transformarlos con SQL

### Componentes principales

| Componente | Descripción |
|---|---|
| **Clúster** (aprovisionado) | Conjunto de nodos: un **nodo líder**, que recibe las consultas, arma el plan y agrega resultados, y **nodos de cómputo**, que ejecutan en paralelo sobre sus *slices* |
| **Namespace + Workgroup** (Serverless) | El *namespace* agrupa los objetos de base de datos (esquemas, tablas, usuarios, credenciales de admin). El *workgroup* agrupa el cómputo (capacidad base en **RPU**, red, SG) |
| **RPU** (Redshift Processing Unit) | Unidad de capacidad de Serverless; se paga por RPU-hora usada |
| **Redshift Managed Storage (RMS)** | Almacenamiento administrado sobre S3, separado del cómputo (nodos RA3 y Serverless) |
| **Almacenamiento columnar, compresión, distribution keys y sort keys** | Técnicas que reducen la E/S y aceleran los JOINs y filtros |
| **`COPY` / `UNLOAD`** | Carga masiva y paralela desde S3 (CSV, JSON, Parquet…) y exportación a S3 |
| **Redshift Data API** | API HTTP (`execute_statement`, `describe_statement`, `get_statement_result`) para ejecutar SQL sin drivers ni conexiones persistentes, autenticando con Secrets Manager o IAM |
| **Query Editor v2** | Editor SQL web en la consola |
| **Rol de IAM asociado** | Permite a Redshift leer y escribir en S3 (para `COPY`) en nombre del clúster |
| **Spectrum, concurrency scaling, snapshots** | Consultar S3 directamente, escalar la concurrencia y hacer backups |

## 2. Redshift vs RDS

| | Amazon Redshift | Amazon RDS |
|---|---|---|
| Propósito | **Analítica (OLAP)**: pocas consultas muy grandes sobre muchos datos | **Transaccional (OLTP)**: muchas operaciones pequeñas (insertar, actualizar, leer por clave) |
| Almacenamiento | **Columnar**: lee solo las columnas que usa la consulta; compresión alta | **Por filas**: lee o escribe filas completas rápido |
| Escala | Paralelismo en muchos nodos; de TB a PB | Una instancia (más réplicas de lectura); hasta decenas de TB |
| Carga típica | Masiva y por lotes (`COPY`) | Fila a fila desde la aplicación |
| Motores | Redshift (SQL tipo PostgreSQL) | PostgreSQL, MySQL, MariaDB, Oracle, SQL Server, Db2 |
| Claves e integridad | PK/FK solo informativas (no se validan) | Restricciones aplicadas, transacciones ACID de alto volumen |

**Caso para elegir cada uno:**
- **RDS:** el backend de una tienda en línea que registra pedidos, pagos e inventario en tiempo real. Muchas transacciones pequeñas y concurrentes que requieren consistencia.
- **Redshift:** analizar 3 años de historial de esos pedidos (cientos de millones de filas) para obtener ventas por región, categoría y mes, y alimentar un dashboard de gerencia.

## 3. Serverless vs aprovisionado

| | Serverless | Aprovisionado |
|---|---|---|
| Cómputo | **USD 0.36 por RPU-hora**, cobrado **por segundo solo mientras hay consultas** (mínimo 60 s por cobro) | Por nodo-hora, **encendido todo el tiempo**: `ra3.large` USD 0.543/h, `ra3.xlplus` USD 1.086/h; `dc2.large` USD 0.25/h (generación anterior, puede no estar disponible para clústeres nuevos) |
| Capacidad base mínima | **4 RPU** (de 4 a 1024) | 1 nodo |
| Costo de 1 hora de consultas continuas a la capacidad mínima | 4 × 0.36 = **USD 1.44/h** | USD 0.543/h (ra3.large) |
| Costo en reposo | **USD 0 de cómputo** | Sigue cobrando cada hora (se puede pausar) |
| Almacenamiento | RMS: USD 0.024/GB-mes | RMS: USD 0.024/GB-mes (RA3) |
| Prueba gratuita | **USD 300 en créditos** por 90 días (primer uso de Serverless en la cuenta) | 2 meses gratis de `dc2.large` (750 h/mes), si aplica |

**Elección: Redshift Serverless con capacidad base de 4 RPU.**
En el taller el cómputo trabaja solo unos minutos: crear tablas, hacer `COPY` y correr ~5 consultas. Con Serverless se paga solo ese tiempo, mientras un clúster aprovisionado cobra todas las horas que esté encendido aunque no se use. Además, los créditos de prueba cubren la práctica.

**Ejemplo:** si el cómputo está activo un total de 15 minutos acumulados, cuesta 4 RPU × 0.25 h × 0.36 ≈ **USD 0.36**. Un `ra3.large` encendido 3 h costaría ≈ USD 1.63.

## 4. Contraseña de administración en Secrets Manager
Al crear el namespace se marca **"Manage admin credentials in AWS Secrets Manager"**. Redshift genera la contraseña del admin, la guarda en un secreto administrado y la puede rotar. El programa Python usa la **Redshift Data API** con el parámetro `SecretArn`, así que nunca ve ni escribe la contraseña. Alternativamente, la Data API puede autenticarse con credenciales IAM temporales (`WorkgroupName` sin secreto).

## 5. Rol de IAM para `COPY` desde S3
Se crea un rol con relación de confianza para `redshift.amazonaws.com` y permisos `s3:GetObject` y `s3:ListBucket` **solo sobre el bucket del taller**. Se asocia al namespace, y en `COPY ... IAM_ROLE '<arn>'` (o `IAM_ROLE default`) Redshift lo asume para leer los archivos.

## 6. Práctica realizada

### Despliegue
Todo se creó por AWS CLI con `user_cli` ([crear.sh](crear.sh)):
- **Namespace** `p5-namespace`:
  - base de datos `actividad`, admin `rsadmin`;
  - **contraseña administrada en Secrets Manager** (`--manage-admin-password`), con el secreto `redshift!p5-namespace-rsadmin-…`;
  - rol por defecto `p5-redshift-s3-role`.
- **Workgroup** `p5-workgroup`: **4 RPU** (la capacidad base mínima), **sin acceso público** y con las subredes de la VPC por defecto. No hace falta abrir red: la Data API es un servicio HTTPS de AWS autenticado con IAM.

### Permisos necesarios (y una lección aprendida)
`user_cli` no tenía ningún permiso de Redshift, porque `AmazonRDSFullAccess` no lo cubre. Se le asoció la política administrada `Punto5Redshift` ([iam/politica_user_cli_redshift.json](iam/politica_user_cli_redshift.json)), que permite:
- `redshift-serverless:*` en Ohio y la Data API;
- `iam:PassRole` solo para el rol de `COPY`;
- los permisos de Secrets Manager sobre `redshift!*`.

Se creó como política **administrada** y no inline: IAM limita a **2048 caracteres la suma de todas las políticas inline** de un usuario, y `user_cli` ya tenía cuatro.

Para que Redshift administre la contraseña, quien crea el namespace necesita **7 permisos** de Secrets Manager:
- `CreateSecret`, `RotateSecret`, `DescribeSecret`, `UpdateSecret`, `DeleteSecret` y `TagResource`;
- `GetRandomPassword`, con `Resource: "*"`, porque Redshift genera la contraseña con él.

Son más que los 3 que pide RDS. El primer intento falló por falta de permisos ([03_redshift_crear_error_permisos.txt](evidencias/03_redshift_crear_error_permisos.txt)), y **dejó creado un secreto huérfano** (`redshift!p5-namespace-awsadmin`). Ese secreto **no se puede borrar a mano porque es propiedad de Redshift**, y bloqueó el nombre ([03b_…](evidencias/03b_redshift_crear_error_secreto_huerfano.txt)). Se resolvió usando otro usuario admin (`rsadmin`). Al final, **una vez eliminado el namespace, Redshift liberó el secreto huérfano** y se pudo programar su eliminación con `delete-secret`.

**Lección:** revisar en la documentación los permisos exactos de cada servicio antes de crear recursos que generan secretos administrados.

### Rol para `COPY`
Rol `p5-redshift-s3-role`:
- **Confianza:** `redshift.amazonaws.com` y `redshift-serverless.amazonaws.com` ([iam/rol_redshift_confianza.json](iam/rol_redshift_confianza.json)).
- **Permisos:** `s3:GetObject`, `s3:ListBucket` y `s3:GetBucketLocation`, **solo** sobre el bucket del punto ([iam/rol_redshift_permisos_s3.json](iam/rol_redshift_permisos_s3.json)).

Se asoció al namespace como rol por defecto, y el `COPY` lo usa con `IAM_ROLE '<arn>'`.

### Conjunto de datos
Dos tablas relacionadas, en CSV ([datos/](datos/)):

| Tabla | Filas | Columnas | Diseño en Redshift |
|---|---|---|---|
| `clientes` | 12 | `cliente_id` (PK), `nombre`, `ciudad`, `segmento`, `fecha_registro` | `DISTSTYLE ALL`: tabla pequeña, se copia en todos los nodos y así el JOIN no mueve datos |
| `pedidos` | 40 | `pedido_id` (PK), `cliente_id` (FK → clientes), `fecha`, `categoria`, `cantidad`, `monto` | `DISTKEY (cliente_id)` para el JOIN y `SORTKEY (fecha)` para filtros por fechas |

En Redshift, las PK y FK son **informativas** (no se validan), pero el optimizador las usa.

### Programa ([redshift_pipeline.py](redshift_pipeline.py))
1. Sube los CSV a `s3://actividad-aws-p5-807872461370/datos/` con Boto3.
2. Lee del namespace el **ARN del secreto** y el **ARN del rol**, para no escribirlos en el código.
3. Envía cada sentencia con la **Data API**: `execute_statement(WorkgroupName, Database, SecretArn, Sql)`. Después consulta `describe_statement` hasta que el estado sea `FINISHED` y recupera las filas con `get_statement_result`, paginando.
4. Ejecuta `DROP`/`CREATE TABLE` y `COPY ... FORMAT AS CSV IGNOREHEADER 1`. Carga **12 y 40 filas**, validadas con `COUNT(*)`.

### Consultas e interpretación ([05_pipeline_resultados.txt](evidencias/05_pipeline_resultados.txt))

| # | Tipo | Pregunta que responde | Resultado e interpretación |
|---|---|---|---|
| 1 | **Filtro** (`WHERE` categoría + monto + rango de fechas) | ¿Qué pedidos de Electrónica superaron 1.000 en el primer semestre de 2026? | **6 pedidos**, entre 1.267,97 y 3.204,29. Están concentrados en pocos clientes (8, 7, 11 y 12): los clientes 8 y 7 aparecen dos veces cada uno, lo que sugiere clientes recurrentes de alto valor en esa categoría |
| 2 | **Unión** (`JOIN` pedidos–clientes) | ¿Quiénes hicieron los 5 pedidos más grandes y de qué ciudad y segmento son? | Los 5 son de **Electrónica**. **Hugo Castro** (Bogotá, Minorista) tiene dos de ellos. 3 de los 5 son clientes **Pyme**, a pesar de ser solo 4 de los 12 clientes, así que es un segmento valioso para campañas de Electrónica |
| 3 | **Agregación** (`GROUP BY` ciudad con `COUNT`, `SUM` y `AVG`, sobre un JOIN) | ¿Cuánto vende cada ciudad, cuántos pedidos hace y cuál es su ticket promedio? | **Bogotá** lidera en ventas (8.081, 14 pedidos). **Barranquilla** (833) y **Cali** (790) tienen el **ticket promedio más alto** con menos pedidos. **Medellín** tiene más clientes con pedidos (4), pero el ticket más bajo (433). Conclusión: Bogotá destaca por volumen; Barranquilla y Cali, por valor por pedido |

## 7. Preguntas de costos

### ¿Qué modalidad de Redshift cuesta menos para esta práctica?
**Serverless.** El cómputo se cobra por segundo solo durante las consultas (≈ USD 0.36–1.00 en total para el taller, cubierto por los créditos de prueba). Un clúster aprovisionado cobra desde USD 0.25–0.54 por **cada hora encendido**, aunque esté inactivo.

### ¿Cómo se cobran el cómputo y el almacenamiento?
- **Cómputo (Serverless):** RPU-hora × USD 0.36, medido por segundo con **mínimo de 60 segundos** cada vez que se activa. Se escala automáticamente desde la capacidad base (4 RPU). Sin consultas, el cómputo cuesta USD 0.
- **Cómputo (aprovisionado):** nodo-hora × número de nodos, mientras el clúster esté encendido (no se cobra si está pausado).
- **Almacenamiento:** **RMS a USD 0.024/GB-mes** por los datos guardados, se use o no el cómputo. Los snapshots manuales y los puntos de recuperación adicionales cobran aparte (≈ USD 0.023/GB-mes).
- **Otros:** S3 para los CSV (USD 0.023/GB-mes, despreciable), Spectrum a USD 5/TB escaneado (no se usa aquí) y el **secreto de admin** (USD 0.40/mes).

Para el dataset del taller (KB o pocos MB), el almacenamiento es ≈ USD 0.00.

### ¿Qué recursos podrían seguir generando cargos después de ejecutar las consultas?
- **Almacenamiento RMS** del namespace mientras exista, aunque el workgroup no se use.
- **Snapshots** manuales o el snapshot final si se pide al borrar.
- **El secreto de admin** en Secrets Manager (USD 0.40/mes) mientras exista.
- **Archivos en S3** (CSV y resultados), mientras no se borre el bucket.
- En **aprovisionado**: el clúster sigue cobrando **cada hora** hasta pausarlo o eliminarlo.
- Consultas programadas, BI conectado o conexiones que dejen el workgroup activo (Serverless cobra mientras haya actividad).
- Si se hubiera hecho accesible públicamente: una IPv4 pública o un *Elastic IP*.

**Limpieza:** eliminar el workgroup y el namespace (sin snapshot final), el bucket S3 con su contenido, el rol de IAM y verificar que el secreto se eliminó.

### Costo real de la práctica
| Concepto | Uso | Costo estimado |
|---|---|---|
| Cómputo (RPU) | ~15 sentencias de 0,04–1,8 s. Con el mínimo de 60 s por cobro y 4 RPU, del orden de **5–10 minutos facturables** | 4 RPU × ≈0,15 h × USD 0.36 ≈ **USD 0.20** (USD 0 con los créditos de prueba de Redshift Serverless) |
| Almacenamiento administrado (RMS) | La consola reportó 322 MB, casi todo de tablas de sistema, durante ~1 h | ≈ USD 0.00001 |
| Secretos (`rsadmin` + el huérfano) | Secretos nuevos con 30 días gratis | USD 0: ambos quedaron programados para eliminación, y un secreto en ese estado no se cobra |
| S3 (2 CSV de pocos KB) | Unas horas | ≈ USD 0 |
| **Total** | | **≈ USD 0.20 de referencia; costo real USD 0**: la cuenta usó el **crédito de prueba de USD 300** de Redshift Serverless |

Al terminar se eliminaron el **workgroup**, el **namespace** (sin snapshot final, y con él el secreto del admin) y el **bucket**. El rol IAM y la política no cobran.

## Fuentes
- [Amazon Redshift Pricing](https://aws.amazon.com/redshift/pricing/)
- [What is Amazon Redshift?](https://docs.aws.amazon.com/redshift/latest/mgmt/welcome.html)
- [Amazon Redshift Serverless – Billing for compute capacity](https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-billing.html)
- [Managing Amazon Redshift admin passwords using AWS Secrets Manager](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-secrets-manager-integration.html)
- [Using the Amazon Redshift Data API](https://docs.aws.amazon.com/redshift/latest/mgmt/data-api.html)
- [Loading data from Amazon S3 (COPY)](https://docs.aws.amazon.com/redshift/latest/dg/t_Loading-data-from-S3.html)
- AWS Price List API, `AmazonRedshift`, región us-east-2 (consultada el 2026-09-29)
