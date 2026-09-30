# Punto 1 – AWS Secrets Manager

Un programa en Python recupera con Boto3 un secreto de prueba **en tiempo de ejecución**, sin contraseñas en el código. La identidad que lo ejecuta solo tiene permiso para leer **ese** secreto.

- Investigación y preguntas de costos: [consulta.md](consulta.md)
- Región: **us-east-2 (Ohio)**
- Identidad del programa: usuario IAM `user_cli` (perfil `default` de AWS CLI/Boto3)

## Archivos

| Archivo | Descripción |
|---|---|
| [leer_secreto.py](leer_secreto.py) | Programa que lee el secreto con `get_secret_value` y muestra identidad, versión y valores (la contraseña enmascarada) |
| [politica_acceso.json](politica_acceso.json) | Política IAM de mínimo privilegio: solo `secretsmanager:GetSecretValue` sobre el ARN del secreto |
| [evidencias/](evidencias/) | Capturas y salidas de cada paso |

## Cómo reproducirlo

### 1. Crear el secreto (consola, con una identidad administradora)
1. **Secrets Manager → Almacenar un secreto nuevo → Otro tipo de secreto**.
2. Pares clave/valor ficticios: `username` = `usuario_demo`, `password` = `ClaveFicticia123`.
3. Clave de cifrado: `aws/secretsmanager`. Nombre: `taller/punto1/demo`. Sin rotación.
4. Copiar el ARN, por ejemplo `arn:aws:secretsmanager:us-east-2:<cuenta>:secret:taller/punto1/demo-XXXXXX`.

### 2. Dar acceso de solo lectura a ese secreto
1. Asociar a `user_cli` la política [politica_acceso.json](politica_acceso.json), reemplazando el ARN por el del secreto.
2. Quitarle a `user_cli` cualquier política amplia de Secrets Manager (por ejemplo `SecretsManagerReadWrite`). Si no se quita, podría leer todos los secretos de la cuenta.

### 3. Configurar y ejecutar el programa
Desde la raíz del repositorio, con el entorno Conda `aws` del curso (o `pip install -r requirements.txt`):

```bash
cp .env.example .env          # contiene solo el NOMBRE del secreto: PUNTO1_SECRET_NAME=taller/punto1/demo
conda activate aws
python punto1_secrets_manager/leer_secreto.py
```

Para probar que el acceso está restringido, se pasa el nombre de otro secreto como argumento:

```bash
python punto1_secrets_manager/leer_secreto.py otro/secreto
```

### 4. Modificar el valor y volver a ejecutar
En la consola (identidad administradora): **secreto → Recuperar el valor del secreto → Editar**, se cambia `password` y se guarda. Se ejecuta de nuevo el mismo comando **sin cambiar el código**.

### 5. Eliminar el secreto
**Acciones → Eliminar secreto** con el período de espera mínimo (7 días). Por CLI, con una identidad administradora:

```bash
aws secretsmanager delete-secret --secret-id taller/punto1/demo --recovery-window-in-days 7
```

## Resultados

### Mínimo privilegio

| Prueba con `user_cli` | Resultado |
|---|---|
| `GetSecretValue` sobre `taller/punto1/demo` | ✅ Permitido |
| `GetSecretValue` sobre otro secreto (`eia/ingdata/secret`) | ❌ `AccessDeniedException` |
| `ListSecrets` | ❌ `AccessDeniedException` |
| `PutSecretValue` sobre `taller/punto1/demo` | ❌ `AccessDeniedException` |

El programa solo puede **leer** su secreto; no puede listar, leer otros ni modificarlo ([04_acceso_denegado.txt](evidencias/04_acceso_denegado.txt)).

### Actualización del secreto sin cambiar el código

| | Antes del cambio | Después del cambio |
|---|---|---|
| `VersionId` | `01c514e9-b04a-4b54-a147-cb35bcc8b510` | `b2b4d88a-74d9-438e-9ba7-4eee146a5183` |
| Etapa | `AWSCURRENT` | `AWSCURRENT` (la anterior pasó a `AWSPREVIOUS`) |
| Creada | 2026-09-30 17:25:11 -05 | 2026-09-30 18:01:49 -05 |
| Password (enmascarada) | `Cla*************` | `Nue**********` |

**¿Por qué el programa obtiene la versión actual sin cambiar el código?**
`leer_secreto.py` llama a `get_secret_value(SecretId=...)` sin indicar `VersionId` ni `VersionStage`, y en ese caso Secrets Manager devuelve la versión con la etiqueta **`AWSCURRENT`**. Al editar el valor, Secrets Manager no sobrescribe la versión existente:
1. Crea una **versión nueva** con su propio `VersionId`.
2. Le mueve la etiqueta `AWSCURRENT` a esa versión nueva.
3. Pasa la etiqueta `AWSPREVIOUS` a la versión que estaba vigente.

Como el programa pide el secreto en cada ejecución (no lo guarda en disco ni en el código), la siguiente ejecución recibe el valor nuevo automáticamente. Las capturas [06](evidencias/06_versiones_antes_del_cambio.png) y [08](evidencias/08_versiones_despues_del_cambio.png) muestran cómo se movieron las etiquetas.

### Eliminación
El secreto quedó **programado para eliminación** (ventana de 7 días). Desde ese momento ya no se puede leer, ni siquiera con el permiso correcto:

```
No se pudo leer el secreto: InvalidRequestException
You can't perform this operation on the secret because it was marked for deletion.
```

Un secreto programado para eliminación **no genera cobro**.

## Costos

Detalle de tarifas y preguntas en [consulta.md](consulta.md#6-preguntas-de-costos). Uso real de este punto:

| Concepto | Uso | Costo |
|---|---|---|
| Secreto `taller/punto1/demo` | ~50 min activo (22:17 → 23:05 UTC) × USD 0.40/mes | ≈ USD 0.0005 |
| Llamadas a la API | ~20 `GetSecretValue` × USD 0.05/10 000 | ≈ USD 0.0001 |
| **Total** | | **< USD 0.01**, y cubierto por la prueba gratuita de 30 días para secretos nuevos |

## Evidencias

| # | Archivo | Qué muestra |
|---|---|---|
| 01 | [01_secreto_creado.png](evidencias/01_secreto_creado.png) | Secreto `taller/punto1/demo` creado en us-east-2 |
| 02 | [02_permisos_user_cli.png](evidencias/02_permisos_user_cli.png) | `user_cli` con `Punto1LeerSecretoDemo` y sin `SecretsManagerReadWrite` |
| 03 | [03_politica_json.png](evidencias/03_politica_json.png) | JSON de la política de acceso |
| 04 | [04_acceso_denegado.txt](evidencias/04_acceso_denegado.txt) | Pruebas de mínimo privilegio (otro secreto, listar, modificar → denegado) |
| 05 | [05_lectura_version1.png](evidencias/05_lectura_version1.png) · [.txt](evidencias/05_lectura_version1.txt) | Lectura de la versión 1 |
| 06 | [06_versiones_antes_del_cambio.png](evidencias/06_versiones_antes_del_cambio.png) | Versiones antes de modificar el valor |
| 07 | [07_lectura_version2.png](evidencias/07_lectura_version2.png) · [.txt](evidencias/07_lectura_version2.txt) | Misma ejecución, sin cambiar código, leyendo la versión 2 |
| 08 | [08_versiones_despues_del_cambio.png](evidencias/08_versiones_despues_del_cambio.png) | Nueva versión `AWSCURRENT` y anterior `AWSPREVIOUS` |
| 09 | [09_lectura_tras_eliminacion.txt](evidencias/09_lectura_tras_eliminacion.txt) | El programa ya no puede leer el secreto eliminado |
| 10 | [10_secretos_eliminados_ohio.png](evidencias/10_secretos_eliminados_ohio.png) | Secretos de us-east-2 con su fecha de eliminación |
