# 🎓 Automatización Académica con n8n + Docker

Sistema de automatización de procesos académicos usando n8n, PostgreSQL, Adminer y Mailhog.
Automatiza asistencia, entregas de tareas y retroalimentación con 5 workflows y 15 tipos de nodos distintos.

---

## 📁 Estructura del Proyecto

```
academic-automation-n8n/
├── docker-compose.yml          ← Orquestación de servicios
├── .env                        ← Variables de entorno (NO subir a Git)
├── .env.example                ← Plantilla segura para control de versiones
├── init.sql                    ← Esquema BD + datos de prueba (auto-ejecutado)
├── shared/
│   ├── input/
│   │   ├── attendance_sample.csv   ← CSV de asistencia de ejemplo
│   │   └── submissions/            ← Carpeta de entregas de tareas
│   └── output/                     ← Reportes HTML generados aquí
└── workflows/
    ├── WF1_Procesamiento_Asistencia_CSV.json
    ├── WF2_Verificacion_Entregas_Tareas.json
    ├── WF3_Generacion_Reportes_Automaticos.json
    ├── WF4_Retroalimentacion_Notificaciones.json
    └── WF5_Error_Handler_Global.json
```

---

## 🐳 Requisitos Previos

| Herramienta | Versión mínima | Descarga |
|-------------|---------------|---------|
| Docker      | 24.x          | https://docs.docker.com/get-docker/ |
| Docker Compose | 2.x        | incluido con Docker Desktop |

> **No se necesita** Node.js, Python, ni nada más en el host.

---

## 🚀 Instalación y Arranque (5 pasos)

### Paso 1 — Clonar / descomprimir el proyecto

```bash
# Si tienes el ZIP, descomprime y entra al directorio:
cd academic-automation-n8n
```

### Paso 2 — Crear el archivo `.env`

```bash
# Copia la plantilla y edita con tus valores:
cp .env.example .env
```

Edita `.env` con un editor de texto. Los valores por defecto ya funcionan para pruebas locales.

> **IMPORTANTE para producción:** Cambia todas las contraseñas y genera
> una `N8N_ENCRYPTION_KEY` aleatoria de 32+ caracteres:
> ```bash
> openssl rand -base64 32
> ```

### Paso 3 — Crear carpetas de salida necesarias

```bash
mkdir -p shared/input/submissions shared/output
```

### Paso 4 — Levantar los contenedores

```bash
docker compose up -d
```

Espera ~30 segundos para que PostgreSQL y n8n inicialicen completamente.

Verifica que todos los servicios están corriendo:
```bash
docker compose ps
```

Deberías ver 4 servicios en estado `running`:
- `n8n_academic`
- `postgres_academic`
- `adminer_academic`
- `mailhog_academic`

### Paso 5 — Acceder a los servicios

| Servicio | URL | Usuario | Contraseña |
|----------|-----|---------|-----------|
| **n8n** (workflows) | http://localhost:5678 | `admin` | valor en `.env` |
| **Adminer** (BD) | http://localhost:8080 | `academic_user` | valor en `.env` |
| **Mailhog** (emails) | http://localhost:8025 | — | — |

---

## 🔌 Configurar Credenciales en n8n

**Este paso es obligatorio antes de importar los workflows.**

### A) Credencial PostgreSQL

1. En n8n → **Settings → Credentials → New Credential**
2. Busca **"PostgreSQL"**
3. Rellena:
   - **Name:** `PostgreSQL Academic DB`  ← EXACTAMENTE este nombre
   - **Host:** `postgres`
   - **Port:** `5432`
   - **Database:** `academic_db`
   - **User:** `academic_user`
   - **Password:** (valor de `POSTGRES_PASSWORD` en tu `.env`)
4. Haz clic en **"Test connection"** → debe aparecer ✅
5. Guarda.

### B) Credencial SMTP (Mailhog)

1. En n8n → **Settings → Credentials → New Credential**
2. Busca **"SMTP"**
3. Rellena:
   - **Name:** `SMTP Mailhog Local`  ← EXACTAMENTE este nombre
   - **Host:** `mailhog`
   - **Port:** `1025`
   - **SSL/TLS:** `None`
   - **Authentication:** desactivado / None
4. Guarda (no hay "Test" para SMTP sin auth, es normal).

---

## 📥 Importar los Workflows

1. En n8n → menú hamburger (☰) → **"Import from file"**
2. Importa los 5 archivos JSON en este orden:
   - `WF5_Error_Handler_Global.json` **primero** (lo referenciarán los demás)
   - `WF1_Procesamiento_Asistencia_CSV.json`
   - `WF2_Verificacion_Entregas_Tareas.json`
   - `WF3_Generacion_Reportes_Automaticos.json`
   - `WF4_Retroalimentacion_Notificaciones.json`

3. (**Opcional pero recomendado**) Configurar WF5 como error handler global:
   - Entra a WF1 → **Settings** (engranaje) → **"Error Workflow"** → selecciona **WF5**
   - Repite para WF2, WF3, WF4.

4. Activa los workflows que quieras con el toggle ⚡.

---

## 🧪 Probar los Workflows

### WF1 — Procesar CSV de Asistencia

Copia el CSV de muestra con el nombre exacto que lee el workflow:
```bash
cp shared/input/attendance_sample.csv shared/input/attendance_sample.csv
```

En n8n, abre **WF1** y haz clic en **"Test workflow"** (▶️).

**Resultado esperado:**
- Registros insertados en tabla `attendance`
- Archivo HTML generado en `shared/output/attendance_report_YYYY-MM-DD.html`
- Registro en tabla `reports`

### WF2 — Enviar Entrega de Tarea (webhook)

```bash
curl -X POST http://localhost:5678/webhook/task-submission \
  -H "Content-Type: application/json" \
  -d '{
    "student_id":    "STU099",
    "student_name":  "Test Estudiante",
    "task_id":       "TASK03",
    "task_name":     "Laboratorio de Prueba",
    "deadline":      "2020-01-01T23:59:00.000Z",
    "file_name":     "lab_test",
    "file_extension":"pdf",
    "student_email": "test@academico.local"
  }'
```

> La fecha `deadline` en 2020 fuerza una **entrega tardía** → ves el email en Mailhog (http://localhost:8025).

Para una entrega a tiempo, usa una fecha futura:
```bash
"deadline": "2099-12-31T23:59:00.000Z"
```

### WF3 — Generar Reporte Semanal

Abre **WF3** en n8n y haz clic en **"Test workflow"**.

**Resultado esperado:**
- `shared/output/full_report_YYYY-MM-DD.html` generado
- Email de notificación en Mailhog
- Registro en tabla `reports`

### WF4 — Enviar Retroalimentación (webhook)

```bash
# Nota baja → dispara alerta
curl -X POST http://localhost:5678/webhook/feedback \
  -H "Content-Type: application/json" \
  -d '{
    "student_id":    "STU001",
    "student_name":  "María García",
    "course_id":     "CS101",
    "task_id":       "TASK01",
    "grade":         45,
    "feedback_text": "Necesita mejorar la documentación y las pruebas unitarias.",
    "student_email": "maria@academico.local"
  }'

# Nota alta → sin alerta, email de felicitación
curl -X POST http://localhost:5678/webhook/feedback \
  -H "Content-Type: application/json" \
  -d '{
    "student_id":    "STU004",
    "student_name":  "Pedro Rodríguez",
    "course_id":     "CS101",
    "task_id":       "TASK01",
    "grade":         95,
    "feedback_text": "Excelente trabajo. Código limpio y bien documentado.",
    "student_email": "pedro@academico.local"
  }'
```

---

## 🗄️ Consultar la Base de Datos

Accede a **Adminer** en http://localhost:8080 con:
- Sistema: `PostgreSQL`
- Servidor: `postgres`
- Usuario: `academic_user`
- Contraseña: (de tu `.env`)
- Base de datos: `academic_db`

### Consultas útiles en psql

```bash
# Entrar al contenedor de PostgreSQL
docker exec -it postgres_academic psql -U academic_user -d academic_db
```

```sql
-- Ver resumen de asistencia
SELECT * FROM vw_attendance_summary;

-- Ver resumen de entregas
SELECT * FROM vw_task_summary;

-- Ver resumen de calificaciones
SELECT * FROM vw_grade_summary;

-- Ver errores recientes
SELECT * FROM error_logs ORDER BY created_at DESC LIMIT 20;

-- Ver notificaciones enviadas
SELECT * FROM notifications_log ORDER BY created_at DESC LIMIT 20;

-- Ver reportes generados
SELECT * FROM reports ORDER BY generated_at DESC;
```

---

## 📊 Descripción de los Workflows

### WF1 — Procesamiento de Asistencia CSV
**8 tipos de nodos** | Trigger: Manual + Horario (lun-vie 8am)

```
Manual/Schedule → Leer CSV → Parsear+Validar → IF(válido?)
  ✅ → Construir INSERT → PostgreSQL → Generar HTML → Guardar archivo → Log BD → Set Success
  ❌ → Preparar SQL Error → PostgreSQL error_logs → Set Error
```

**Nodos:** `manualTrigger`, `scheduleTrigger`, `readBinaryFile`, `code`, `if`, `postgres`, `writeBinaryFile`, `set`

---

### WF2 — Verificación de Entregas de Tareas
**8 tipos de nodos** | Trigger: Webhook POST `/webhook/task-submission`

```
Webhook → Validar → IF(formato OK?)
  ✅ → Construir SQL → PostgreSQL → IF(tarde?)
         🔴 → Email tardanza → Log notif → HTTP log → Responder
         🟢 → Set OK → HTTP log → Responder
  ❌ → Set error → Responder
```

**Nodos:** `webhook`, `code`, `if`, `postgres`, `emailSend`, `httpRequest`, `set`, `respondToWebhook`

---

### WF3 — Generación de Reportes Automáticos
**9 tipos de nodos** | Trigger: Manual + Semanal (lunes 7am)

```
Manual/Schedule → Init → ┬→ PG Attendance Stats ─┐
                          └→ PG Submission Stats ─┴→ Merge → Generar HTML
                                                           → Guardar → Log BD → Email → IF(datos?) → Set
```

**Nodos:** `manualTrigger`, `scheduleTrigger`, `code`, `postgres`, `merge`, `writeBinaryFile`, `emailSend`, `if`, `set`

---

### WF4 — Retroalimentación y Notificaciones
**8 tipos de nodos** | Trigger: Webhook POST `/webhook/feedback`

```
Webhook → Validar+SQL → IF(válido?)
  ✅ → Guardar BD → IF(nota < 60?)
         🔴 → Email alerta → Log BD → Preparar resp → Responder
         🟢 → Email positivo → Preparar resp → Responder
  ❌ → Set error → No-Op → Responder
```

**Nodos:** `webhook`, `code`, `if`, `postgres`, `emailSend`, `set`, `noOp`, `respondToWebhook`

---

### WF5 — Error Handler Global
**5 tipos de nodos** | Trigger: Error de otro workflow

```
ErrorTrigger → Formatear → PostgreSQL (log) → Email admin → Set final
```

**Nodos:** `errorTrigger`, `code`, `postgres`, `emailSend`, `set`

---

## 🔒 Buenas Prácticas de Seguridad Implementadas

| Práctica | Implementación |
|----------|---------------|
| Secretos en variables de entorno | Archivo `.env` nunca en Git |
| `.gitignore` obligatorio | Ver sección abajo |
| Contraseñas no hardcodeadas | Todas vía `${VARIABLE}` en docker-compose |
| Clave de cifrado n8n | `N8N_ENCRYPTION_KEY` en `.env` |
| Red interna Docker | Los servicios se comunican vía `academic_net`, sin exposición extra |
| Sanitización SQL | Función `safe()` en Code nodes escapa comillas simples |
| `continueOnFail` selectivo | Solo en nodos PostgreSQL críticos para no romper el flujo |
| Log de errores en BD | Tabla `error_logs` + WF5 Error Handler |

### `.gitignore` recomendado

```gitignore
.env
*.env
shared/output/
shared/input/submissions/
```

---

## 🛑 Detener y Limpiar

```bash
# Detener (mantiene datos)
docker compose stop

# Detener y eliminar contenedores (mantiene volúmenes)
docker compose down

# Eliminar TODO incluyendo datos en volúmenes
docker compose down -v
```

---

## 🐛 Solución de Problemas

| Problema | Solución |
|---------|---------|
| n8n no conecta a PostgreSQL | Espera 30s y verifica: `docker compose logs postgres` |
| Error "Credential not found" | Crea las credenciales con el nombre EXACTO indicado |
| WF1 no lee el CSV | Verifica que el archivo exista en `shared/input/attendance_sample.csv` |
| Emails no llegan | Abre Mailhog en http://localhost:8025 — los emails llegan ahí (no a Gmail) |
| Puerto 5678 ocupado | Cambia `N8N_PORT=5679` en `.env` |
| Puerto 5432 ocupado | Cambia `POSTGRES_PORT=5433` en `.env` |

### Ver logs en tiempo real

```bash
docker compose logs -f n8n       # logs de n8n
docker compose logs -f postgres  # logs de PostgreSQL
docker compose logs -f           # todos los servicios
```

---

## 📚 Referencias y Buenas Prácticas

- **n8n Docs:** https://docs.n8n.io
- **n8n Community:** https://community.n8n.io
- **Patrones ETL ligero:** verificar → transformar → cargar (VTL)
- **Principio de mínimo privilegio:** cada servicio solo accede a lo que necesita
- **Idempotencia:** `ON CONFLICT DO NOTHING` en inserts (WF1) evita duplicados
- **Observabilidad:** tabla `error_logs` + Mailhog para trazabilidad completa

---

*Proyecto generado para demostración de Automatización Académica con n8n 1.x + Docker*
