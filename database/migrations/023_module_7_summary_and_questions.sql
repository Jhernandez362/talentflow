BEGIN;

CREATE OR REPLACE FUNCTION talentflow.ia02_begin_summary(
    target_application_id uuid,
    target_provider text DEFAULT 'google-gemini',
    target_model text DEFAULT 'gemini-3.6-flash'
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    target_analysis_id uuid;
    failed_attempts integer;
    context_data jsonb;
BEGIN
    SELECT count(*) INTO failed_attempts
    FROM talentflow.ai_analyses
    WHERE application_id=target_application_id AND analysis_type='PROFESSIONAL_SUMMARY'
      AND status='FAILED' AND prompt_version='PROMPT-IA-02-v1';
    IF failed_attempts >= 3 THEN RAISE EXCEPTION 'IA02_RETRY_LIMIT_REACHED'; END IF;
    IF EXISTS (SELECT 1 FROM talentflow.ai_analyses WHERE application_id=target_application_id
               AND analysis_type='PROFESSIONAL_SUMMARY' AND status IN ('RUNNING','SUCCEEDED'))
    THEN RAISE EXCEPTION 'IA02_ALREADY_RUNNING_OR_COMPLETED'; END IF;

    SELECT jsonb_build_object(
        'candidate_structured_data', extraction.structured_output,
        'score_breakdown', score.result_breakdown,
        'vacancy_title', vacancy.title,
        'vacancy_requirements', jsonb_build_object(
            'criteria', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'name', criterion.name, 'type', criterion.criterion_type,
                'weight', criterion.weight, 'required', criterion.is_required
            ) ORDER BY criterion.evaluation_order)
            FROM talentflow.scoring_criteria criterion
            WHERE criterion.scoring_config_version_id=score.scoring_config_version_id), '[]'::jsonb),
            'minimum_experience_months', vacancy.minimum_experience_months,
            'minimum_education', vacancy.minimum_education
        )
    ) INTO context_data
    FROM talentflow.applications application
    JOIN talentflow.vacancies vacancy ON vacancy.id=application.vacancy_id
    JOIN LATERAL (SELECT analysis.structured_output FROM talentflow.ai_analyses analysis
        WHERE analysis.application_id=application.id AND analysis.analysis_type='CV_EXTRACTION'
          AND analysis.status='SUCCEEDED' ORDER BY analysis.completed_at DESC LIMIT 1) extraction ON true
    JOIN LATERAL (SELECT evaluation.* FROM talentflow.score_evaluations evaluation
        WHERE evaluation.application_id=application.id ORDER BY evaluation.calculated_at DESC LIMIT 1) score ON true
    WHERE application.id=target_application_id;
    IF context_data IS NULL THEN RAISE EXCEPTION 'IA02_STRUCTURED_CONTEXT_NOT_AVAILABLE'; END IF;

    INSERT INTO talentflow.ai_analyses(application_id,analysis_type,status,provider,model,prompt_code,prompt_version,started_at)
    VALUES(target_application_id,'PROFESSIONAL_SUMMARY','RUNNING',left(target_provider,80),left(target_model,120),
           'PROMPT-IA-02','PROMPT-IA-02-v1',now()) RETURNING id INTO target_analysis_id;
    RETURN context_data || jsonb_build_object('analysis_id',target_analysis_id,'attempt_number',failed_attempts+1);
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.ia02_complete_summary(target_analysis_id uuid, result_data jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE target_application_id uuid;
BEGIN
    IF result_data IS NULL OR jsonb_typeof(result_data)<>'object'
       OR jsonb_typeof(result_data->'key_points')<>'array'
       OR btrim(COALESCE(result_data->>'summary',''))=''
       OR jsonb_array_length(result_data->'key_points') NOT BETWEEN 1 AND 8
       OR result_data ?| ARRAY['recommendation','decision','hire','reject','score']
    THEN RAISE EXCEPTION 'IA02_INVALID_OUTPUT'; END IF;
    UPDATE talentflow.ai_analyses SET status='SUCCEEDED',structured_output=result_data,
        completed_at=now(),updated_at=now(),error_message=NULL
    WHERE id=target_analysis_id AND analysis_type='PROFESSIONAL_SUMMARY' AND status='RUNNING'
    RETURNING application_id INTO target_application_id;
    IF target_application_id IS NULL THEN RAISE EXCEPTION 'IA02_ANALYSIS_NOT_AVAILABLE'; END IF;
    RETURN jsonb_build_object('analysis_id',target_analysis_id,'application_id',target_application_id,
        'status','SUCCEEDED','result',result_data);
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.ia02_fail_summary(target_analysis_id uuid, failure_message text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE target_application_id uuid;
BEGIN
    UPDATE talentflow.ai_analyses SET status='FAILED',error_message=left(COALESCE(failure_message,'IA-02 error'),2000),
        completed_at=now(),updated_at=now() WHERE id=target_analysis_id AND analysis_type='PROFESSIONAL_SUMMARY'
    RETURNING application_id INTO target_application_id;
    IF target_application_id IS NULL THEN RAISE EXCEPTION 'IA02_ANALYSIS_NOT_AVAILABLE'; END IF;
    RETURN jsonb_build_object('analysis_id',target_analysis_id,'application_id',target_application_id,'status','FAILED');
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.ia03_begin_questions(
    target_application_id uuid,
    target_provider text DEFAULT 'google-gemini',
    target_model text DEFAULT 'gemini-3.6-flash'
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE target_analysis_id uuid; failed_attempts integer; context_data jsonb;
BEGIN
    SELECT count(*) INTO failed_attempts FROM talentflow.ai_analyses
    WHERE application_id=target_application_id AND analysis_type='INTERVIEW_QUESTIONS'
      AND status='FAILED' AND prompt_version='PROMPT-IA-03-v1';
    IF failed_attempts >= 3 THEN RAISE EXCEPTION 'IA03_RETRY_LIMIT_REACHED'; END IF;
    IF EXISTS (SELECT 1 FROM talentflow.ai_analyses WHERE application_id=target_application_id
               AND analysis_type='INTERVIEW_QUESTIONS' AND status IN ('RUNNING','SUCCEEDED'))
    THEN RAISE EXCEPTION 'IA03_ALREADY_RUNNING_OR_COMPLETED'; END IF;

    SELECT jsonb_build_object(
        'candidate_name', candidate.full_name,
        'total_experience_years', extraction.structured_output->'experiencia_total_anios',
        'work_experiences', extraction.structured_output->'experiencias',
        'detected_skills', extraction.structured_output->'habilidades',
        'declared_unverified_skills', extraction.structured_output->'habilidades_declaradas_no_verificadas',
        'work_evidence', COALESCE((SELECT jsonb_agg(skill) FROM jsonb_array_elements(extraction.structured_output->'habilidades') skill
                                  WHERE COALESCE((skill->>'evidencia_laboral')::boolean,false)), '[]'::jsonb),
        'vacancy_requirements', COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'name',criterion.name,'type',criterion.criterion_type,'required',criterion.is_required,'weight',criterion.weight
        ) ORDER BY criterion.evaluation_order) FROM talentflow.scoring_criteria criterion
        WHERE criterion.scoring_config_version_id=score.scoring_config_version_id), '[]'::jsonb),
        'missing_requirements', COALESCE(score.result_breakdown->'mandatory_missing','[]'::jsonb),
        'question_count', 5
    ) INTO context_data
    FROM talentflow.applications application
    JOIN talentflow.candidates candidate ON candidate.id=application.candidate_id
    JOIN LATERAL (SELECT analysis.structured_output FROM talentflow.ai_analyses analysis
        WHERE analysis.application_id=application.id AND analysis.analysis_type='CV_EXTRACTION'
          AND analysis.status='SUCCEEDED' ORDER BY analysis.completed_at DESC LIMIT 1) extraction ON true
    JOIN LATERAL (SELECT evaluation.* FROM talentflow.score_evaluations evaluation
        WHERE evaluation.application_id=application.id ORDER BY evaluation.calculated_at DESC LIMIT 1) score ON true
    WHERE application.id=target_application_id;
    IF context_data IS NULL THEN RAISE EXCEPTION 'IA03_STRUCTURED_CONTEXT_NOT_AVAILABLE'; END IF;

    INSERT INTO talentflow.ai_analyses(application_id,analysis_type,status,provider,model,prompt_code,prompt_version,started_at)
    VALUES(target_application_id,'INTERVIEW_QUESTIONS','RUNNING',left(target_provider,80),left(target_model,120),
           'PROMPT-IA-03','PROMPT-IA-03-v1',now()) RETURNING id INTO target_analysis_id;
    RETURN context_data || jsonb_build_object('analysis_id',target_analysis_id,'attempt_number',failed_attempts+1);
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.ia03_complete_questions(target_analysis_id uuid, result_data jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE target_application_id uuid; question_item jsonb; question_index integer := 0;
BEGIN
    IF result_data IS NULL OR jsonb_typeof(result_data)<>'object'
       OR jsonb_typeof(result_data->'questions')<>'array'
       OR jsonb_array_length(result_data->'questions') NOT BETWEEN 1 AND 5
    THEN RAISE EXCEPTION 'IA03_INVALID_OUTPUT'; END IF;
    FOR question_item IN SELECT value FROM jsonb_array_elements(result_data->'questions') LOOP
        IF btrim(COALESCE(question_item->>'topic',''))='' OR btrim(COALESCE(question_item->>'question',''))=''
           OR question_item->>'source_type' NOT IN ('WORK_EXPERIENCE','DECLARED_SKILL','EDUCATION','CERTIFICATION','REQUIREMENT_VALIDATION')
        THEN RAISE EXCEPTION 'IA03_INVALID_QUESTION'; END IF;
    END LOOP;
    UPDATE talentflow.ai_analyses SET status='SUCCEEDED',structured_output=result_data,
        completed_at=now(),updated_at=now(),error_message=NULL
    WHERE id=target_analysis_id AND analysis_type='INTERVIEW_QUESTIONS' AND status='RUNNING'
    RETURNING application_id INTO target_application_id;
    IF target_application_id IS NULL THEN RAISE EXCEPTION 'IA03_ANALYSIS_NOT_AVAILABLE'; END IF;
    DELETE FROM talentflow.suggested_questions WHERE application_id=target_application_id;
    FOR question_item IN SELECT value FROM jsonb_array_elements(result_data->'questions') LOOP
        INSERT INTO talentflow.suggested_questions(application_id,ai_analysis_id,question,rationale,display_order)
        VALUES(target_application_id,target_analysis_id,question_item->>'question',question_item->>'topic',question_index);
        question_index := question_index + 1;
    END LOOP;
    RETURN jsonb_build_object('analysis_id',target_analysis_id,'application_id',target_application_id,
        'status','SUCCEEDED','result',result_data);
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.ia03_fail_questions(target_analysis_id uuid, failure_message text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE target_application_id uuid;
BEGIN
    UPDATE talentflow.ai_analyses SET status='FAILED',error_message=left(COALESCE(failure_message,'IA-03 error'),2000),
        completed_at=now(),updated_at=now() WHERE id=target_analysis_id AND analysis_type='INTERVIEW_QUESTIONS'
    RETURNING application_id INTO target_application_id;
    IF target_application_id IS NULL THEN RAISE EXCEPTION 'IA03_ANALYSIS_NOT_AVAILABLE'; END IF;
    RETURN jsonb_build_object('analysis_id',target_analysis_id,'application_id',target_application_id,'status','FAILED');
END;
$$;

INSERT INTO talentflow.schema_migrations(version,description)
VALUES('023','Module 7 independent IA-02 summary and IA-03 interview questions')
ON CONFLICT(version) DO NOTHING;

COMMIT;
