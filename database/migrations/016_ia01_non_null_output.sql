BEGIN;

CREATE OR REPLACE FUNCTION talentflow.ia01_complete_analysis(
    target_analysis_id uuid, candidate_data jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE target_application_id uuid;
BEGIN
    IF candidate_data IS NULL
       OR jsonb_typeof(candidate_data) <> 'object'
       OR jsonb_typeof(candidate_data->'experiencias') <> 'array'
       OR jsonb_typeof(candidate_data->'educacion') <> 'array'
       OR jsonb_typeof(candidate_data->'cursos') <> 'array'
       OR jsonb_typeof(candidate_data->'certificaciones') <> 'array'
       OR jsonb_typeof(candidate_data->'idiomas') <> 'array'
       OR jsonb_typeof(candidate_data->'habilidades') <> 'array'
       OR jsonb_typeof(candidate_data->'habilidades_declaradas_no_verificadas') <> 'array'
       OR jsonb_typeof(candidate_data->'advertencias') <> 'array'
       OR candidate_data ?| ARRAY['score', 'compatibilidad', 'recomendacion', 'contratar', 'rechazar']
    THEN RAISE EXCEPTION 'La respuesta de IA-01 no cumple el schema permitido'; END IF;

    UPDATE talentflow.ai_analyses SET status = 'SUCCEEDED', structured_output = candidate_data,
        completed_at = now(), updated_at = now(), error_message = NULL
    WHERE id = target_analysis_id AND analysis_type = 'CV_EXTRACTION' AND status = 'RUNNING'
    RETURNING application_id INTO target_application_id;
    IF target_application_id IS NULL THEN RAISE EXCEPTION 'Análisis IA-01 no disponible'; END IF;
    UPDATE talentflow.applications SET status = 'ANALIZADO', updated_at = now()
    WHERE id = target_application_id;
    RETURN jsonb_build_object('analysis_id', target_analysis_id,
        'structured_candidate_data', candidate_data, 'status', 'ANALIZADO');
END;
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('016', 'Reject null IA-01 structured output before marking analysis successful')
ON CONFLICT (version) DO NOTHING;

COMMIT;
