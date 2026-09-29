# Punto 4 – Amazon Neptune: consulta

> Precios de **US East (Ohio) – us-east-2**, tomados de la AWS Price List API el 2026-09-29.

## 1. ¿Qué es Amazon Neptune?

Es la base de datos de **grafos administrada** de AWS. Guarda **vértices (nodos)** y **aristas (relaciones)** con propiedades, y está optimizada para recorrer relaciones: amigos de amigos, rutas, recomendaciones, detección de fraude. Igual que DocumentDB, separa el **cómputo** (instancias) del **almacenamiento** (volumen distribuido de 6 copias en 3 zonas, que crece solo) y vive **dentro de una VPC**.

## 2. Neptune vs Neo4j

| Aspecto | Amazon Neptune | Neo4j |
|---|---|---|
| **Modelo de datos** | Soporta **dos modelos**: grafo de propiedades (*Labeled Property Graph*) y **RDF** (tripletas sujeto-predicado-objeto, para la web semántica). Ambos sobre el mismo servicio | Solo **grafo de propiedades**: nodos con *labels* y propiedades, relaciones con un tipo y propiedades |
| **Lenguajes de consulta** | **Gremlin** (Apache TinkerPop, imperativo por recorridos), **openCypher** (declarativo, estilo Cypher) y **SPARQL** (para RDF) | **Cypher**, su lenguaje nativo y el origen de openCypher/GQL. Gremlin solo mediante plugins de terceros |
| **Compatibilidad Cypher** | openCypher: un subconjunto de Cypher. No incluye procedimientos APOC ni algunas funciones específicas de Neo4j | Cypher completo, con **APOC** y **Graph Data Science (GDS)** para algoritmos (PageRank, comunidades, caminos) |
| **Herramientas** | Consola de AWS, **Neptune Workbench** (notebooks Jupyter con *magics* `%%gremlin`, `%%oc`, `%%sparql`), **Graph Explorer** (visualización), **Bulk Loader** desde S3, `neptunedata` en el SDK/CLI, **Neptune Analytics** para algoritmos | **Neo4j Browser**, **Bloom** (visualización), **Neo4j Desktop**, Aura (nube), drivers oficiales, `neo4j-admin import` |
| **Despliegue y operación** | 100 % administrado: sin servidores que mantener, backups, réplicas y *failover* automáticos. Solo en AWS | Autoadministrado (Community/Enterprise en tu servidor) o administrado con **AuraDB** en varias nubes |
| **Acceso** | Por defecto solo desde la VPC. Desde la versión 1.4.6 permite **endpoint público con autenticación IAM** | Puerto Bolt (7687) y HTTP; acceso según donde se despliegue |
| **Modelo de costos** | Instancia-hora o NCU-hora (serverless) + almacenamiento + E/S | Gratis (Community) o licencia/suscripción (Enterprise, Aura) |

## 3. Aprovisionada vs Serverless

| | Aprovisionada | Serverless |
|---|---|---|
| Cobro | Precio fijo por hora de instancia | Por **NCU-hora** (1 NCU ≈ 2 GiB de memoria + CPU y red) |
| Instancia/capacidad mínima | `db.t4g.medium`: **USD 0.093/h** · `db.t3.medium`: USD 0.098/h | **Mínimo 1 NCU** × USD 0.1608 = **USD 0.161/h** |
| Prueba gratuita | **30 días**: 750 h de `db.t3.medium` o `db.t4g.medium`, 10 M de E/S, 1 GB de almacenamiento y 1 GB de backup | No incluida |

Almacenamiento **USD 0.10/GB-mes** y E/S **USD 0.20 por millón** en ambos casos (modo estándar).

**Elección para el taller: `db.t4g.medium` aprovisionada.**
- A diferencia de DocumentDB, el mínimo de Serverless (1 NCU = USD 0.161/h) es **más caro** que la instancia más pequeña (USD 0.093/h). Serverless solo conviene con cargas muy variables que suban mucho.
- `db.t4g.medium` además **entra en la prueba gratuita** de 30 días.
- Se crea con **1 sola instancia**, sin réplicas.

## 4. ¿Cómo consultar Neptune desde local?

| | Túnel SSH por EC2 (bastión) | Endpoint público de Neptune |
|---|---|---|
| Requisito de versión | Cualquiera | Motor **1.4.6.x o superior** |
| Autenticación | La que tenga el clúster (IAM opcional) + llave SSH de la EC2 | **IAM obligatoria**: cada petición se firma con **SigV4** usando las credenciales de `user_cli` |
| Red | Neptune en subredes privadas. La EC2 en una subred pública con IGW. SG de Neptune: 8182 desde el SG de la EC2. SG de la EC2: 22 desde tu IP | Las instancias de Neptune en **subredes públicas** (tabla de rutas con `0.0.0.0/0 → Internet Gateway`). SG de Neptune: TCP 8182 **solo desde tu IP** (`/32`). La instancia se crea con `--publicly-accessible` |
| Conexión | `ssh -L 8182:<endpoint>:8182 ec2-user@<ip>` y luego `https://localhost:8182` (hay que manejar el nombre del certificado TLS) | Directo a `https://<endpoint>:8182` con `boto3.client("neptunedata", endpoint_url=...)` |
| Costo extra | EC2 + IPv4 pública (≈ USD 0.016/h) | **Ninguno** (solo transferencia de datos, despreciable) |
| Seguridad | Neptune no queda expuesto a internet | Expuesto a internet, pero limitado por SG a tu IP y por IAM |

### ¿Es necesario el proceso con EC2? ¿Existe otra manera?
**No es obligatorio.** Neptune vive en una VPC, así que *algo* tiene que dar acceso a esa red, pero hay varias alternativas:
1. **Endpoint público de Neptune** (versión 1.4.6+): sin EC2, con IAM + SG restringido a tu IP. **Es la opción recomendada para el taller** por costo y simplicidad.
2. **Neptune Workbench** (notebooks de SageMaker dentro de la VPC): no requiere configurar red, pero la instancia del notebook cobra por hora.
3. **AWS CloudShell en modo VPC:** una terminal en el navegador lanzada dentro de la VPC, sin EC2 propia.
4. **AWS Client VPN** o VPN site-to-site: tu PC entra a la VPC (más costoso y complejo).
5. **SSM Session Manager (port forwarding):** evita abrir el puerto 22, pero igual necesita una EC2.
6. **Lambda o API Gateway** dentro de la VPC como intermediario.

**Opción elegida: [COMPLETAR: endpoint público o túnel]**. Documentar la VPC, las subredes usadas, la tabla de rutas (ruta al IGW), los SG y el método de autenticación (IAM/SigV4).

## 5. Preguntas de costos

### ¿Cuánto cuestan el cómputo y el almacenamiento?

| Concepto | Tarifa us-east-2 | Estimación práctica (4 h) |
|---|---|---|
| Cómputo `db.t4g.medium` | USD 0.093/h | 4 × 0.093 = **USD 0.37** (USD 0 con prueba gratuita) |
| (Alternativa) Serverless 1 NCU | USD 0.1608/NCU-h | 4 × 0.161 = USD 0.64 |
| Almacenamiento | USD 0.10/GB-mes (se cobra lo usado) | Grafo de ~25 elementos: KB → **≈ USD 0.00** |
| E/S | USD 0.20 por millón | Unos miles → **≈ USD 0.00** |
| Backup | Gratis hasta el 100 % del tamaño del clúster | USD 0 |

Si se dejara encendida **un mes**: `db.t4g.medium` ≈ USD 68; Serverless con 1 NCU ≈ USD 117.

### ¿Su método de conexión añade una instancia EC2?
- **Con el endpoint público:** **no**. El costo adicional es USD 0, salvo la transferencia de datos a internet, que es despreciable para consultas pequeñas.
- **Con el túnel SSH:** **sí**. Una `t3.micro` + IPv4 pública + 8 GB EBS ≈ **USD 0.016/h** (≈ USD 0.07 en 4 h).

### ¿Qué se sigue cobrando mientras no ejecuta consultas?
- **La instancia de Neptune completa**, cada hora que esté disponible, aunque no reciba ninguna consulta. Es el costo principal.
- En Serverless, la **capacidad mínima** (1 NCU) se sigue cobrando.
- **Almacenamiento** del volumen del clúster y **snapshots manuales**, incluidos los que quedan después de borrar el clúster si se pide snapshot final.
- Si se usó túnel: la **EC2**, su **IPv4 pública** y su **volumen EBS**.
- Un clúster **detenido** no cobra cómputo pero sí almacenamiento, y AWS lo vuelve a encender a los 7 días. Por eso, al terminar se **elimina**.

## Fuentes
- [Amazon Neptune Pricing](https://aws.amazon.com/neptune/pricing/)
- [Neptune Public Endpoints](https://docs.aws.amazon.com/neptune/latest/userguide/neptune-public-endpoints.html)
- [Amazon Neptune Database now supports Public Endpoints (2025-09)](https://aws.amazon.com/about-aws/whats-new/2025/09/aws-neptune-database-public-endpoints/)
- [Build graph applications faster with Amazon Neptune public endpoints](https://aws.amazon.com/blogs/database/build-graph-applications-faster-with-amazon-neptune-public-endpoints/)
- [Neptune Serverless now scales down to 1 NCU](https://aws.amazon.com/about-aws/whats-new/2023/03/amazon-neptune-serverless-scales-down-1-ncu-costs/)
- [Authenticating your Neptune database with IAM](https://docs.aws.amazon.com/neptune/latest/userguide/iam-auth.html)
- [Connecting to an Amazon Neptune cluster](https://docs.aws.amazon.com/neptune/latest/userguide/get-started-connecting.html)
- [openCypher compliance in Amazon Neptune](https://docs.aws.amazon.com/neptune/latest/userguide/feature-opencypher-compliance.html)
- AWS Price List API, `AmazonNeptune`, región us-east-2 (consultada el 2026-09-29)
