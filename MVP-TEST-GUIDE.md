# MVP TalentFlow - Guía de Prueba E2E

## 1. PREPARACIÓN PREVIA

### 1.1 Verificar estado de contenedores
```bash
cd talentflow
docker compose ps
# Esperado: 3 servicios en estado "healthy"
# - postgres (healthy)
# - n8n (healthy)
# - frontend (healthy)
```

Si algo no está healthy:
```bash
docker compose logs postgres
docker compose logs n8n
docker compose logs frontend
```

### 1.2 Crear vacante de prueba
Acceder a: `http://localhost:5173/admin/vacantes/nueva`

**Datos a ingresar:**

**Paso 1: Información General**
- Nombre: `Backend Developer Junior`
- Código: `BACKEND_JUNIOR`
- Área: `Tecnología`
- Modalidad: `Remoto`
- Descripción: `Desarrollador backend junior para equipo de APIs REST`
- Ubicación: `Remoto / Colombia`
- Tipo de contrato: `Contrato fijo`
- Nivel: `Junior`
- Plazas: `3`
- Salario min: `2000000` COP
- Salario max: `3500000` COP
- Mostrar salario: ✓ (checked)
- Fecha de cierre: [Fecha en 30 días]

**Paso 2: Perfil Requerido**
- Experiencia mínima: `24` meses (2 años)
- Educación mínima: `PROFESSIONAL`

**Paso 3: Scoring**
Crear exactamente estos criterios (total = 100):

| Criterio | Tipo | Peso | Obligatorio |
|----------|------|------|-------------|
| Java | TECNOLOGIA | 25 | ✓ |
| Spring Boot | TECNOLOGIA | 20 | ✓ |
| SQL | TECNOLOGIA | 15 | ✗ |
| REST API | TECNOLOGIA | 15 | ✗ |
| Git | TECNOLOGIA | 10 | ✗ |
| Experiencia | EXPERIENCIA | 15 | ✓ |

**Paso 4: Deseables y Valor Agregado**
Agregar deseables (no afecta score):
- Docker
- Kubernetes
- AWS

**Paso 5-6:** Preview y Publicar

Debería aparecer un mensaje: "Vacante publicada correctamente"

---

## 2. CREAR WORKFLOWS N8N (MANUAL)

### 2.1 Crear TF-MVP-01 Procesar candidatura

1. Acceder a `http://localhost:5678`
2. Crear nuevo workflow
3. Nombrar: `TF-MVP-01 Procesar candidatura`
4. Agregar nodo **Webhook**:
   - HTTP Method: `POST`
   - Path: `mvp/application`
   - Response Mode: `responseNode`

5. Agregar nodo **Code** (validar PDF):
   ```javascript
   const cv = $input.all()[0].binary.cv;
   if (!cv || !cv[0]) {
     return { valid: false };
   }
   const file = cv[0];
   if (file.mimeType !== 'application/pdf') {
     return { valid: false };
   }
   if (file.data.length > 10485760) { // 10MB
     return { valid: false };
   }
   return { valid: true };
   ```

6. Agregar nodo **PostgreSQL**:
   - Operation: `executeQuery`
   - Query: `SELECT id, code, title FROM talentflow.vacancies WHERE code = $1 LIMIT 1`
   - Params: `[{{ $json.body.vacante }}]`

7. Agregar nodo **OpenAI** (IA-01):
   - Model: `gpt-4o`
   - Prompt: Leer archivo `n8n/prompts/PROMPT-IA-01-extractor.md`
   - Usar variables disponibles del workflow

8. Agregar nodo **Code** (Calcular Score):
   ```javascript
   // Ver TF-MVP-01-SETUP.md sección 8
   // Implementar lógica de scoring
   ```

9. Agregar nodo **OpenAI** (IA-02):
   - Model: `gpt-4o`
   - Prompt: Leer archivo `n8n/prompts/PROMPT-IA-02-resumen.md`

10. Agregar nodo **OpenAI** (IA-03):
    - Model: `gpt-4o`
    - Prompt: Leer archivo `n8n/prompts/PROMPT-IA-03-preguntas.md`

11. Agregar nodo **PostgreSQL** (guardar candidato)
12. Agregar nodo **PostgreSQL** (guardar aplicación)
13. Agregar nodo **PostgreSQL** (guardar análisis IA)
14. Agregar nodo **PostgreSQL** (guardar score)

15. Agregar nodo **Respond to Webhook**:
    ```json
    {
      "success": true,
      "ticket": "TF-2026-0001",
      "message": "Tu postulación fue registrada correctamente."
    }
    ```

16. Conectar nodos en secuencia
17. Activar workflow

**⚠️ NOTA IMPORTANTE:** El archivo JSON `TF-MVP-01-procesar-candidatura.json` es un esqueleto y DEBE ser revisado manualmente para asegurar que la sintaxis es correcta en n8n. Consultar `TF-MVP-01-SETUP.md` para la estructura exacta.

---

## 3. CREAR CV DE PRUEBA

Crear un archivo `test-cv.txt` con este contenido (convertir a PDF):

```
CURRICULUM VITAE

Juan García López
juan.garcia@example.com
+57 300 123 4567
Bogotá, Colombia

EXPERIENCIA LABORAL

Junior Developer - TechCorp (2023 - Presente) [1 año, 8 meses]
  - Desarrollo de APIs REST usando Java y Spring Boot
  - Escritura y optimización de queries SQL
  - Control de versiones con Git
  - Testing con JUnit

Backend Developer - DataSystems (2021 - 2023) [2 años]
  - APIs REST con Java
  - Diseño de bases de datos SQL
  - Git para versionado
  - Integración con AWS (no mucho)

HABILIDADES TÉCNICAS
- Java (avanzado)
- Spring Boot (intermedio-avanzado)
- SQL (avanzado)
- REST APIs (avanzado)
- Git (básico-intermedio)
- Linux (básico)
- PostgreSQL (avanzado)
- MySQL (intermedio)

EDUCACIÓN
- Licenciatura en Ingeniería de Sistemas
  Universidad Nacional de Colombia (2021)

CERTIFICACIONES
- Certified Associate Java Programmer (2022)
- AWS Fundamentals (2023)

IDIOMAS
- Español: Nativo
- Inglés: Intermedio
```

**Convertir a PDF:**
- Copiar a Word/Google Docs
- Guardar como PDF
- Nombrar: `juan-garcia-cv.pdf`

---

## 4. PRUEBA: ENVIAR POSTULACIÓN

### 4.1 Mediante navegador (recomendado para MVP)

1. Acceder a `http://localhost:5173/vacantes`
2. Ver tarjeta de "Backend Developer Junior"
3. Clic en "Ver detalle"
4. Clic en "Postularme"
5. Llenar formulario:
   - Nombre: `Juan García López`
   - Correo: `juan.garcia@example.com`
   - Teléfono: `+57 300 123 4567`
   - Años de experiencia: `3`
   - Tecnologías principales: `Java, Spring Boot, SQL, REST API, Git`
   - Adjuntar: `juan-garcia-cv.pdf`
   - Aceptar términos: ✓

6. Clic en "Enviar postulación"
7. **Esperar 30-60 segundos** (procesamiento IA)
8. Debe aparecer:
   ```
   ✓ Tu postulación fue registrada correctamente.
   Ticket: TF-2026-XXXX
   ```

### 4.2 Mediante curl (para debugging)

```bash
curl -X POST http://localhost:5678/webhook/mvp/application \
  -F "nombre=Juan García" \
  -F "correo=juan@example.com" \
  -F "telefono=+573001234567" \
  -F "vacante=BACKEND_JUNIOR" \
  -F "experiencia_declarada=3" \
  -F "habilidades_declaradas=Java,Spring Boot,SQL" \
  -F "cv=@juan-garcia-cv.pdf"
```

**Respuesta esperada:**
```json
{
  "success": true,
  "ticket": "TF-2026-0001",
  "message": "Tu postulación fue registrada correctamente."
}
```

---

## 5. VERIFICAR EN PANEL ADMINISTRATIVO

1. Acceder a `http://localhost:5173/admin/candidatos`
2. Debe aparecer candidato en tabla:
   - Ticket: `TF-2026-0001`
   - Nombre: `Juan García López`
   - Vacante: `Backend Developer Junior`
   - Score: `87` (aproximadamente, según algoritmo)
   - Prioridad: `ALTA`
   - Estado: `PENDIENTE_REVISION`

3. Clic en el candidato
4. Debe mostrar página `/admin/candidatos/{id}` con:
   - ✅ Información del candidato
   - ✅ Score: 87/100
   - ✅ Habilidades detectadas: Java, Spring Boot, SQL, etc.
   - ✅ Desglose de criterios:
     ```
     Java: 25/25 ✓
     Spring Boot: 20/20 ✓
     SQL: 15/15 ✓
     REST API: 15/15 ✓
     Git: 10/10 ✓
     Experiencia: 7/15 ✓
     ```
   - ✅ Resumen profesional (texto generado por IA-02)
   - ✅ Preguntas de entrevista (5 preguntas generadas por IA-03)

---

## 6. VERIFICAR EN BASE DE DATOS (OPCIONAL)

Conectar a PostgreSQL:
```bash
psql -h localhost -U talentflow_app -d talentflow
```

```sql
-- Ver candidato
SELECT * FROM talentflow.candidates WHERE email = 'juan.garcia@example.com';

-- Ver aplicación
SELECT a.id, a.ticket, a.status, a.priority, se.total_score
FROM talentflow.applications a
LEFT JOIN talentflow.score_evaluations se ON a.id = se.application_id
WHERE a.candidate_id = (SELECT id FROM talentflow.candidates WHERE email = 'juan.garcia@example.com');

-- Ver análisis IA
SELECT analysis_type, status, structured_output
FROM talentflow.ai_analyses
WHERE application_id = (SELECT id FROM talentflow.applications LIMIT 1);

-- Ver desglose de score
SELECT scr.id, sc.name, scr.points_awarded, scr.matched
FROM talentflow.score_criterion_results scr
JOIN talentflow.scoring_criteria sc ON scr.scoring_criterion_id = sc.id
WHERE scr.score_evaluation_id = (SELECT id FROM talentflow.score_evaluations LIMIT 1);
```

---

## 7. MATRIZ DE VALIDACIÓN

| Aspecto | Validación | Status |
|---------|-----------|--------|
| Docker compuesto levantado | `docker compose ps` muestra 3 healthy | ◯ |
| Vacante creada | `http://localhost:5173/vacantes` muestra la vacante | ◯ |
| Workflows en n8n | TF-MVP-01 creado y activado | ◯ |
| Credencial OpenAI | Configurada en n8n | ◯ |
| PDF procesado | Workflow recibe y valida PDF | ◯ |
| IA-01 ejecuta | Extrae información JSON | ◯ |
| Score calculado | JS calcula número 0-100 | ◯ |
| IA-02 ejecuta | Genera resumen de 100-200 palabras | ◯ |
| IA-03 ejecuta | Genera 5 preguntas válidas | ◯ |
| BD guarda | Candidato y aplicación en PostgreSQL | ◯ |
| Frontend lista | `/admin/candidatos` muestra candidato | ◯ |
| Frontend detalle | `/admin/candidatos/{id}` completo | ◯ |
| Score visible | Panel muestra 87 puntos | ◯ |
| Habilidades visibles | Detecta Java, Spring Boot, SQL | ◯ |
| Desglose visible | Muestra criterios con puntos | ◯ |
| Resumen visible | IA-02 output se renderiza | ◯ |
| Preguntas visibles | IA-03 output se renderiza (5) | ◯ |

---

## 8. TROUBLESHOOTING

### Problema: "CV no legible"
**Causa:** PDF escaneado o sin texto extractable  
**Solución:** Usar PDF generado de Word/Google Docs

### Problema: "No se puede conectar a OpenAI"
**Causa:** Credencial no configurada o API Key inválida  
**Solución:** 
- Verificar `OPENAI_API_KEY` válida en n8n Credentials
- Verificar saldo en cuenta OpenAI

### Problema: Frontend carga pero candidatos están vacíos
**Causa:** Endpoint `/api/admin/candidates` no existe o falla  
**Solución:**
- Verificar webhook en n8n respondiendo
- Ver `docker compose logs n8n`

### Problema: Score incorrecto (ej. 120 en lugar de 87)
**Causa:** Lógica de scoring en JS tiene error  
**Solución:**
- Revisar algoritmo en código: máximo 100 puntos
- Revisar peso de criterios suma a 100
- Debug con `console.log()` en nodo Code

### Problema: Aplicación no se guarda en BD
**Causa:** Query PostgreSQL falla  
**Solución:**
- Verificar credencial PostgreSQL en n8n
- Revisar query SQL en nodo
- Ver logs de n8n para errores

---

## 9. METRICAS ESPERADAS (MVP)

- **Tiempo de procesamiento:** 30-60 segundos (3 llamadas OpenAI)
- **Score promedio:** 60-90 (según CV)
- **Prioridad calculada:** ALTA (80+), MEDIA (60-79), BAJA (<60)
- **Habilidades detectadas:** 5-8 tecnologías
- **Preguntas generadas:** Exactamente 5

---

## 10. PRÓXIMOS PASOS DESPUÉS DE VALIDACIÓN

✅ **Si todo funciona:**
1. Hacer commit de código
2. Hacer push a rama `mvp-rescate`
3. Hacer PR a `main`
4. Merge a `main`
5. Documentar credenciales en setup interno

❌ **Si hay errores:**
1. Ver logs específicos en n8n
2. Revisar queries PostgreSQL
3. Verificar variables en prompts IA
4. Consultar documentación en TF-MVP-01-SETUP.md

---

**Duración estimada de prueba:** 15-30 minutos  
**Éxito:** Si el candidato aparece en `/admin/candidatos` con score y detalles IA
