# Punto 6 – AWS Glue Data Catalog: consulta

> Precios de **US East (Ohio) – us-east-2**, tomados de la AWS Price List API el 2026-09-29.

## 1. ¿Qué almacena Glue Data Catalog?

Es un **repositorio central de metadatos**. Es decir, guarda la *descripción* de los datos, no los datos:
- Nombres de bases de datos y tablas
- **Esquema**: columnas, tipos de datos y su orden
- **Ubicación** de los datos (por ejemplo `s3://bucket/ventas/`)
- **Formato** y cómo leerlo: CSV/JSON/Parquet, SerDe, delimitador, si hay encabezado, compresión
- **Particiones** (por ejemplo `anio=2026/mes=09/`) y estadísticas
- Conexiones (JDBC, etc.), clasificadores y propiedades de la tabla

Es compatible con el Hive Metastore y lo usan **Athena, Redshift Spectrum, EMR, Glue ETL y Lake Formation**. Varios servicios comparten así la misma definición de tabla.

### Datos en S3 vs metadatos en el catálogo

| | Archivos en S3 | Metadatos en Glue Data Catalog |
|---|---|---|
| Qué son | Los **datos reales** (filas del CSV/JSON) | La **descripción** de esos datos (esquema, ubicación, formato) |
| Dónde viven | Objetos en un bucket | Entradas en el catálogo de la cuenta y región |
| Tamaño | Puede ser de GB a PB | KB: unas pocas definiciones |
| Qué pasa si se borran | Se pierde la información | Los datos siguen intactos en S3; solo se pierde la "vista" de tabla para consultarlos |
| Costo | Por GB almacenado en S3 | Por objetos del catálogo y peticiones (con capa gratuita amplia) |

Cuando se ejecuta `SELECT * FROM ventas` en Athena, Athena **pregunta al catálogo** dónde están los datos y cómo leerlos, y **luego lee los archivos de S3**. La tabla es una "lente" sobre los archivos (*schema-on-read*).

### Bases de datos, tablas y *crawlers*

| Elemento | Función |
|---|---|
| **Base de datos** | Contenedor lógico (un *namespace*) que agrupa tablas relacionadas, como `taller_glue`. No guarda datos |
| **Tabla** | Definición de metadatos de un conjunto de datos: esquema + ubicación en S3 + formato + particiones. Se consulta con SQL desde Athena |
| ***Crawler*** | Proceso que **recorre una ruta de S3** (u otra fuente), **infiere** el formato y el esquema con clasificadores, y **crea o actualiza** tablas y particiones en el catálogo. Puede ejecutarse a demanda o programado, y necesita un **rol de IAM** para leer S3 y escribir en el catálogo |

## 2. Crawler vs creación manual de la tabla

| | Crawler | Creación manual (DDL en Athena o consola) |
|---|---|---|
| Esquema | **Inferido** automáticamente; puede equivocarse (por ejemplo, una fecha como `string`, un código con ceros a la izquierda como `bigint`, encabezados no detectados si todas las columnas son texto) | **Definido exactamente** por el usuario: tipos, nombres y SerDe controlados |
| Cambios en los datos | Detecta **columnas nuevas y particiones nuevas** al volver a ejecutarse | Hay que modificar la tabla a mano (`ALTER TABLE`, `MSCK REPAIR TABLE` para particiones) |
| Esfuerzo | Poco: se configura una vez | Hay que conocer el formato y escribir el DDL |
| Costo | DPU-hora de cada ejecución (mínimo 10 min) | USD 0 (solo la consulta DDL en Athena, que no escanea datos) |
| Riesgo | Si hay archivos con formatos mezclados en la misma carpeta, crea varias tablas o esquemas erróneos | Errores humanos al escribir el DDL |
| Cuándo usarlo | Datos cambiantes, muchas fuentes o particiones, descubrimiento inicial | Esquema estable y conocido, cuando se necesita control total de tipos |

Para los registros nuevos: si se agregan **archivos nuevos con el mismo esquema en la misma carpeta**, Athena los lee sin volver a ejecutar el crawler, porque la tabla apunta a la carpeta. Se vuelve a ejecutar el crawler cuando cambia el esquema o aparecen particiones nuevas.

## 3. ¿Se necesita alguna credencial de aplicación?

**No, si se trabaja solo con S3, Glue y Athena.** Ninguno de estos servicios tiene usuario y contraseña propios: todo el acceso se controla con **IAM**.
- `user_cli` (o el usuario de consola) necesita permisos de Glue, Athena y S3.
- El **crawler** asume un **rol de IAM** (`AWSGlueServiceRole` + lectura del bucket) y obtiene credenciales temporales automáticamente.
- **Athena** usa la identidad de quien ejecuta la consulta para leer S3 y escribir los resultados.

No hay ninguna contraseña que guardar, así que **no se crea otro secreto**. Solo si el crawler se conectara a una fuente con usuario y contraseña (una **conexión JDBC** a RDS, Redshift, etc.), esa credencial se guardaría en **Secrets Manager** y la conexión de Glue la referenciaría.

## 4. Preguntas de costos

### ¿Qué se cobra por el crawler, el catálogo, S3 y las consultas de Athena?

| Servicio | Cómo se cobra (us-east-2) | Estimación del taller |
|---|---|---|
| **Crawler** | **USD 0.44 por DPU-hora**, facturado por segundo con **mínimo de 10 minutos por ejecución** | Cada ejecución sobre archivos pequeños ≈ 10 min mínimo → 0.44 × 10/60 ≈ **USD 0.073 por ejecución**. Con 2–3 ejecuciones ≈ USD 0.15–0.22 |
| **Data Catalog: almacenamiento** | Primer **millón de objetos gratis** al mes; después USD 1 por cada 100 000 objetos/mes | Unas pocas tablas → **USD 0** |
| **Data Catalog: peticiones** | Primer **millón de peticiones gratis** al mes; después USD 1 por millón | **USD 0** |
| **S3** | USD 0.023/GB-mes (Standard) + peticiones (PUT ≈ USD 0.005 por 1 000, GET ≈ USD 0.0004 por 1 000) | Archivos de KB y resultados de Athena → **≈ USD 0.00** |
| **Athena** | **USD 5 por TB escaneado**, redondeado al MB, con **mínimo de 10 MB por consulta**. Las consultas DDL (`CREATE`/`ALTER`/`DROP`) y las fallidas no se cobran | Un archivo de KB se cobra como 10 MB: 10 MB × USD 5/TB ≈ **USD 0.00005 por consulta**. 20 consultas ≈ USD 0.001 |

**Total estimado del punto: ≈ USD 0.25**, casi todo por las ejecuciones del crawler.

### ¿Qué efecto tiene el volumen de datos examinados?
- **Athena cobra directamente por los bytes que lee de S3**, no por el tiempo ni por las filas devueltas. Duplicar los datos escaneados duplica el costo; una consulta sobre 1 TB cuesta USD 5 aunque devuelva una sola fila. Un `LIMIT` **no** reduce necesariamente lo escaneado.
- **El crawler** tarda más (más DPU-horas) cuantos más archivos y carpetas recorre.
- Cómo **reducir el volumen examinado**:
  - **Formatos columnares** (Parquet/ORC): Athena lee solo las columnas de la consulta.
  - **Compresión** (Snappy, GZIP): menos bytes que leer.
  - **Particionar** (por ejemplo por fecha) y filtrar por la partición: Athena se salta carpetas enteras.
  - Seleccionar solo las columnas necesarias en lugar de `SELECT *`.
  - En el crawler: *incremental crawls* (solo carpetas nuevas) y rutas de inclusión o exclusión.
- Con datos tan pequeños como los del taller, se paga el **mínimo de 10 MB por consulta**, así que el volumen no se nota. A escala de GB o TB es el principal factor de costo.

## Fuentes
- [AWS Glue Pricing](https://aws.amazon.com/glue/pricing/)
- [Amazon Athena Pricing](https://aws.amazon.com/athena/pricing/)
- [Amazon S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [AWS Glue Data Catalog](https://docs.aws.amazon.com/glue/latest/dg/catalog-and-crawler.html)
- [Using crawlers to populate the Data Catalog](https://docs.aws.amazon.com/glue/latest/dg/add-crawler.html)
- [Creating tables in Athena (CREATE TABLE)](https://docs.aws.amazon.com/athena/latest/ug/creating-tables.html)
- [Connecting to data with AWS Glue connections (JDBC + Secrets Manager)](https://docs.aws.amazon.com/glue/latest/dg/glue-connections.html)
- AWS Price List API, `AWSGlue` y `AmazonAthena`, región us-east-2 (consultada el 2026-09-29)
