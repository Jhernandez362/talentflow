# Modulo 5: IA-01 extractor de CV

## Alcance

- Subworkflow `WF-IA01-EXTRACTOR-CV` con input `postulacion_id`.
- Descarga únicamente CV previamente válidos desde Google Drive privado.
- Extrae texto y exige un mínimo defensivo de 100 caracteres.
- Usa `PROMPT-IA-01-v1`, `gemini-3.6-flash` y Structured Output Parser.
- Valida nuevamente el JSON y rechaza score, recomendaciones y atributos protegidos.
- Persiste proveedor, modelo, prompt, timestamps, resultado o error.
- Limita IA-01 a tres intentos y diferencia `AI_PROCESSING_ERROR` de errores del PDF.
- Finaliza en `ANALIZADO` solo después de guardar un resultado válido.

IA-01 no calcula score, no resume, no genera preguntas y no procesa postulaciones
en `REVISION_DOCUMENTO`.

## Ejemplo

Input: `{"postulacion_id":"c8a7ca06-0c8d-4700-bd0c-7d2fa02ef85a"}`

Output:

```json
{
  "analysis_id": "uuid",
  "structured_candidate_data": {
    "experiencia_total_anios": 2,
    "experiencias": [], "educacion": [], "cursos": [],
    "certificaciones": [], "idiomas": [], "habilidades": [],
    "habilidades_declaradas_no_verificadas": [], "advertencias": []
  },
  "status": "ANALIZADO"
}
```
