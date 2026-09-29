# Ingeniería de Datos
## Actividad AWS
### 2026-2

**Universidad EIA**

---

**Indicaciones generales**

Use una sola región de AWS y mantenga los recursos activos únicamente durante el tiempo necesario para realizar las pruebas. Antes de cada despliegue, elija la configuración de menor costo que permita cumplir el ejercicio y estime el gasto según la región y las horas previstas de uso. Al finalizar, elimine los recursos y compruebe si quedan componentes facturables, como almacenamiento, instantáneas o instancias auxiliares.

**Uso de secretos:** desde el punto 1, toda contraseña o credencial de base de datos que se necesite en los ejercicios debe gestionarse mediante **AWS Secrets Manager**. Los programas deben recuperar el secreto durante su ejecución, no deben llevar contraseñas escritas en el código. Cuando un servicio ofrezca administración integrada de su contraseña en Secrets Manager, investigue y use esa opción.

**Entrega final:** suba código, consultas, instrucciones, resultados y evidencias a un repositorio de GitHub y comparta un enlace al que un externo pueda acceder, en caso tal de que no desee hacer el repositorio público puede agregar al usuario “smm-0216”. Incluya un README.md para reproducir cada punto. No publique valores de secretos, claves de IAM, llaves privadas, archivos de estado de Terraform ni capturas que muestren credenciales.

> Terraform solo es obligatorio en el **punto 2**. En los demás puntos puede usar la consola de AWS, AWS CLI o el SDK.

**1. AWS Secrets Manager**

Investigue qué es AWS Secrets Manager, qué tipo de información permite guardar y cómo se controla quién puede leer un secreto. Distinga entre **crear un secreto**, **recuperarlo desde una aplicación** y **rotarlo**.

Cree un secreto de prueba que contenga un usuario y una contraseña ficticios. Configure permisos para que un programa en Python pueda leer únicamente ese secreto y recupérelo con Boto3. Modifique su valor y compruebe que el programa obtiene la versión actual sin cambiar el código.

**Preguntas de costos:** ¿Cómo se cobran los secretos almacenados y las llamadas a la API? ¿Qué ocurre con el costo si el programa consulta el mismo secreto repetidamente? ¿Cuándo convendría guardar temporalmente el valor en memoria?

**Entregables:** código Python, política de acceso, explicación de la actualización del secreto, estimación de costos y evidencia de eliminación del secreto de prueba.

**2. Despliegue con Terraform, SDK y AWS CLI**

Investigue qué es Terraform y cómo se utiliza para definir, planificar, crear y eliminar infraestructura.

Configure el usuario de IAM user_cli para trabajar con AWS CLI, Boto3 y Terraform. Investigue y documente los permisos que necesita para crear y eliminar un bucket de S3, una instancia EC2, una instancia RDS y los componentes de red utilizados. Verifique las operaciones con ese usuario, sin utilizar las credenciales de la cuenta raíz.

Cree los tres recursos mediante Terraform. Configure RDS para que su contraseña sea administrada en Secrets Manager, si el motor y la configuración elegidos lo permiten. Repita el despliegue con Boto3 y después con AWS CLI. Realice las tres versiones de forma secuencial y elimine los recursos de cada versión antes de iniciar la siguiente. Compare los métodos.

Explique cómo autentica user_cli las herramientas. **No guarde sus claves de acceso como una contraseña de base de datos en Secrets Manager:** las herramientas necesitan autenticarse en AWS antes de poder leer un secreto. Revise también qué información conserva Terraform en su archivo de estado y evite introducir allí contraseñas.

**Preguntas de costos:** ¿Cuánto costaría mantener los recursos durante una hora y durante una semana? ¿Qué componentes seguirían generando cargos sin recibir tráfico? ¿Qué costo añade el secreto de RDS?

**Entregables:** política de IAM, archivos de Terraform, programa Python, comandos CLI, respuestas a preguntas, estimación de costos y evidencias de creación y eliminación.

**3. Amazon DocumentDB**

Compare DocumentDB con MongoDB e identifique al menos tres diferencias que podrían afectar una aplicación existente. Despliegue DocumentDB con una configuración de bajo costo. Compare una instancia aprovisionada con DocumentDB Serverless, disponible con una capacidad mínima configurable de 0,5 DCU, y justifique cuál resulta más económica para su región y tiempo de uso.

DocumentDB está dentro de una VPC y no ofrece conexión pública directa desde su computador. Prepare una instancia EC2 en la misma VPC y un túnel SSH. Configure los grupos de seguridad, TLS y el certificado necesarios. Compruebe la conexión desde MongoDB Compass y desde Python. Gestione la contraseña de DocumentDB con Secrets Manager y recupérela desde el programa.

Cree una base de datos y una colección, inserte al menos diez documentos y ejecute una búsqueda con filtro, una ordenación y una agregación. Todo esto usando Python.

**Preguntas de costos:** ¿Qué opción de DocumentDB cuesta menos para esta práctica? ¿Cuánto agrega la EC2 del túnel?

**Entregables:** respuestas a preguntas, cálculo de costos, diagrama de conexión(lo que se hizo para poder conectar DocumentDB a Compass), código, consultas, resultados y evidencias de eliminación.

**4. Amazon Neptune**

Compare Neptune con Neo4j en modelos de datos, lenguajes de consulta y herramientas. Despliegue Neptune con una configuración de bajo costo y justifique la elección entre capacidad aprovisionada y Serverless, si ambas están disponibles.

Investigue cómo consultar Neptune desde local. Compare un túnel SSH mediante EC2 con un punto de acceso público de Neptune, si la versión utilizada lo permite. Documente la VPC, las rutas, los grupos de seguridad y la autenticación de la opción elegida. ¿Es necesario este proceso con EC2? ¿Existe otra manera de realizar dicho proceso?

Cree un grafo con al menos diez vértices y quince relaciones. Inserte los datos y ejecute desde Python tres consultas que recorran relaciones.

**Preguntas de costos:** ¿Cuánto cuestan el cómputo y el almacenamiento? ¿Su método de conexión añade una instancia EC2? ¿Qué se sigue cobrando mientras no ejecuta consultas?

**Entregables:** respuestas a preguntas, modelo del grafo, arquitectura de acceso, costos, código, consultas, resultados y evidencias de eliminación.

**5. Amazon Redshift**

Investigue qué es Amazon Redshift, para qué tipo de análisis se utiliza y cuáles son sus principales componentes. Compare brevemente su propósito con el de Amazon RDS e indique un caso en el que elegiría cada servicio.

Despliegue Redshift con la configuración de menor costo adecuada para el taller. Investigue las opciones Serverless y aprovisionada, y justifique su elección según la región y el tiempo previsto de uso. Configure la contraseña de administración mediante AWS Secrets Manager.

Prepare un conjunto de datos con al menos dos tablas relacionadas. Desarrolle un programa en Python con Boto3 que suba los archivos a S3, cree las tablas en Redshift, cargue los datos mediante COPY y ejecute consultas con filtro, unión y agregación. Use la API de datos de Redshift para enviar las instrucciones SQL, comprobar que terminaron y recuperar sus resultados. El programa debe usar el secreto de Secrets Manager para autenticar las operaciones, sin incluir la contraseña en el código. Configure también el rol de IAM que permite a Redshift leer los archivos de S3.

Explique qué pregunta responde cada consulta e interprete los resultados. Puede usar Query Editor v2 para inspeccionar la base de datos. Si además decide conectarse desde su computador con un cliente SQL, documente la configuración de red y del grupo de seguridad necesaria.

**Preguntas de costos:** ¿Qué modalidad de Redshift cuesta menos para esta práctica? ¿Cómo se cobran el cómputo y el almacenamiento? ¿Qué recursos podrían seguir generando cargos después de ejecutar las consultas?

**Entregables:** respuestas a preguntas, conjunto de datos, instrucciones de carga, consultas SQL, resultados interpretados, comparación conceptual con RDS, estimación de costos y evidencias de eliminación de recursos

**6. AWS Glue Data Catalog**

Investigue qué almacena Glue Data Catalog y distinga los archivos de datos en S3 de los metadatos registrados en el catálogo. Explique la función de las bases de datos, tablas y *crawlers*.

Cargue en S3 un archivo CSV o JSON con al menos veinte registros. Cree una base de datos en Glue Data Catalog y un crawler para descubrirlo. Revise el esquema inferido y corrija los errores que encuentre. Consulte la tabla desde Athena con un filtro y una agrupación. Agregue registros, actualice el catálogo y verifique el resultado. Compare el crawler con la creación manual de la tabla.

Identifique si los recursos de este punto requieren alguna credencial de aplicación. Si utiliza una conexión que sí la requiere, guárdela en Secrets Manager, si trabaja únicamente con S3, Glue y Athena mediante permisos IAM, explique por qué no necesita crear otro secreto.

**Preguntas de costos:** ¿Qué se cobra por el crawler, el catálogo, S3 y las consultas de Athena? ¿Qué efecto tiene el volumen de datos examinados?

**Entregables:** respuestas a preguntas, datos, configuración, esquema, consultas, resultados, costos y evidencias de eliminación.
