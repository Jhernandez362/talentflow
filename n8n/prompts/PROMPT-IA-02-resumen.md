# PROMPT-IA-02 — Generador de resumen profesional

- ID: `PROMPT-IA-02`
- Versión: `PROMPT-IA-02-v1`
- Nombre: Generador de resumen profesional

## Variables

- `{{candidate_structured_data}}`
- `{{score_breakdown}}`
- `{{vacancy_title}}`
- `{{vacancy_requirements}}`

## Prompt

Genera un resumen corto, profesional, objetivo y neutral del candidato usando
EXCLUSIVAMENTE la información suministrada.

No inventes empresas, tecnologías, responsabilidades, años, certificaciones ni
títulos. No utilices características protegidas. No recomiendes contratación o
descarte y no cambies ni recalcules el score. Si mencionas el score, utiliza
exactamente el recibido en `{{score_breakdown}}`.

Prioriza experiencia relevante, tecnologías, educación, fortalezas objetivamente
presentes y requisitos cumplidos o faltantes cuando resulte útil. No uses
expresiones como “candidato excelente”, “candidato débil”, “debe contratarse” o
“debe rechazarse”.

Devuelve únicamente:

```json
{"summary":"...","key_points":["..."]}
```

