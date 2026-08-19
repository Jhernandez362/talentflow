BEGIN;

CREATE OR REPLACE FUNCTION talentflow.ia01_begin_analysis(
    target_application_id uuid, target_provider text DEFAULT 'google-gemini',
    target_model text DEFAULT 'gemini-2.5-flash'
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    target_analysis_id uuid;
    context_data jsonb;
    failed_attempts integer;
BEGIN
    SELECT count(*) INTO failed_attempts FROM talentflow.ai_analyses analysis
    WHERE analysis.application_id = target_application_id
      AND analysis.analysis_type = 'CV_EXTRACTION' AND analysis.status = 'FAILED'
      AND analysis.prompt_version = 'PROMPT-IA-01-v1';
    IF failed_attempts >= 3 THEN RAISE EXCEPTION 'Se agotaron los 3 intentos permitidos para IA-01'; END IF;

    SELECT jsonb_build_object(
        'application_id', application.id, 'drive_file_id', cv.drive_file_id,
        'candidate_declared_experience', candidate.declared_experience_years,
        'candidate_declared_skills', to_jsonb(candidate.declared_skills),
        'vacancy_title', vacancy.title, 'attempt_number', failed_attempts + 1
    ) INTO context_data
    FROM talentflow.applications application
    JOIN talentflow.candidates candidate ON candidate.id = application.candidate_id
    JOIN talentflow.vacancies vacancy ON vacancy.id = application.vacancy_id
    JOIN talentflow.cv_references cv ON cv.application_id = application.id AND cv.is_current
    WHERE application.id = target_application_id
      AND application.status IN ('RECIBIDO', 'PROCESANDO', 'ERROR')
      AND EXISTS (SELECT 1 FROM talentflow.document_processing_attempts attempt
                  WHERE attempt.application_id = application.id AND attempt.status = 'SUCCEEDED');
    IF context_data IS NULL THEN
        RAISE EXCEPTION 'La postulación no tiene un CV válido disponible para IA-01';
    END IF;

    INSERT INTO talentflow.ai_analyses (
        application_id, analysis_type, status, provider, model,
        prompt_code, prompt_version, started_at
    ) VALUES (
        target_application_id, 'CV_EXTRACTION', 'RUNNING', left(target_provider, 80),
        left(target_model, 120), 'PROMPT-IA-01', 'PROMPT-IA-01-v1', now()
    ) RETURNING id INTO target_analysis_id;
    UPDATE talentflow.applications SET status = 'PROCESANDO', updated_at = now()
    WHERE id = target_application_id;
    RETURN context_data || jsonb_build_object('analysis_id', target_analysis_id);
END;
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('017', 'Use Google Gemini Flash as the IA-01 default provider and model')
ON CONFLICT (version) DO NOTHING;

COMMIT;
