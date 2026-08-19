BEGIN;

CREATE OR REPLACE FUNCTION talentflow.admin_list_candidates()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'ticket', a.ticket_id,
    'full_name', c.full_name,
    'vacancy_title', v.title,
    'score', COALESCE(latest_score.total_score, 0),
    'priority', a.priority,
    'status', a.status,
    'applied_at', a.applied_at
) ORDER BY a.applied_at DESC), '[]'::jsonb)
FROM talentflow.applications a
JOIN talentflow.candidates c ON c.id = a.candidate_id
JOIN talentflow.vacancies v ON v.id = a.vacancy_id
LEFT JOIN LATERAL (
    SELECT se.total_score
    FROM talentflow.score_evaluations se
    WHERE se.application_id = a.id
    ORDER BY se.calculated_at DESC
    LIMIT 1
) latest_score ON true
WHERE EXISTS (
    SELECT 1
    FROM talentflow.document_processing_attempts attempt
    WHERE attempt.application_id = a.id
      AND attempt.status = 'SUCCEEDED'
)
AND EXISTS (
    SELECT 1
    FROM talentflow.cv_references cv
    WHERE cv.application_id = a.id
      AND cv.is_current
);
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_get_candidate(target_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
SELECT jsonb_build_object(
    'id', a.id,
    'ticket', a.ticket_id,
    'full_name', c.full_name,
    'email', c.email,
    'phone', c.phone,
    'location', c.location,
    'vacancy_title', v.title,
    'applied_at', a.applied_at,
    'experience_years', COALESCE(c.declared_experience_years, 0),
    'score', COALESCE(latest_score.total_score, 0),
    'priority', a.priority,
    'status', a.status,
    'habilidades', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'nombre', skill,
            'evidencia_laboral', false
        ) ORDER BY skill)
        FROM unnest(c.declared_skills) skill
    ), '[]'::jsonb),
    'score_breakdown', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'nombre', criterion.name,
            'peso', criterion.weight,
            'puntos', result.points_awarded,
            'cumple', result.matched
        ) ORDER BY criterion.evaluation_order)
        FROM talentflow.score_criterion_results result
        JOIN talentflow.scoring_criteria criterion
          ON criterion.id = result.scoring_criterion_id
        WHERE result.score_evaluation_id = latest_score.id
    ), '[]'::jsonb),
    'interview_questions', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'tema', COALESCE(q.rationale, 'Entrevista'),
            'pregunta', q.question
        ) ORDER BY q.display_order)
        FROM talentflow.suggested_questions q
        WHERE q.application_id = a.id
    ), '[]'::jsonb),
    'resumen', latest_summary.structured_output->>'summary'
)
FROM talentflow.applications a
JOIN talentflow.candidates c ON c.id = a.candidate_id
JOIN talentflow.vacancies v ON v.id = a.vacancy_id
LEFT JOIN LATERAL (
    SELECT se.id, se.total_score
    FROM talentflow.score_evaluations se
    WHERE se.application_id = a.id
    ORDER BY se.calculated_at DESC
    LIMIT 1
) latest_score ON true
LEFT JOIN LATERAL (
    SELECT analysis.structured_output
    FROM talentflow.ai_analyses analysis
    WHERE analysis.application_id = a.id
      AND analysis.analysis_type = 'PROFESSIONAL_SUMMARY'
      AND analysis.status = 'SUCCEEDED'
    ORDER BY analysis.created_at DESC
    LIMIT 1
) latest_summary ON true
WHERE a.id = target_id;
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('013', 'Administrative candidate list and detail API')
ON CONFLICT (version) DO NOTHING;

COMMIT;
