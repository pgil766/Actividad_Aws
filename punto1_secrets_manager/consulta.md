# Punto 1 – AWS Secrets Manager: consulta

> Precios de **US East (Ohio) – us-east-2**, tomados de la AWS Price List API el 2026-09-29.

## 1. ¿Qué es AWS Secrets Manager?

Es un servicio administrado de AWS para **guardar, cifrar, distribuir y rotar secretos**. Un secreto es cualquier dato sensible que una aplicación necesita para funcionar y que no debe quedar escrito en el código ni en archivos de configuración.

Cada secreto se guarda cifrado con una llave de **AWS KMS**: la administrada por AWS (`aws/secretsmanager`) o una propia. Además, cada secreto tiene **versiones**, identificadas por *etiquetas de etapa*:

| Etapa | Significado |
|---|---|
| `AWSCURRENT` | Versión vigente, la que se entrega por defecto |
| `AWSPREVIOUS` | Versión anterior, útil para volver atrás |
| `AWSPENDING` | Versión en creación durante una rotación |

## 2. ¿Qué tipo de información permite guardar?

Cualquier texto o dato binario de hasta **64 KB**. Normalmente es un JSON de pares clave-valor. Ejemplos:
- Usuario y contraseña de bases de datos (RDS, Aurora, DocumentDB, Redshift…)
- Claves de API de terceros y tokens OAuth
- Cadenas de conexión
- Llaves privadas o certificados
- Cualquier par clave-valor de configuración sensible

## 3. ¿Cómo se controla quién puede leer un secreto?

Hay tres capas que actúan juntas:

1. **Políticas de identidad (IAM):** se asignan a un usuario, grupo o rol e indican qué acciones puede hacer (`secretsmanager:GetSecretValue`, `DescribeSecret`, `PutSecretValue`…) y sobre qué secretos (`Resource` = ARN del secreto). Aplicando **mínimo privilegio**, el programa del taller solo tiene `GetSecretValue` sobre el ARN de un único secreto.
2. **Política de recurso:** es una política pegada al propio secreto. Sirve, por ejemplo, para dar acceso a otra cuenta de AWS o para negar explícitamente a todos menos a un rol.
3. **Permisos de KMS:** para descifrar el secreto, quien lo lee también necesita `kms:Decrypt` sobre la llave. Con la llave administrada por AWS esto se concede automáticamente a quien tenga permiso sobre el secreto. Con una llave propia, la política de la llave es un control adicional.

Además, se pueden usar **condiciones** (etiquetas, IP de origen, VPC endpoint) y **CloudTrail** registra cada lectura para auditoría.

## 4. Crear, recuperar y rotar

| Operación | Qué es | Quién la hace | API |
|---|---|---|---|
| **Crear** | Registrar un secreto nuevo con su primer valor. Se cifra y queda como `AWSCURRENT` | Un administrador o la infraestructura (consola, CLI, Terraform, o el servicio mismo, como RDS con contraseña administrada) | `CreateSecret` |
| **Recuperar desde una aplicación** | El programa pide el valor **en tiempo de ejecución** con el SDK. No guarda la contraseña: la obtiene cada vez, o la cachea por un tiempo | La aplicación, autenticada con su identidad IAM | `GetSecretValue` |
| **Rotar** | Cambiar el valor del secreto **y** la credencial real en el sistema de destino (por ejemplo la contraseña en la base de datos), idealmente de forma automática y periódica | Secrets Manager, con una función Lambda de rotación o con **rotación administrada** (RDS, Redshift, DocumentDB) | `RotateSecret` |

**Diferencia clave:** actualizar a mano el valor (`PutSecretValue`) solo cambia lo que está guardado. **Rotar** además cambia la credencial en la base de datos, coordinando las etapas `AWSPENDING` → `AWSCURRENT` para que la aplicación nunca quede con una contraseña inválida.

## 5. ¿Por qué el programa obtiene la versión nueva sin cambiar el código?

El programa llama a `get_secret_value(SecretId="taller/punto1/demo")` sin pedir una versión específica. Por defecto, Secrets Manager entrega la versión con la etapa **`AWSCURRENT`**.

Cuando se cambia el valor (`put-secret-value` o desde la consola), se crea una **nueva versión**. Esa versión recibe `AWSCURRENT` y la anterior pasa a `AWSPREVIOUS`. Así, la siguiente ejecución del programa recibe automáticamente el valor nuevo. Se puede ver en el `VersionId` que devuelve la respuesta, que cambia entre las dos ejecuciones.

## 6. Preguntas de costos

### ¿Cómo se cobran los secretos almacenados y las llamadas a la API?

| Concepto | Precio (us-east-2) |
|---|---|
| Secreto almacenado | **USD 0.40 por secreto al mes**, prorrateado por hora (≈ USD 0.00055/h) |
| Llamadas a la API | **USD 0.05 por cada 10 000 llamadas** |
| Prueba gratuita | Los secretos nuevos tienen **30 días gratis** desde su creación (según la página de precios) |

Las réplicas de un secreto en otras regiones cuentan como secretos adicionales. Si se usa una llave KMS propia, se suma su costo.

**Estimación para este punto:** el secreto existe unas horas y se hacen unas pocas decenas de llamadas.
- Almacenamiento: 3 h × USD 0.00055 ≈ **USD 0.002**
- Llamadas: 20 / 10 000 × 0.05 ≈ **USD 0.0001**
- Total ≈ **USD 0.00**, y además queda cubierto por los 30 días gratis.

### ¿Qué ocurre con el costo si el programa consulta el mismo secreto repetidamente?

El secreto cuesta lo mismo, pero **cada llamada se cobra**. Ejemplos:

| Frecuencia | Llamadas/mes | Costo/mes |
|---|---|---|
| 1 vez por hora | ~730 | ≈ USD 0.004 |
| 1 vez por minuto | ~43 800 | ≈ USD 0.22 |
| 1 vez por segundo | ~2 628 000 | ≈ USD 13.14 |
| En cada petición de una API con 100 req/s | ~262 millones | ≈ USD 1 314 |

Consultar en cada operación no solo cuesta más: también agrega latencia (una llamada de red extra) y puede toparse con los límites de tasa de la API.

### ¿Cuándo convendría guardar temporalmente el valor en memoria?

Conviene cuando el programa **usa el secreto muchas veces** (un servidor web, un proceso que abre muchas conexiones, una Lambda que se invoca miles de veces). Se lee una vez y se guarda en memoria con un **tiempo de vida (TTL)**, por ejemplo 5–60 minutos. Para esto existen la librería `aws-secretsmanager-caching` (Python) y el *Secrets Manager Agent*.

Hay que tener en cuenta:
- **Nunca** escribir el valor cacheado en disco ni en logs.
- El TTL debe ser menor que el período de rotación. Si una conexión falla por autenticación, se debe refrescar la caché de inmediato.
- Para un script que se ejecuta una sola vez (como el de este punto), la caché no aporta: una sola llamada basta.

## Fuentes
- [AWS Secrets Manager – Pricing](https://aws.amazon.com/secrets-manager/pricing/)
- [What is AWS Secrets Manager?](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [Authentication and access control for Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/auth-and-access.html)
- [Rotate AWS Secrets Manager secrets](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
- [Cache secrets – Python](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_cache-python.html)
- AWS Price List API, `AWSSecretsManager`, región us-east-2 (consultada el 2026-09-29)
