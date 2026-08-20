BEGIN;

ALTER TABLE talentflow.score_evaluations
    ADD COLUMN IF NOT EXISTS compatibility_priority varchar(10),
    ADD CONSTRAINT score_compatibility_priority_valid
        CHECK (compatibility_priority IS NULL OR compatibility_priority IN ('ALTA', 'MEDIA', 'BAJA'));

CREATE OR REPLACE FUNCTION talentflow.persist_deterministic_score(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    evaluation_id uuid;
    result jsonb;
BEGIN
    IF EXISTS (
        SELECT 1 FROM talentflow.score_evaluations
        WHERE application_id = (payload->>'postulacion_id')::uuid
          AND scoring_config_version_id = (payload->>'scoring_version_id')::uuid
    ) THEN
        RAISE EXCEPTION 'SCORE_ALREADY_EXISTS_FOR_VERSION';
    END IF;
    IF (payload->>'score')::numeric < 0 OR (payload->>'score')::numeric > 100 THEN
        RAISE EXCEPTION 'Deterministic score must be between 0 and 100';
    END IF;
    INSERT INTO talentflow.score_evaluations (
        application_id, vacancy_id, scoring_config_version_id, total_score, algorithm_version, compatibility_priority
    ) VALUES (
        (payload->>'postulacion_id')::uuid, (payload->>'vacancy_id')::uuid,
        (payload->>'scoring_version_id')::uuid, (payload->>'score')::numeric,
        'WF-SCORING-CANDIDATO-v1', payload->>'priority'
    ) RETURNING id INTO evaluation_id;

    INSERT INTO talentflow.score_criterion_results (
        score_evaluation_id, scoring_criterion_id, matched, points_awarded, evidence, explanation
    )
    SELECT evaluation_id, (item->>'criterion_id')::uuid, COALESCE((item->>'matched')::boolean, false),
           (item->>'points')::numeric, COALESCE(item->'evidence', '[]'::jsonb), item->>'explanation'
    FROM jsonb_array_elements(payload->'criteria') item;

    result := jsonb_build_object('evaluation_id', evaluation_id, 'score', (payload->>'score')::numeric,
        'priority', payload->>'priority', 'scoring_version', payload->>'scoring_version');
    RETURN result;
END;
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('019', 'Module 6 deterministic compatibility scoring persistence')
ON CONFLICT (version) DO NOTHING;

COMMIT;