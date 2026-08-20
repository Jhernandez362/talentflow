# Modulo 6: motor deterministico de compatibilidad

`WF-SCORING-CANDIDATO` recibe `postulacion_id`, `analysis_id`, `vacancy_id` y
`scoring_version`. Carga exclusivamente el resultado estructurado de IA-01 y la
version publicada de scoring solicitada. No llama modelos de IA.

## Algoritmo

- Normaliza con `trim`, minusculas y espacios consecutivos.
- Tecnologias y conocimientos coinciden solo por nombre exacto o alias
  configurado. Las habilidades declaradas no verificadas no otorgan puntos.
- Criterios binarios otorgan todo el peso o cero. La evidencia laboral se
  informa, pero no cambia los puntos.
- Experiencia: `min(anios_candidato / anios_requeridos, 1) * peso`.
- Educacion usa la jerarquia `NINGUNA`, `BACHILLER`, `TECNICO`, `TECNOLOGO`,
  `PROFESIONAL`, `ESPECIALIZACION`, `MAESTRIA`, `DOCTORADO`.
- Obligatorios faltantes generan una alerta y no descartan al candidato.
- Deseables y valor agregado se informan y no suman al score.
- El total se redondea a dos decimales y se limita a `0..100`.
- Prioridad: `ALTA >= 80`, `MEDIA >= 60`, de lo contrario `BAJA`.

## Persistencia y auditoria

`talentflow.persist_deterministic_score(jsonb)` valida que la postulacion, el
analisis exitoso, la vacante y la version publicada correspondan entre si. La
base guarda el score, la version, el timestamp, el analisis fuente, todos los
criterios y el resultado completo (`mandatory_missing`, deseables, valor
agregado y ajuste de seniority).

La combinacion postulacion/version es unica. Un nuevo calculo de una version ya
guardada falla con `SCORE_ALREADY_EXISTS_FOR_VERSION`; una version nueva debe
solicitarse de forma explicita.

## Pruebas

```powershell
node n8n/tests/scoring-engine-tests.mjs
node n8n/workflows/validate-workflows.mjs
Get-Content -Raw database/tests/007_module_6_deterministic_scoring.sql |
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U talentflow_app -d talentflow
```

La prueba JavaScript cubre los casos A-I, reproducibilidad, limites, prioridad,
seniority y exclusión de habilidades no verificadas. La prueba SQL crea su
propio escenario dentro de una transaccion, valida persistencia y reglas de
rechazo, y ejecuta `ROLLBACK` al terminar.
