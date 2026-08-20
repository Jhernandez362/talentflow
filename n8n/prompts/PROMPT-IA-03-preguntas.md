# PROMPT-IA-03 — Generador de preguntas de entrevista

- ID: `PROMPT-IA-03`
- Versión: `PROMPT-IA-03-v1`
- Nombre: Generador de preguntas de entrevista
- Cantidad inicial: 5 preguntas

## Variables

- `{{candidate_name}}`
- `{{total_experience_years}}`
- `{{work_experiences}}`
- `{{detected_skills}}`
- `{{work_evidence}}`
- `{{vacancy_requirements}}`
- `{{missing_requirements}}`

## Prompt

Genera exactamente 5 preguntas diversas para que RR. HH. valide experiencia y
conocimientos declarados. Utiliza EXCLUSIVAMENTE la información recibida.

No inventes experiencias, empresas ni tecnologías. No afirmes que una tecnología
fue usada profesionalmente sin evidencia laboral. Con evidencia, contextualiza la
pregunta con la experiencia correspondiente. Si aparece únicamente como habilidad
declarada, pregunta en qué contextos fue utilizada sin afirmar experiencia laboral.

Prioriza tecnologías principales, responsabilidades, experiencia, requisitos
obligatorios y requisitos faltantes por validar. No preguntes por edad, género,
estado civil, nacionalidad, religión, discapacidad, orientación sexual, embarazo
ni otra información protegida. No realices decisiones laborales.

`source_type` solo puede ser `WORK_EXPERIENCE`, `DECLARED_SKILL`, `EDUCATION`,
`CERTIFICATION` o `REQUIREMENT_VALIDATION`. `experience_id` debe ser el ID real
de la experiencia cuando corresponda; en otro caso debe ser `null`.

Devuelve únicamente JSON con esta forma:

```json
{"questions":[{"topic":"Docker","question":"...","source_type":"WORK_EXPERIENCE","evidence":"...","experience_id":"EXP-2"}]}
```

