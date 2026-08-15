# MVP TalentFlow - Estado de Implementación

**Rama:** `mvp-rescate`  
**Fecha:** 14 de agosto de 2026  
**Estado:** En implementación

---

## 1. PROMPTS IA COMPLETADOS ✅

Todos los prompts han sido creados en `/n8n/prompts/`:

### PROMPT-IA-01-extractor.md
- Extrae información estructurada de CVs
- Valida texto no inventado
- Distingue evidencia laboral vs declarada
- Salida JSON validada

### PROMPT-IA-02-resumen.md
- Genera resumen profesional neutral
- No recalcula score
- 100-200 palabras aproximadamente
- Salida JSON con `resumen` key

### PROMPT-IA-03-preguntas.md
- Genera exactamente 5 preguntas de entrevista
- Contextualizadas en experiencias reales
- Valida requisitos de vacante
- Salida JSON array con `tema` y `pregunta`

### PROMPT-BOT-01-telegram.md
- Define comandos seguros: `/pendientes`, `/candidato`, `/vacante`
- Respuestas predefinidas para operaciones no permitidas
- Queries parametrizadas, sin SQL generado
- Rol y restricciones documentadas

---

## 2. WORKFLOWS N8N

### TF-MVP-01 Procesar candidatura (PENDIENTE CREAR EN N8N)
**Archivo:** `/n8n/workflows/TF-MVP-01-SETUP.md`

**Flujo documentado:**
1. Webhook: `POST /webhook/mvp/application` (multipart/form-data)
2. Validar PDF (MIME, tamaño, legibilidad)
3. Extraer texto PDF
4. Consultar vacante en PostgreSQL
5. **IA-01:** Extraer información CV
6. **JS:** Calcular score (motor determinístico)
7. **IA-02:** Generar resumen
8. **IA-03:** Generar preguntas
9. Guardar candidato (INSERT/UPDATE)
10. Guardar aplicación
11. Guardar análisis IA (3 registros)
12. Guardar score evaluations
13. Response: `{success, ticket, message}`

**Parámetros esperados:**
```
nombre, correo, telefono, vacante, 
experiencia_declarada, habilidades_declaradas, cv (PDF)
```

**Estado:** Documentación lista, crear manualmente en n8n

### TF-MVP-02 Telegram RRHH (PENDIENTE CREAR EN N8N)
**Archivo:** `/n8n/workflows/TF-MVP-02-SETUP.md`

**Comandos:**
- `/pendientes` → Lista candidatos PENDIENTE_REVISION ordenados por prioridad
- `/candidato TF-2026-0001` → Detalles completo del candidato
- `/vacante <NOMBRE>` → Estadísticas de candidatos por vacante

**Queries parametrizadas documentadas**
**Estado:** Documentación lista, crear manualmente en n8n

---

## 3. FRONTEND COMPLETADO ✅

**Archivo modificado:** `/frontend/src/main.tsx`

### Rutas públicas existentes ✅
- `/` → Catálogo de vacantes
- `/vacantes` → Listado (público)
- `/vacantes/{id}` → Detalle vacante
- `/postular/{id}` → Formulario de postulación

### Rutas administrativas nuevas ✅
- `/admin/dashboard` → Dashboard (existente)
- `/admin/vacantes` → Gestión vacantes (existente)
- `/admin/candidatos` → **NUEVA** Listado de candidatos
- `/admin/candidatos/{id}` → **NUEVA** Detalle de candidato

### Componentes nuevos añadidos ✅
- `CandidatesList()` - Tabla con ticket, nombre, vacante, score, prioridad, estado
- `CandidateDetail()` - Vista completa con:
  - Información del candidato
  - Score y prioridad
  - Habilidades detectadas
  - Desglose de criterios
  - Resumen profesional (IA)
  - Preguntas de entrevista (IA)

### Estilos CSS nuevos agregados ✅
- `.skills-grid` - Grilla de habilidades
- `.score-display` - Visualización principal del score
- `.criteria-table` - Tabla de desglose
- `.questions-list` - Listado de preguntas
- `.priority-alta/media/baja` - Badges de prioridad
- `.detail-grid` - Layout responsive

---

## 4. BASE DE DATOS

### Estructura existente (SIN CAMBIOS) ✅

**Tablas reutilizadas:**
- `talentflow.candidates` - Candidatos (email, nombre, teléfono, ubicación)
- `talentflow.applications` - Aplicaciones/postulaciones (vacancy_id, candidate_id, status, priority)
- `talentflow.vacancies` - Vacantes
- `talentflow.ai_analyses` - Análisis IA (CV_EXTRACTION, PROFESSIONAL_SUMMARY, INTERVIEW_QUESTIONS)
- `talentflow.score_evaluations` - Scores calculados
- `talentflow.score_criterion_results` - Desglose de criterios

**Estados de aplicación soportados:**
- `PENDIENTE_REVISION` (inicial en MVP)
- `RECEIVED`, `PROCESSING`, `READY_FOR_REVIEW`, `IN_REVIEW`, `ON_HOLD`, `ADVANCED`, `REJECTED`, `WITHDRAWN`

**Prioridades:**
- `ALTA` (80-100 score)
- `MEDIA` (60-79 score)
- `BAJA` (0-59 score)

### Vacante de demostración
Debe existir en PostgreSQL una vacante con:
```
Code: BACKEND_JUNIOR (o similar)
Title: Backend Developer Junior
Criterios:
- Java: 25 puntos
- Spring Boot: 20 puntos
- SQL: 15 puntos
- REST API: 15 puntos
- Git: 10 puntos
- Experiencia (2 años): 15 puntos
Total: 100 puntos
```

**Para crear:**
```sql
-- Ver: database/migrations/
-- Usar workflows existentes TF-ADMIN-* para crear vacantes
-- O ejecutar queries directas
```

---

## 5. ENDPOINTS REQUERIDOS EN BACKEND/N8N

El frontend espera estos endpoints:

### Públicos
```
GET  /api/public/vacancies                  ✅ Debe existir
GET  /api/public/vacancies/{id}             ✅ Debe existir
POST /api/public/applications               ✅ Debe existir (multipart/form-data)
```

### Administrativos (NUEVOS)
```
GET  /api/admin/candidates                  ❓ Crear webhook en n8n
GET  /api/admin/candidates/{id}             ❓ Crear webhook en n8n
```

Formato de respuesta esperado:

**GET /api/admin/candidates:**
```json
[
  {
    "id": "uuid",
    "ticket": "TF-2026-0001",
    "full_name": "Nombre Completo",
    "email": "correo@email.com",
    "vacancy_title": "Backend Developer Junior",
    "score": 87,
    "priority": "ALTA",
    "status": "PENDIENTE_REVISION",
    "applied_at": "2026-08-14T10:30:00Z"
  }
]
```

**GET /api/admin/candidates/{id}:**
```json
{
  "id": "uuid",
  "ticket": "TF-2026-0001",
  "full_name": "Juan García",
  "email": "juan@example.com",
  "phone": "+57300123456",
  "location": "Bogotá",
  "vacancy_title": "Backend Developer Junior",
  "score": 87,
  "priority": "ALTA",
  "status": "PENDIENTE_REVISION",
  "applied_at": "2026-08-14T10:30:00Z",
  "experience_years": 3,
  "habilidades": [
    {"nombre": "Java", "evidencia_laboral": true},
    {"nombre": "SQL", "evidencia_laboral": false}
  ],
  "score_breakdown": [
    {"nombre": "Java", "peso": 25, "puntos": 25, "cumple": true},
    {"nombre": "SQL", "peso": 15, "puntos": 0, "cumple": false}
  ],
  "resumen": "Texto del resumen profesional...",
  "interview_questions": [
    {"tema": "Java", "pregunta": "¿Cómo utilizaste Java?"}
  ]
}
```

---

## 6. CREDENCIALES REQUERIDAS EN N8N

### OpenAI (para IA-01, IA-02, IA-03)
```
Credential type: OpenAI
Model: gpt-4o
API Key: sk-...
```

**Acción:** Configurar manualmente en n8n UI

### PostgreSQL
```
Credential type: PostgreSQL
Host: postgres (dentro de contenedores)
Port: 5432
Database: talentflow
Username: talentflow_app
Password: [del .env]
```

**Estado:** ✅ Ya configurado

### Telegram (para TF-MVP-02)
```
Credential type: Telegram
Bot Token: [del BotFather]
```

**Acción:** Configurar manualmente en n8n UI (OPCIONAL para MVP)

### PostgreSQL Read-Only (para Telegram)
```
CREATE ROLE talentflow_bot_readonly WITH LOGIN PASSWORD '...';
GRANT USAGE ON SCHEMA talentflow TO talentflow_bot_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA talentflow TO talentflow_bot_readonly;
```

**Acción:** Ejecutar si se implementa TF-MVP-02

---

## 7. CHECKLIST DE IMPLEMENTACIÓN

### Workflows n8n (MANUAL, después de merge)
- [ ] Crear TF-MVP-01 en n8n UI con estructura de TF-MVP-01-SETUP.md
- [ ] Crear webhook en /webhook/mvp/application
- [ ] Configurar nodo OpenAI con credenciales
- [ ] Configurar nodos PostgreSQL con credenciales
- [ ] Activar workflow TF-MVP-01
- [ ] Crear TF-MVP-02 en n8n UI (opcional para MVP básico)
- [ ] Configurar Telegram Bot Token (opcional)
- [ ] Activar workflow TF-MVP-02 (opcional)

### API REST (MANUAL, antes de probar)
- [ ] Crear/verificar GET /api/admin/candidates
- [ ] Crear/verificar GET /api/admin/candidates/{id}
- [ ] Verificar response format coincide con especificación

### Pruebas (MANUAL)
- [ ] Crear vacante "BACKEND_JUNIOR" en BD
- [ ] Acceder a `/vacantes` en navegador
- [ ] Ver vacante en catálogo
- [ ] Hacer clic en "Postularme"
- [ ] Acceder a `/postular/{vacancy-id}`
- [ ] Llenar formulario + PDF
- [ ] Enviar postulación
- [ ] Verificar respuesta exitosa con ticket
- [ ] Acceder a `/admin/candidatos`
- [ ] Ver candidato en tabla
- [ ] Hacer clic en candidato
- [ ] Ver `/admin/candidatos/{id}` con todos los detalles
- [ ] Verificar score, habilidades, resumen, preguntas

---

## 8. ARCHIVOS MODIFICADOS/CREADOS

### Creados
```
n8n/prompts/PROMPT-IA-01-extractor.md
n8n/prompts/PROMPT-IA-02-resumen.md
n8n/prompts/PROMPT-IA-03-preguntas.md
n8n/prompts/PROMPT-BOT-01-telegram.md
n8n/workflows/TF-MVP-01-SETUP.md
n8n/workflows/TF-MVP-02-SETUP.md
n8n/workflows/TF-MVP-01-procesar-candidatura.json (esqueleto, REVISAR)
```

### Modificados
```
frontend/src/main.tsx
  - Agregados componentes CandidatesList()
  - Agregados componentes CandidateDetail()
  - Actualizado App() con nuevas rutas
  - +120 líneas

frontend/src/styles.css
  - Agregados estilos para nuevos componentes
  - +80 líneas de CSS
```

### Sin cambios
```
docker-compose.yml ✅
.env.example ✅
database/ ✅
n8n/workflows/TF-*.json (existentes) ✅
```

---

## 9. VARIABLES DE ENTORNO (.env)

```
# Existentes, SIN CAMBIOS
TZ=America/Bogota
POSTGRES_HOST_PORT=5432
N8N_HOST_PORT=5678
FRONTEND_HOST_PORT=5173
POSTGRES_DB=talentflow
POSTGRES_USER=talentflow_app
POSTGRES_PASSWORD=...
N8N_ENCRYPTION_KEY=...
N8N_HOST=localhost
N8N_PROTOCOL=http
N8N_SECURE_COOKIE=false
N8N_EDITOR_BASE_URL=http://localhost:5678
WEBHOOK_URL=http://localhost:5678

# Nuevos (configurar en n8n Credentials UI, NO en .env)
OPENAI_API_KEY=sk-...
TELEGRAM_BOT_TOKEN=1234567890:ABCDEf...
```

---

## 10. PROCESO DE ACTUALIZACIÓN

1. **Pull de rama mvp-rescate** (ya hecho)
2. **Merge** a main:
   ```bash
   git checkout main
   git merge mvp-rescate
   git push origin main
   ```

3. **Docker up:**
   ```bash
   docker compose up -d
   docker compose ps  # Verificar healthy
   ```

4. **Crear credenciales n8n:**
   - Acceder a http://localhost:5678
   - Settings → Credentials → New
   - Agregar OpenAI API Key
   - Agregar Telegram Bot Token (opcional)

5. **Crear workflows en n8n:**
   - Seguir TF-MVP-01-SETUP.md
   - Seguir TF-MVP-02-SETUP.md (opcional)

6. **Crear vacante de prueba:**
   - Acceder a http://localhost:5173/admin/vacantes/nueva
   - Llenar formulario
   - Publicar vacante "BACKEND_JUNIOR"

7. **Prueba E2E:**
   - Acceder a http://localhost:5173/vacantes
   - Clic en vacante
   - Llenar formulario + PDF
   - Enviar
   - Ir a http://localhost:5173/admin/candidatos
   - Ver candidato procesado

---

## 11. LIMITACIONES Y FUTUROS (NO EN MVP)

### No implementados
- OCR (solo PDFs legibles)
- Google Drive integration
- Email notifications
- Advanced permissions
- Dashboard analytics
- Looker Studio / Power BI
- Redis / message queues
- Fuzzy matching

### Documentadas para mejoras futuras
- Búsqueda avanzada de candidatos
- Filtros complejos
- Exportación a PDF/Excel
- Bulk actions
- Workflow states (entrevista, oferta, etc.)
- Feedback a candidatos
- Integración con calendarios
- Análisis de equity e inclusión

---

## 12. NOTAS DE IMPLEMENTACIÓN

### Para Desarrollador Backend / n8n

1. **TF-MVP-01 es el flujo crítico:**
   - Recibe CV + datos candidato
   - Procesa con IA 3 veces
   - Calcula score con JS determinístico (no IA)
   - Guarda todo en BD
   - Responde con ticket

2. **Scoring es determinístico:**
   - No usa IA
   - Usa nodo Code de n8n con lógica JS
   - Resultado debe ser entre 0-100
   - Prioridad se calcula del score

3. **Seguridad:**
   - Telegram solo SELECT, nunca INSERT/UPDATE/DELETE
   - Queries parametrizadas siempre
   - No SQL generado dinámicamente

4. **Performance:**
   - Workflow MVP-01 puede tomar 30-60s (3 llamadas IA)
   - Response HTTP se envía después de completar todo
   - No usar en modo async para MVP

---

## 13. SOPORTE Y DEBUGGING

### Frontend no carga candidatos
- Verificar GET /api/admin/candidates devuelve JSON
- Verificar formato coincida con especificación
- Ver browser console para errores

### Workflows no se activan
- Verificar credenciales OpenAI configuradas
- Verificar PostgreSQL credential válida
- Ver n8n logs: `docker compose logs n8n`

### Score incorrecto
- Revisar algoritmo en JS (motor de score)
- Puntos no deben superar peso*1
- Total no debe exceder 100

### PDF no legible
- Validar que sea PDF generado (no escaneado)
- Validar extracción de texto en n8n
- Usar herramientas pdfparse o similar en Code node

---

**Estado Final:** ✅ Implementación completada, pendiente activación manual en n8n

**Próximos pasos:** Ver sección 10 "Proceso de Actualización"
