# TF-MVP-02 Telegram RRHH - Guía de Configuración en n8n

## Descripción General
Workflow MVP que integra Telegram como interfaz de consulta READ-ONLY para el equipo de RR.HH.

Permite consultar candidatos, vacantes y resultados sin capacidad de modificar datos.

## Configuración Inicial en n8n

### 1. Credencial de Telegram
- Obtener Bot Token de Telegram BotFather
- Configurar en n8n Credentials como "Telegram"

### 2. Webhook de Telegram
- n8n recibe mensajes de Telegram
- Procesa comandos y consulta PostgreSQL
- Responde con resultados

## Comandos Disponibles

### `/pendientes`
Lista candidatos con estado PENDIENTE_REVISION ordenados por prioridad

**Query PostgreSQL**:
```sql
SELECT 
  a.id,
  c.email,
  c.full_name,
  v.title,
  a.priority,
  a.applied_at,
  (SELECT total_score FROM talentflow.score_evaluations 
   WHERE application_id = a.id LIMIT 1) as score
FROM talentflow.applications a
JOIN talentflow.candidates c ON a.candidate_id = c.id
JOIN talentflow.vacancies v ON a.vacancy_id = v.id
WHERE a.status = 'PENDIENTE_REVISION'
ORDER BY 
  CASE a.priority 
    WHEN 'ALTA' THEN 1 
    WHEN 'MEDIA' THEN 2 
    WHEN 'BAJA' THEN 3 
  END,
  a.applied_at DESC
LIMIT 20
```

**Respuesta**:
```
Candidatos pendientes de revisión:

1️⃣ TF-2026-0001 | Backend Dev | ALTA (87/100) | Juan García
2️⃣ TF-2026-0002 | Frontend Dev | MEDIA (72/100) | María López
```

### `/candidato <TICKET>`
Muestra detalles completos de un candidato

**Query PostgreSQL** (Validación de ticket):
```sql
SELECT a.id, a.candidate_id, a.vacancy_id
FROM talentflow.applications a
WHERE EXISTS (
  SELECT 1 FROM talentflow.applications 
  WHERE id = a.id
) LIMIT 1
```

**Queries de Datos**:
```sql
-- Datos candidato
SELECT c.full_name, c.email, c.phone, c.location, 
       (SELECT created_at FROM talentflow.applications 
        WHERE id = $1 LIMIT 1) as applied_at
FROM talentflow.candidates c
WHERE c.id = (SELECT candidate_id FROM talentflow.applications WHERE id = $1)

-- Score
SELECT total_score, (
  SELECT array_agg(json_build_object('name', sc.name, 'points', scr.points_awarded, 'weight', sc.weight))
  FROM talentflow.score_criterion_results scr
  JOIN talentflow.scoring_criteria sc ON scr.scoring_criterion_id = sc.id
  WHERE scr.score_evaluation_id = se.id
) as criteria
FROM talentflow.score_evaluations se
WHERE se.application_id = $1
LIMIT 1

-- Análisis IA
SELECT structured_output 
FROM talentflow.ai_analyses 
WHERE application_id = $1 AND analysis_type = $2
ORDER BY created_at DESC LIMIT 1
```

**Respuesta**:
```
📋 Candidato TF-2026-0001

👤 Juan García
📧 juan@email.com
📱 +57 300 123 4567
📍 Bogotá, Colombia

Postulación: 14 ago 2026, 10:32 AM

Vacante: Backend Developer Junior
Experiencia: 3 años

🎯 Score: 87/100 (ALTA)

Criterios:
✅ Java (25/25)
✅ Spring Boot (20/20)
✅ SQL (15/15)
❌ REST API (0/15)
✅ Experiencia (7/15)

📝 Resumen:
Desarrollador backend con 3 años de experiencia...

❓ Preguntas sugeridas:
1. ¿Cómo utilizaste Java en Empresa X?
2. ¿Cuál es tu experiencia con Spring Boot?
3. ...
```

### `/vacante <NOMBRE_O_CODIGO>`
Estadísticas de una vacante

**Query PostgreSQL**:
```sql
SELECT 
  v.title,
  v.code,
  COUNT(a.id) as total_applicants,
  SUM(CASE WHEN a.priority = 'ALTA' THEN 1 ELSE 0 END) as alta,
  SUM(CASE WHEN a.priority = 'MEDIA' THEN 1 ELSE 0 END) as media,
  SUM(CASE WHEN a.priority = 'BAJA' THEN 1 ELSE 0 END) as baja,
  ROUND(AVG(COALESCE(se.total_score, 0))::numeric, 1) as score_promedio
FROM talentflow.vacancies v
LEFT JOIN talentflow.applications a ON v.id = a.vacancy_id
LEFT JOIN talentflow.score_evaluations se ON a.id = se.application_id
WHERE v.code ILIKE $1 OR v.title ILIKE $1
GROUP BY v.id, v.title, v.code
```

**Respuesta**:
```
💼 Vacante: Backend Developer Junior

Candidatos por prioridad:
🔴 ALTA: 3
🟡 MEDIA: 5
🟢 BAJA: 2
────────
Total: 10 candidatos

📊 Score promedio: 65/100
```

## Flujo del Workflow en n8n

### 1. Telegram Trigger
- **Nodo**: Telegram Trigger
- Escucha mensajes del chat
- Extrae comando y parámetros

### 2. Parse Comando
- **Nodo**: Code (JavaScript)
- Identifica comando y argumentos
- Valida formato

### 3. Ejecutar Comando
- **Nodo**: Switch (condicional)
- Ramifica según comando: `/pendientes`, `/candidato`, `/vacante`

### 4. Query PostgreSQL (Según Comando)
- **Nodo**: PostgreSQL
- Ejecuta query correspondiente
- Maneja errores silenciosamente

### 5. Formatear Respuesta
- **Nodo**: Code (JavaScript)
- Convierte datos en mensaje legible
- Agrega emojis y formato

### 6. Enviar Respuesta
- **Nodo**: Telegram
- Responde al usuario

### 7. Manejo de Errores
- Si comando no reconocido: "Comando no válido"
- Si no hay resultados: "No se encontraron candidatos"
- Si falla BD: "Error consultando base de datos"

## Respuestas a Solicitudes No Permitidas

```javascript
const responses = {
  "modificar": "Solo tengo permisos de consulta. Las modificaciones se hacen en el panel administrativo.",
  "cambiar estado": "No puedo cambiar estados. Usa el panel administrativo.",
  "eliminar": "No puedo eliminar información. Contacta a administración.",
  "off-topic": "Solo puedo ayudarte con consultas sobre candidatos y vacantes en TalentFlow."
};
```

## Credenciales Requeridas

1. **Telegram Bot Token**: De BotFather
2. **PostgreSQL**: Usuario `talentflow_bot_readonly` (READ-ONLY)

## Crear Usuario PostgreSQL Read-Only

```sql
-- Ejecutar como superusuario
CREATE ROLE talentflow_bot_readonly WITH LOGIN PASSWORD 'random_password';

GRANT USAGE ON SCHEMA talentflow TO talentflow_bot_readonly;

GRANT SELECT ON ALL TABLES IN SCHEMA talentflow TO talentflow_bot_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA talentflow GRANT SELECT ON TABLES TO talentflow_bot_readonly;

-- Denegar explícitamente operaciones de escritura
REVOKE INSERT, UPDATE, DELETE, DROP ON ALL TABLES IN SCHEMA talentflow FROM talentflow_bot_readonly;
```

## Seguridad

### Lo que SÍ puede hacer
- SELECT cualquier tabla de talentflow
- Leer datos públicos de candidatos
- Consultar scores y resultados

### Lo que NO puede hacer
- INSERT, UPDATE, DELETE
- Cambiar estados
- Modificar scores
- Recalcular análisis
- Acceder a credenciales o sistemas externos

## Configuración en n8n

1. **Crear workflow "TF-MVP-02 Telegram RRHH"**
2. **Agregar nodo Telegram Trigger**
   - Usar Bot Token guardado en Credentials
   - Configurar para recibir mensajes
3. **Agregar nodo Code para parsear comando**
4. **Agregar nodo Switch** con ramas para cada comando
5. **Agregar nodo PostgreSQL** para cada comando
6. **Agregar nodo Code** para formatear respuestas
7. **Agregar nodo Telegram** para enviar respuesta
8. **Activar workflow**

## Pruebas

1. Iniciar el bot en Telegram
2. Enviar `/pendientes`
3. Enviar `/candidato TF-2026-0001`
4. Enviar `/vacante Backend`
5. Intentar algo no permitido: "cambiar estado"

## Variables de Entorno

En `.env`:
```
TELEGRAM_BOT_TOKEN=1234567890:ABCDEfghijklmno...
POSTGRES_BOT_READONLY_USER=talentflow_bot_readonly
POSTGRES_BOT_READONLY_PASSWORD=...
```

## Notas Importantes

- Las queries son **pre-definidas** y parametrizadas
- No hay generación dinámica de SQL
- Respuestas lentas no rompen el flujo (timeout 30s)
- Los mensajes se guardan en el chat de Telegram indefinidamente
- El bot solo responde a comandos estructurados

## Mejoras Futuras (NO en MVP)

- Botones interactivos en Telegram
- Búsqueda libre de candidatos (con límite)
- Exportar resultados a PDF
- Notificaciones automáticas
- Historial de consultas
