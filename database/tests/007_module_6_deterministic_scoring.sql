\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    actor_id uuid := gen_random_uuid();
    vacancy_id uuid := gen_random_uuid();
    config_id uuid := gen_random_uuid();
    candidate_id uuid := gen_random_uuid();
    application_id uuid := gen_random_uuid();
    analysis_id uuid := gen_random_uuid();
    skill_id uuid := gen_random_uuid();
    experience_id uuid := gen_random_uuid();
    education_id uuid := gen_random_uuid();
    result jsonb;
    evaluation_id uuid;
    payload jsonb;
BEGIN
    INSERT INTO talentflow.hr_users(id, email, display_name, role)
    VALUES(actor_id, actor_id || '@module6.test', 'Prueba Modulo 6', 'ADMIN');

    INSERT INTO talentflow.vacancies(
        id, code, title, status, priority, created_by, updated_by,
        responsible_hr_user_id, minimum_experience_months,
        expected_experience_min_months, expected_experience_max_months,
        minimum_education, education_required, education_affects_score
    ) VALUES (
        vacancy_id, 'M6-' || left(vacancy_id::text, 8), 'Vacante prueba Modulo 6',
        'DRAFT', 'NORMAL', actor_id, actor_id, actor_id, 24, 24, 48,
        'TECHNICAL', true, true
    );

    INSERT INTO talentflow.scoring_config_versions(id, vacancy_id, version, status, created_by)
    VALUES(config_id, vacancy_id, 1, 'DRAFT', actor_id);
    INSERT INTO talentflow.scoring_criteria(
        id, scoring_config_version_id, code, name, criterion_type,
        weight, evaluation_order, evaluation_rule, is_required, aliases
    ) VALUES
        (skill_id, config_id, 'REACT', 'React', 'TECNOLOGIA', 40, 1, '{"aliases":["ReactJS"]}', true, ARRAY['React.js']),
        (experience_id, config_id, 'EXP', 'Experiencia', 'EXPERIENCIA', 20, 2, '{"required_years":2}', false, '{}'),
        (education_id, config_id, 'EDU', 'Educacion', 'EDUCACION', 40, 3, '{"minimum_level":"TECNICO"}', false, '{}');
    INSERT INTO talentflow.desirable_requirements(scoring_config_version_id, name)
    VALUES(config_id, 'Docker');
    INSERT INTO talentflow.added_value_requirements(scoring_config_version_id, name)
    VALUES(config_id, 'AWS');
    UPDATE talentflow.scoring_config_versions
    SET status='PUBLISHED', published_by=actor_id
    WHERE id=config_id;

    INSERT INTO talentflow.candidates(id, email, full_name)
    VALUES(candidate_id, candidate_id || '@module6.test', 'Candidato Modulo 6');
    INSERT INTO talentflow.applications(id, vacancy_id, candidate_id, status, source)
    VALUES(application_id, vacancy_id, candidate_id, 'RECEIVED', 'MODULE-6-TEST');
    INSERT INTO talentflow.ai_analyses(id, application_id, analysis_type, status, structured_output)
    VALUES(analysis_id, application_id, 'CV_EXTRACTION', 'SUCCEEDED',
      '{"experiencia_total_anios":1,"experiencias":[],"educacion":[{"nivel":"TECNICO"}],"cursos":[],"certificaciones":[],"idiomas":[],"habilidades":[{"nombre":"ReactJS","evidencia_laboral":true,"experiencia_ids":[]}],"habilidades_declaradas_no_verificadas":[],"advertencias":[]}'::jsonb);

    payload := jsonb_build_object(
        'postulacion_id', application_id, 'analysis_id', analysis_id,
        'vacancy_id', vacancy_id, 'scoring_version_id', config_id,
        'scoring_version', 1, 'score', 90, 'priority', 'ALTA',
        'criteria', jsonb_build_array(
            jsonb_build_object('criterion','React','criterion_id',skill_id,'weight',40,'points',40,'matched',true,'mandatory',true,'work_evidence',true,'explanation','Alias configurado'),
            jsonb_build_object('criterion','Experiencia','criterion_id',experience_id,'weight',20,'points',10,'matched',false,'mandatory',false,'work_evidence',false,'explanation','Experiencia proporcional'),
            jsonb_build_object('criterion','Educacion','criterion_id',education_id,'weight',40,'points',40,'matched',true,'mandatory',false,'work_evidence',false,'explanation','Nivel suficiente')
        ),
        'mandatory_missing', '[]'::jsonb,
        'desired_found', '["Docker"]'::jsonb, 'desired_missing', '[]'::jsonb,
        'added_value', '["AWS"]'::jsonb, 'added_value_missing', '[]'::jsonb,
        'seniority_fit', 'POR_DEBAJO'
    );

    result := talentflow.persist_deterministic_score(payload);
    evaluation_id := (result->>'evaluation_id')::uuid;

    IF (result->>'score')::numeric <> 90
       OR result->>'priority' <> 'ALTA'
       OR result->>'scoring_version' <> '1'
       OR result->>'seniority_fit' <> 'POR_DEBAJO'
       OR result->'desired_found' <> '["Docker"]'::jsonb
       OR result->'added_value' <> '["AWS"]'::jsonb
       OR (SELECT stored.analysis_id FROM talentflow.score_evaluations stored WHERE stored.id=evaluation_id) <> analysis_id
       OR (SELECT stored.result_breakdown->>'seniority_fit' FROM talentflow.score_evaluations stored WHERE stored.id=evaluation_id) <> 'POR_DEBAJO'
       OR (SELECT count(*) FROM talentflow.score_criterion_results detail WHERE detail.score_evaluation_id=evaluation_id) <> 3
    THEN
        RAISE EXCEPTION 'Persistencia auditable del Modulo 6 incompleta';
    END IF;

    BEGIN
        PERFORM talentflow.persist_deterministic_score(payload);
        RAISE EXCEPTION 'Se permitio recalcular automaticamente la misma version';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%SCORE_ALREADY_EXISTS_FOR_VERSION%' THEN RAISE; END IF;
    END;

    payload := payload || '{"priority":"BAJA"}'::jsonb;
    BEGIN
        PERFORM talentflow.persist_deterministic_score(payload);
        RAISE EXCEPTION 'Se permitio prioridad inconsistente';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%does not correspond%' THEN RAISE; END IF;
    END;
END;
$$;

ROLLBACK;
SELECT 'Module 6 deterministic persistence and audit test passed and rolled back' AS result;
