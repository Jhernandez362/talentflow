# TF-MVP-01 Procesar candidatura - Guía de Configuración en n8n

## Descripción General
Workflow MVP que recibe una candidatura con CV, valida el PDF, extrae información, calcula score y guarda el resultado en PostgreSQL.

## Endpoint
```
POST /webhook/mvp/application
Content-Type: multipart/form-data
```

## Parámetros Esperados
```
- nombre (string, requerido)
- correo (string, requerido, válido como email)
- telefono (string)
- vacante (string, default: "BACKEND_JUNIOR")
- experiencia_declarada (number)
- habilidades_declaradas (string, comma-separated)
- cv (file, PDF, máximo 10MB)
```

## Flujo del Workflow

### 1. Webhook de Entrada
- **Nodo**: Webhook (HTTP Method: POST, Path: `mvp/application`)
- **Configuración**: Espera multipart/form-data

### 2. Validación de PDF
- **Nodo**: Code (JavaScript)
- **Validaciones**:
  - Archivo CV existe
  - MIME type es `application/pdf`
  - Tamaño < 10MB
  - Devuelve error `CV_NOT_READABLE` si falla

### 3. Extracción de Texto PDF
- **Nodo**: Code (JavaScript)
- **Función**: Extrae texto del PDF usando herramientas integradas
- **Salida**: Texto plano del CV

### 4. Obtener Vacante
- **Nodo**: PostgreSQL
- **Query**: 
  ```sql
  SELECT id, code, title FROM talentflow.vacancies 
  WHERE code = $1 LIMIT 1
  ```
- **Error**: Devuelve `VACANCY_NOT_FOUND` si no existe

### 5. Obtener Configuración de Scoring
- **Nodo**: PostgreSQL
- **Query**:
  ```sql
  SELECT id FROM talentflow.scoring_config_versions 
  WHERE vacancy_id = $1 ORDER BY created_at DESC LIMIT 1
  ```

### 6. IA-01: Extractor de CV
- **Nodo**: OpenAI (o proveedor configurado)
- **Modelo**: GPT-4o
- **Prompt**: PROMPT-IA-01-extractor.md
- **Entrada**: Texto del CV + datos formulario
- **Salida**: JSON con estructura:
  ```json
  {
    "experiencia_anios": number,
    "experiencias": [...],
    "habilidades": [...],
    "educacion": [...],
    "cursos": [...],
    "certificaciones": [...]
  }
  ```

### 7. Generar Número de Ticket
- **Nodo**: PostgreSQL
- **Query**:
  ```sql
  SELECT COALESCE(MAX(CAST(SUBSTRING(ticket FROM 9) AS INTEGER)), 0) + 1 AS next_seq 
  FROM talentflow.applications
  ```
- **Formato**: `TF-2026-{NNNN}`

### 8. Calcular Score (Motor JavaScript)
- **Nodo**: Code (JavaScript)
- **Entrada**: candidate_data (IA-01), scoring_criteria
- **Lógica**:
  ```javascript
  // Para cada tecnología:
  // - Si evidencia_laboral: peso completo
  // - Si no: 0 puntos
  
  // Para experiencia:
  // puntos = min(experiencia_candidato / experiencia_requerida, 1) * peso
  
  // Determinar prioridad:
  // 80-100: ALTA
  // 60-79: MEDIA
  // 0-59: BAJA
  ```
- **Salida**:
  ```json
  {
    "score": 87,
    "prioridad": "ALTA",
    "criterios": [...]
  }
  ```

### 9. IA-02: Generar Resumen
- **Nodo**: OpenAI
- **Modelo**: GPT-4o
- **Prompt**: PROMPT-IA-02-resumen.md
- **Entrada**: candidate_data, score, vacancy
- **Salida**:
  ```json
  {
    "resumen": "Texto del resumen profesional..."
  }
  ```

### 10. IA-03: Generar Preguntas
- **Nodo**: OpenAI
- **Modelo**: GPT-4o
- **Prompt**: PROMPT-IA-03-preguntas.md
- **Entrada**: experiencias, habilidades, requisitos vacante
- **Salida**:
  ```json
  {
    "preguntas": [
      {
        "tema": "Nombre tema",
        "pregunta": "Texto de la pregunta"
      }
    ]
  }
  ```

### 11. Guardar Candidato
- **Nodo**: PostgreSQL
- **Query**:
  ```sql
  INSERT INTO talentflow.candidates 
  (email, full_name, phone, location, consent_at) 
  VALUES ($1, $2, $3, $4, now()) 
  ON CONFLICT (email) DO UPDATE SET updated_at = now() 
  RETURNING id
  ```

### 12. Guardar Aplicación
- **Nodo**: PostgreSQL
- **Query**:
  ```sql
  INSERT INTO talentflow.applications 
  (vacancy_id, candidate_id, status, priority, source) 
  VALUES ($1, $2, 'PENDIENTE_REVISION', $3, 'WEB') 
  ON CONFLICT (vacancy_id, candidate_id) 
  DO UPDATE SET status = 'PENDIENTE_REVISION' 
  RETURNING id
  ```

### 13. Guardar Análisis IA
- **Nodo**: PostgreSQL
- **Inserts 3 registros** en `talentflow.ai_analyses`:
  - CV_EXTRACTION (IA-01)
  - PROFESSIONAL_SUMMARY (IA-02)
  - INTERVIEW_QUESTIONS (IA-03)

### 14. Guardar Score
- **Nodo**: PostgreSQL
- **Query**:
  ```sql
  INSERT INTO talentflow.score_evaluations 
  (application_id, vacancy_id, scoring_config_version_id, total_score, algorithm_version) 
  VALUES ($1, $2, $3, $4, 'MVP-v1')
  ```

### 15. Guardar Desglose de Criterios
- **Nodo**: PostgreSQL
- **Inserts múltiples registros** en `talentflow.score_criterion_results`
  - Un registro por cada criterio evaluado

### 16. Response Éxito
- **Nodo**: Respond to Webhook
- **Response**:
  ```json
  {
    "success": true,
    "ticket": "TF-2026-0001",
    "message": "Tu postulación fue registrada correctamente."
  }
  ```

## Manejo de Errores

### Error Paths

1. **CV no proporcionado** → `CV_NOT_PROVIDED`
2. **Formato no PDF** → `CV_INVALID_FORMAT`
3. **No se puede leer PDF** → `CV_NOT_READABLE`
4. **Vacante no existe** → `VACANCY_NOT_FOUND`
5. **Fallo en IA** → `PROCESSING_ERROR`

Todos devuelven respuesta HTTP 400 o 500 según corresponda.

## Credenciales Requeridas

1. **PostgreSQL**: Conecta con usuario `talentflow_app` (configurado en .env)
2. **OpenAI**: API Key debe estar en n8n Credentials

## Configuración en n8n

1. Crear nuevo workflow
2. Copiar estructura del flujo anterior
3. Configurar Webhook con ruta `/mvp/application`
4. Configurar credenciales PostgreSQL y OpenAI
5. Activar workflow
6. Probar con `curl` o Postman

## URLs de Prueba (Local)

```bash
# Test básico sin archivo
curl -X POST http://localhost:5678/webhook/tf-mvp-application \
  -F "nombre=Juan García" \
  -F "correo=juan@example.com" \
  -F "telefono=+573001234567" \
  -F "vacante=BACKEND_JUNIOR" \
  -F "experiencia_declarada=3" \
  -F "habilidades_declaradas=Java,Spring Boot,SQL" \
  -F "cv=@curriculum.pdf"
```

## Variables de Entorno Necesarias

En `.env`:
```
OPENAI_API_KEY=sk-...
N8N_HOST=n8n
N8N_PORT=5678
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=talentflow
POSTGRES_USER=talentflow_app
POSTGRES_PASSWORD=...
```

## Notas Importantes

- El workflow es ASINCRÓNICO: procesa todo antes de responder
- El PDF debe ser legible (no escaneado sin OCR)
- La vacante debe existir en PostgreSQL antes de aplicar
- Las credenciales IA deben estar configuradas en n8n
