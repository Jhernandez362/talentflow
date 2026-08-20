\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    vacancy_id uuid; config_id uuid; candidate_id uuid := gen_random_uuid();
    target_application_id uuid := gen_random_uuid(); extraction_id uuid := gen_random_uuid();
    summary_context jsonb; question_context jsonb; criteria_payload jsonb;
BEGIN
    SELECT vacancy.id, config.id INTO vacancy_id, config_id
    FROM talentflow.vacancies vacancy
    JOIN talentflow.scoring_config_versions config ON config.vacancy_id=vacancy.id AND config.status='PUBLISHED'
    LIMIT 1;
    IF vacancy_id IS NULL THEN RAISE EXCEPTION 'Se requiere una vacante con scoring publicado'; END IF;

    INSERT INTO talentflow.candidates(id,email,full_name)
    VALUES(candidate_id,candidate_id||'@module7.test','Candidato Modulo 7');
    INSERT INTO talentflow.applications(id,vacancy_id,candidate_id,ticket_id,status,source)
    VALUES(target_application_id,vacancy_id,candidate_id,'TF-M7-'||left(target_application_id::text,8),'ANALIZADO','MODULE-7-TEST');
    INSERT INTO talentflow.ai_analyses(id,application_id,analysis_type,status,provider,model,prompt_code,prompt_version,structured_output,started_at,completed_at)
    VALUES(extraction_id,target_application_id,'CV_EXTRACTION','SUCCEEDED','test','test','PROMPT-IA-01','PROMPT-IA-01-v1',
      '{"experiencia_total_anios":2,"experiencias":[{"id":"EXP-2","empresa":"Empresa X","cargo":"Dev","funciones":[],"tecnologias":["Docker"]}],"educacion":[],"cursos":[],"certificaciones":[],"idiomas":[],"habilidades":[{"nombre":"Docker","evidencia_laboral":true,"experiencia_ids":["EXP-2"]}],"habilidades_declaradas_no_verificadas":["AWS"],"advertencias":[]}'::jsonb,now(),now());

    SELECT jsonb_agg(jsonb_build_object('criterion',criterion.name,'criterion_id',criterion.id,
        'weight',criterion.weight,'points',0,'matched',false,'mandatory',criterion.is_required,
        'work_evidence',false,'explanation','Fixture Modulo 7') ORDER BY criterion.evaluation_order)
    INTO criteria_payload FROM talentflow.scoring_criteria criterion WHERE criterion.scoring_config_version_id=config_id;
    PERFORM talentflow.persist_deterministic_score(jsonb_build_object(
        'postulacion_id',target_application_id,'analysis_id',extraction_id,'vacancy_id',vacancy_id,
        'scoring_version_id',config_id,'scoring_version',(SELECT version FROM talentflow.scoring_config_versions WHERE id=config_id),
        'score',0,'priority','BAJA','criteria',criteria_payload,'mandatory_missing','[]'::jsonb,
        'desired_found','[]'::jsonb,'desired_missing','[]'::jsonb,'added_value','[]'::jsonb,
        'added_value_missing','[]'::jsonb,'seniority_fit','ALINEADO'));

    summary_context := talentflow.ia02_begin_summary(target_application_id,'test','test-model');
    question_context := talentflow.ia03_begin_questions(target_application_id,'test','test-model');
    PERFORM talentflow.ia02_complete_summary((summary_context->>'analysis_id')::uuid,
        '{"summary":"Perfil con experiencia documentada en Docker.","key_points":["Docker con evidencia laboral"]}'::jsonb);
    PERFORM talentflow.ia03_complete_questions((question_context->>'analysis_id')::uuid,
        '{"questions":[{"topic":"Docker","question":"¿Cómo utilizaste Docker durante tu trabajo en Empresa X?","source_type":"WORK_EXPERIENCE","evidence":"Docker en EXP-2","experience_id":"EXP-2"},{"topic":"AWS","question":"Indicas conocimiento de AWS. ¿En qué contextos lo has utilizado?","source_type":"DECLARED_SKILL","evidence":"Habilidad declarada","experience_id":null}]}'::jsonb);
    IF (SELECT count(*) FROM talentflow.suggested_questions question WHERE question.application_id=target_application_id) <> 2
       OR NOT EXISTS (SELECT 1 FROM talentflow.ai_analyses analysis WHERE analysis.application_id=target_application_id AND analysis.analysis_type='PROFESSIONAL_SUMMARY' AND analysis.status='SUCCEEDED')
       OR NOT EXISTS (SELECT 1 FROM talentflow.ai_analyses analysis WHERE analysis.application_id=target_application_id AND analysis.analysis_type='INTERVIEW_QUESTIONS' AND analysis.status='SUCCEEDED')
    THEN RAISE EXCEPTION 'Persistencia independiente del Modulo 7 incompleta'; END IF;
END;
$$;
ROLLBACK;
SELECT 'Module 7 IA-02/IA-03 persistence test passed and rolled back' AS result;
