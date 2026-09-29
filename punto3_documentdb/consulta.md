# Punto 3 – Amazon DocumentDB: consulta

> Precios de **US East (Ohio) – us-east-2**, tomados de la AWS Price List API el 2026-09-29.

## 1. ¿Qué es Amazon DocumentDB?

Es una base de datos de documentos **administrada por AWS** y **compatible con la API de MongoDB**: se usan los mismos drivers (`pymongo`), el mismo formato BSON/JSON y herramientas como MongoDB Compass.

Por dentro **no es MongoDB**: es un motor propio de AWS con arquitectura de **cómputo separado del almacenamiento**. El almacenamiento es un volumen distribuido que se replica 6 veces en 3 zonas de disponibilidad y crece solo. Encima de ese volumen van 1 instancia primaria y hasta 15 réplicas de lectura.

## 2. DocumentDB vs MongoDB: diferencias que pueden afectar una aplicación existente

| # | Diferencia | Impacto en una aplicación existente |
|---|---|---|
| 1 | **Compatibilidad de versión de API:** DocumentDB emula la API de MongoDB 3.6, 4.0 y 5.0, no las versiones más nuevas. Algunos operadores, etapas de agregación y comandos **no están soportados** o se comportan distinto | Consultas o *pipelines* que funcionan en MongoDB pueden fallar con "feature not supported". Hay que probar con la [lista de APIs soportadas](https://docs.aws.amazon.com/documentdb/latest/developerguide/mongo-apis.html) o la herramienta de compatibilidad de AWS |
| 2 | **Sin JavaScript en el servidor:** no soporta `$where`, `mapReduce` ni funciones JS almacenadas | Hay que reescribir esa lógica con el *aggregation pipeline* o en la aplicación |
| 3 | **`retryWrites` no soportado:** la cadena de conexión debe llevar `retryWrites=false` | Si no se cambia, los drivers modernos (que lo activan por defecto) fallan al escribir |
| 4 | **Red y seguridad:** solo es accesible **dentro de una VPC** (no hay endpoint público) y **TLS está activado por defecto** con el certificado de AWS (`global-bundle.pem`) | La app debe correr en la misma VPC o conectarse por túnel/VPN y configurar TLS con la CA de AWS. Una app que se conectaba por internet a MongoDB Atlas cambia su despliegue |
| 5 | **Escalado horizontal distinto:** los clústeres basados en instancias **no hacen *sharding***; escalan leyendo en réplicas. Para *sharding* existen los *Elastic Clusters*, un producto aparte | Una app que depende de claves de *shard* o de comandos de *sharding* (`sh.*`) debe rediseñarse o usar Elastic Clusters |
| 6 | **Modelo de costos y operación:** se paga por instancia-hora (o DCU-hora), almacenamiento **y cada operación de E/S** (en el modo estándar). No hay acceso al sistema operativo ni a la configuración interna del `mongod` | Consultas mal indexadas cuestan dinero en E/S. Configuraciones avanzadas de MongoDB (motores de almacenamiento, parámetros) no aplican |

## 3. Instancia aprovisionada vs DocumentDB Serverless

| | Aprovisionada | Serverless |
|---|---|---|
| Cómo se cobra | Precio fijo por hora de la instancia, se use o no | Por **DCU-hora** consumida (1 DCU ≈ 2 GiB de memoria + CPU y red), facturado por segundo |
| Capacidad | Fija según el tipo (`db.t4g.medium` = 2 vCPU, 4 GiB) | Escala entre un mínimo y un máximo configurables; **mínimo 0,5 DCU** |
| Instancia más barata (us-east-2) | `db.t4g.medium`: **USD 0.0757/h** · `db.t3.medium`: USD 0.078/h | 0,5 DCU × USD 0.0822 = **USD 0.0411/h** |
| Cargo extra | Instancias `t3`/`t4g`: créditos de CPU si se excede la línea base (USD 0.09/vCPU-h) | Si la carga sube, sube el número de DCU |
| Prueba gratuita | **30 días gratis** con 750 h/mes de `db.t3.medium`, 30 M de E/S, 5 GB de almacenamiento y 5 GB de backup (primer uso de DocumentDB en la cuenta) | No incluida en la prueba gratuita |

Comunes a ambos: almacenamiento **USD 0.10/GB-mes**, E/S **USD 0.20 por millón** (modo estándar) y backup extra USD 0.021/GB-mes.

### ¿Cuál es más económica para este taller?
La carga del taller es mínima (10 documentos y unas pocas consultas) durante unas **3 a 4 horas**:

| Opción | Cálculo (4 h) | Costo |
|---|---|---|
| `db.t3.medium` **con prueba gratuita** | cubierto por las 750 h gratis | **USD 0.00** |
| Serverless, 0,5–1 DCU | 4 h × 0,5 DCU × 0.0822 | **≈ USD 0.16** |
| `db.t4g.medium` sin prueba | 4 h × 0.0757 | ≈ USD 0.30 |

**Conclusión:**
- Si la cuenta **todavía tiene la prueba gratuita** de DocumentDB, lo más barato es **`db.t3.medium` aprovisionada**: cuesta USD 0.
- Si no la tiene, lo más barato es **Serverless con mínimo 0,5 DCU y máximo 1–2 DCU**: a carga baja se queda en 0,5 DCU y cuesta **~46 % menos por hora** que la instancia más pequeña.

En ambos casos se usa **1 sola instancia** (sin réplicas) y almacenamiento estándar, no I/O-Optimized.

## 4. Arquitectura de conexión (para el diagrama)

```
[Tu PC] --SSH:22--> [EC2 bastión (subred pública, IP pública)] --TCP:27017 + TLS--> [DocumentDB (subredes privadas)]
   │                                                                                    ▲
   └── Compass / pymongo se conectan a localhost:27017 ── túnel SSH (-L 27017:endpoint:27017) ──┘
```

- **Security Group de la EC2:** entrada TCP 22 solo desde **tu IP pública** (`x.x.x.x/32`).
- **Security Group de DocumentDB:** entrada TCP 27017 **solo desde el SG de la EC2** (no desde una IP).
- **TLS:** se descarga `global-bundle.pem` y se usa como CA (`tlsCAFile`). Como la conexión llega por `localhost`, el nombre del certificado no coincide, así que se necesita `tlsAllowInvalidHostnames=true`, además de `directConnection=true` y `retryWrites=false`.
- **Contraseña:** se crea con la contraseña administrada en Secrets Manager (si el motor lo permite) o se guarda en un secreto propio. El programa la lee con `GetSecretValue`.

## 5. Preguntas de costos

### ¿Qué opción de DocumentDB cuesta menos para esta práctica?
Con la prueba gratuita disponible: **`db.t3.medium`** (USD 0). Sin la prueba: **DocumentDB Serverless con 0,5 DCU mínimo**, ≈ USD 0.041/h frente a USD 0.076/h de `db.t4g.medium`.

El almacenamiento (unos KB) y las E/S (unos miles) son despreciables: < USD 0.01. En ambos casos hay que **borrar el clúster sin snapshot final** al terminar.

### ¿Cuánto agrega la EC2 del túnel?
Con una EC2 `t3.micro` (o `t4g.micro`) de 8 GB:

| Concepto | Por hora |
|---|---|
| t3.micro | USD 0.0104 |
| IPv4 pública | USD 0.005 |
| EBS 8 GB gp3 | ≈ USD 0.0009 |
| **Total EC2 del túnel** | **≈ USD 0.016/h** |

Para 4 horas de práctica son **≈ USD 0.07**. En serverless, la EC2 sumaría cerca de un **40 %** al costo de la base de datos. Si la cuenta tiene capa gratuita o créditos de EC2, puede quedar en USD 0.

## Fuentes
- [Amazon DocumentDB Pricing](https://aws.amazon.com/documentdb/pricing/)
- [Functional differences: Amazon DocumentDB and MongoDB](https://docs.aws.amazon.com/documentdb/latest/developerguide/functional-differences.html)
- [Supported MongoDB APIs, operations, and data types](https://docs.aws.amazon.com/documentdb/latest/developerguide/mongo-apis.html)
- [Amazon DocumentDB serverless](https://docs.aws.amazon.com/documentdb/latest/developerguide/docdb-serverless.html)
- [Connecting to an Amazon DocumentDB cluster from outside an Amazon VPC (SSH tunnel)](https://docs.aws.amazon.com/documentdb/latest/developerguide/connect-from-outside-a-vpc.html)
- [Connect using MongoDB Compass](https://docs.aws.amazon.com/documentdb/latest/developerguide/studio3t.html)
- AWS Price List API, `AmazonDocDB`, región us-east-2 (consultada el 2026-09-29)
