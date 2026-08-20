BEGIN;

ALTER TABLE talentflow.score_evaluations
    ADD COLUMN IF NOT EXISTS analysis_id uuid REFERENCES talentflow.ai_analyses(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS result_breakdown jsonb;

ALTER TABLE talentflow.score_evaluations
    DROP CONSTRAINT IF EXISTS score_result_breakdown_object,
    ADD CONSTRAINT score_result_breakdown_object
        CHECK (result_breakdown IS NULL OR jsonb_typeof(result_breakdown) = 'object');

CREATE OR REPLACE FUNCTION talentflow.persist_deterministic_score(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    evaluation_id uuid;
    target_application_id uuid := (payload->>'postulacion_id')::uuid;
    target_analysis_id uuid := (payload->>'analysis_id')::uuid;
    target_vacancy_id uuid := (payload->>'vacancy_id')::uuid;
    target_config_id uuid := (payload->>'scoring_version_id')::uuid;
    target_score numeric(5,2) := round((payload->>'score')::numeric, 2);
    target_priority varchar(10) := payload->>'priority';
    expected_priority varchar(10);
    expected_version integer;
    expected_criteria integer;
    received_criteria integer;
    result jsonb;
BEGIN
    IF jsonb_typeof(payload) <> 'object'
       OR jsonb_typeof(payload->'criteria') <> 'array'
       OR jsonb_typeof(payload->'mandatory_missing') <> 'array'
       OR jsonb_typeof(payload->'desired_found') <> 'array'
       OR jsonb_typeof(payload->'desired_missing') <> 'array'
       OR jsonb_typeof(payload->'added_value') <> 'array'
       OR payload->>'seniority_fit' NOT IN ('POR_DEBAJO', 'ALINEADO', 'POR_ENCIMA')
    THEN
        RAISE EXCEPTION 'INVALID_DETERMINISTIC_SCORE_PAYLOAD';
    END IF;

    IF target_score < 0 OR target_score > 100 THEN
        RAISE EXCEPTION 'Deterministic score must be between 0 and 100';
    END IF;
    expected_priority := CASE WHEN target_score >= 80 THEN 'ALTA' WHEN target_score >= 60 THEN 'MEDIA' ELSE 'BAJA' END;
    IF target_priority IS DISTINCT FROM expected_priority THEN
        RAISE EXCEPTION 'Priority % does not correspond to score %', target_priority, target_score;
    END IF;

    SELECT config.version, count(criterion.id)::integer
    INTO expected_version, expected_criteria
    FROM talentflow.scoring_config_versions config
    LEFT JOIN talentflow.scoring_criteria criterion ON criterion.scoring_config_version_id = config.id
    WHERE config.id = target_config_id
      AND config.vacancy_id = target_vacancy_id
      AND config.status = 'PUBLISHED'
    GROUP BY config.version;
    IF expected_version IS NULL OR expected_version IS DISTINCT FROM (payload->>'scoring_version')::integer THEN
        RAISE EXCEPTION 'SCORING_VERSION_MISMATCH';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM talentflow.applications application
        JOIN talentflow.ai_analyses analysis
          ON analysis.id = target_analysis_id
         AND analysis.application_id = application.id
         AND analysis.analysis_type = 'CV_EXTRACTION'
         AND analysis.status = 'SUCCEEDED'
        WHERE application.id = target_application_id
          AND application.vacancy_id = target_vacancy_id
    ) THEN
        RAISE EXCEPTION 'SCORING_APPLICATION_ANALYSIS_MISMATCH';
    END IF;

    SELECT count(*) INTO received_criteria FROM jsonb_array_elements(payload->'criteria');
    IF received_criteria <> expected_criteria THEN
        RAISE EXCEPTION 'INCOMPLETE_SCORE_BREAKDOWN';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(payload->'criteria') item
        LEFT JOIN talentflow.scoring_criteria criterion
          ON criterion.id = (item->>'criterion_id')::uuid
         AND criterion.scoring_config_version_id = target_config_id
        WHERE criterion.id IS NULL
           OR (item->>'points')::numeric < 0
           OR (item->>'points')::numeric > criterion.weight
    ) THEN
        RAISE EXCEPTION 'INVALID_SCORE_CRITERION';
    END IF;
    IF (SELECT round(COALESCE(sum((item->>'points')::numeric), 0), 2)
        FROM jsonb_array_elements(payload->'criteria') item) <> target_score THEN
        RAISE EXCEPTION 'SCORE_BREAKDOWN_TOTAL_MISMATCH';
    END IF;

    IF EXISTS (
        SELECT 1 FROM talentflow.score_evaluations
        WHERE application_id = target_application_id
          AND scoring_config_version_id = target_config_id
    ) THEN
        RAISE EXCEPTION 'SCORE_ALREADY_EXISTS_FOR_VERSION';
    END IF;

    result := jsonb_build_object(
        'score', target_score,
        'priority', target_priority,
        'scoring_version', expected_version,
        'criteria', payload->'criteria',
        'mandatory_missing', payload->'mandatory_missing',
        'desired_found', payload->'desired_found',
        'desired_missing', payload->'desired_missing',
        'added_value', payload->'added_value',
        'added_value_missing', COALESCE(payload->'added_value_missing', '[]'::jsonb),
        'seniority_fit', payload->>'seniority_fit'
    );

    INSERT INTO talentflow.score_evaluations (
        application_id, analysis_id, vacancy_id, scoring_config_version_id,
        total_score, algorithm_version, compatibility_priority, result_breakdown
    ) VALUES (
        target_application_id, target_analysis_id, target_vacancy_id, target_config_id,
        target_score, 'WF-SCORING-CANDIDATO-v1', target_priority, result
    ) RETURNING id INTO evaluation_id;

    INSERT INTO talentflow.score_criterion_results (
        score_evaluation_id, scoring_criterion_id, matched, points_awarded, evidence, explanation
    )
    SELECT evaluation_id,
           (item->>'criterion_id')::uuid,
           COALESCE((item->>'matched')::boolean, false),
           round((item->>'points')::numeric, 2),
           jsonb_build_array(jsonb_build_object(
               'work_evidence', COALESCE((item->>'work_evidence')::boolean, false),
               'mandatory', COALESCE((item->>'mandatory')::boolean, false)
           )),
           item->>'explanation'
    FROM jsonb_array_elements(payload->'criteria') item;

    RETURN result || jsonb_build_object(
        'evaluation_id', evaluation_id,
        'calculated_at', (SELECT calculated_at FROM talentflow.score_evaluations WHERE id = evaluation_id)
    );
END;
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('020', 'Complete Module 6 deterministic score audit and validation')
ON CONFLICT (version) DO NOTHING;

COMMIT;
