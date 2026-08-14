BEGIN;

DO $$
DECLARE definition text;
BEGIN
    SELECT pg_get_functiondef('talentflow.admin_save_vacancy_impl(jsonb,boolean)'::regprocedure) INTO definition;
    definition := replace(definition, 'FROM talentflow.scoring_config_versions WHERE vacancy_id=vacancy_id ORDER BY version DESC', 'FROM talentflow.scoring_config_versions s WHERE s.vacancy_id=vacancy_id ORDER BY s.version DESC');
    definition := replace(definition, 'FROM talentflow.scoring_config_versions WHERE vacancy_id=vacancy_id;', 'FROM talentflow.scoring_config_versions s WHERE s.vacancy_id=vacancy_id;');
    definition := replace(definition, 'DELETE FROM talentflow.vacancy_benefits WHERE vacancy_id=vacancy_id;', 'DELETE FROM talentflow.vacancy_benefits b WHERE b.vacancy_id=vacancy_id;');
    definition := replace(definition,
        E'            UPDATE talentflow.scoring_config_versions SET status=''ARCHIVED'' WHERE id=config_id AND status=''PUBLISHED'';\n            config_id := NULL;',
        E'            config_id := NULL;');
    definition := replace(definition,
        E'    IF publish_now THEN\n        UPDATE talentflow.scoring_config_versions SET status=''PUBLISHED'',published_by=actor_id WHERE id=config_id;',
        E'    IF publish_now THEN\n        UPDATE talentflow.scoring_config_versions s SET status=''ARCHIVED'' WHERE s.vacancy_id=vacancy_id AND s.status=''PUBLISHED'' AND s.id<>config_id;\n        UPDATE talentflow.scoring_config_versions SET status=''PUBLISHED'',published_by=actor_id WHERE id=config_id;');
    EXECUTE definition;
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_duplicate_vacancy(source_id uuid, new_code varchar)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE source jsonb; v jsonb; copy_payload jsonb;
BEGIN
    source := talentflow.admin_get_vacancy(source_id); v := source->'vacancy';
    IF source IS NULL THEN RAISE EXCEPTION 'Vacancy not found'; END IF;
    copy_payload := v || jsonb_build_object(
      'id',NULL,'code',upper(btrim(new_code)),'title',(v->>'title')||' (copia)','responsibleHrUserId',v->>'responsible_hr_user_id',
      'workMode',v->>'work_mode','contractType',v->>'contract_type','seniorityLevel',v->>'seniority_level','salaryMin',v->>'salary_min',
      'salaryMax',v->>'salary_max','salaryCurrency',v->>'salary_currency','salaryPeriod',v->>'salary_period','showSalaryPublicly',v->'show_salary_publicly',
      'plannedPublishAt',NULL,'closesAt',NULL,'expectedStartDate',NULL,'minimumExperienceMonths',v->>'minimum_experience_months',
      'expectedExperienceMinMonths',v->>'expected_experience_min_months','expectedExperienceMaxMonths',v->>'expected_experience_max_months',
      'minimumEducation',v->>'minimum_education','relatedAcademicArea',v->>'related_academic_area','educationRequired',v->'education_required',
      'educationAffectsScore',v->'education_affects_score',
      'benefits',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',b->>'name','order',b->'display_order')) FROM jsonb_array_elements(source->'benefits') b),'[]'::jsonb),
      'criteria',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',c->>'name','type',c->>'criterion_type','description',c->>'description','weight',c->'weight','required',c->'is_required','aliases',c->'aliases','order',c->'evaluation_order')) FROM jsonb_array_elements(source->'scoring'->'criteria') c),'[]'::jsonb),
      'desirables',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',d->>'name','description',d->>'description','relevance',d->>'relevance','order',d->'display_order')) FROM jsonb_array_elements(source->'scoring'->'desirables') d),'[]'::jsonb),
      'addedValues',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',a->>'name','description',a->>'description','type',a->>'requirement_type','relevance',a->>'relevance','order',a->'display_order')) FROM jsonb_array_elements(source->'scoring'->'addedValues') a),'[]'::jsonb));
    RETURN talentflow.admin_save_vacancy(copy_payload,false);
END;
$$;

INSERT INTO talentflow.schema_migrations(version,description) VALUES('009','Preserve active scoring version and map vacancy duplication');
COMMIT;
