# Modulo 7: IA-02 resumen e IA-03 preguntas

El módulo ejecuta dos subworkflows independientes después del scoring:

- `WF-IA02-RESUMEN` usa `PROMPT-IA-02-v1` y persiste un análisis `PROFESSIONAL_SUMMARY`.
- `WF-IA03-PREGUNTAS` usa `PROMPT-IA-03-v1`, persiste un análisis `INTERVIEW_QUESTIONS` y materializa hasta cinco preguntas en `suggested_questions`.

Ambos consumen la salida estructurada de IA-01 y el scoring ya almacenado. No
descargan ni reinterpretan el CV, no recalculan el score y admiten hasta tres
intentos fallidos de manera individual. El fallo de una tarea no cambia el estado
de la postulación ni obliga a repetir IA-01.

## Pruebas

```bash
node n8n/tests/module7-contract-tests.mjs
node n8n/workflows/validate-workflows.mjs
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U talentflow_app -d talentflow < database/tests/008_module_7_summary_questions.sql
```
