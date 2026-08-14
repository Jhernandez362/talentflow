BEGIN;

CREATE OR REPLACE FUNCTION talentflow.admin_list_vacancies()
RETURNS jsonb LANGUAGE sql STABLE AS $$
SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.created_at DESC), '[]'::jsonb)
FROM (
    SELECT v.id, v.code, v.title, v.department, v.seniority_level, v.work_mode,
           v.status, v.priority, v.closes_at, v.openings, v.created_at,
           count(DISTINCT a.id)::integer AS application_count,
           max(s.version) FILTER (WHERE s.status = 'PUBLISHED') AS active_scoring_version
    FROM talentflow.vacancies v
    LEFT JOIN talentflow.applications a ON a.vacancy_id = v.id
    LEFT JOIN talentflow.scoring_config_versions s ON s.vacancy_id = v.id
    GROUP BY v.id
) item;
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_get_vacancy(target_id uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
SELECT jsonb_build_object(
    'vacancy', to_jsonb(v),
    'benefits', COALESCE((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.display_order) FROM talentflow.vacancy_benefits b WHERE b.vacancy_id = v.id), '[]'::jsonb),
    'scoring', COALESCE((SELECT jsonb_build_object(
        'id', s.id, 'version', s.version, 'status', s.status,
        'criteria', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.evaluation_order) FROM talentflow.scoring_criteria c WHERE c.scoring_config_version_id = s.id), '[]'::jsonb),
        'desirables', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.display_order) FROM talentflow.desirable_requirements d WHERE d.scoring_config_version_id = s.id), '[]'::jsonb),
        'addedValues', COALESCE((SELECT jsonb_agg(to_jsonb(av) ORDER BY av.display_order) FROM talentflow.added_value_requirements av WHERE av.scoring_config_version_id = s.id), '[]'::jsonb)
    ) FROM talentflow.scoring_config_versions s WHERE s.vacancy_id = v.id ORDER BY s.version DESC LIMIT 1), '{}'::jsonb)
)
FROM talentflow.vacancies v WHERE v.id = target_id;
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_save_vacancy(payload jsonb, publish_now boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $$
#variable_conflict use_variable
DECLARE
    vacancy_id uuid := NULLIF(payload->>'id', '')::uuid;
    actor_id uuid := COALESCE(NULLIF(payload->>'responsibleHrUserId', '')::uuid, (SELECT id FROM talentflow.hr_users WHERE is_active ORDER BY created_at LIMIT 1));
    config_id uuid;
    current_config_status varchar(20);
    next_version integer;
    criterion jsonb;
    item jsonb;
    total integer;
    requested_status varchar(20) := CASE WHEN publish_now THEN 'OPEN' ELSE 'DRAFT' END;
BEGIN
    IF actor_id IS NULL THEN RAISE EXCEPTION 'An active HR user is required'; END IF;
    IF btrim(COALESCE(payload->>'title', '')) = '' OR btrim(COALESCE(payload->>'code', '')) = '' THEN
        RAISE EXCEPTION 'Title and code are required';
    END IF;
    IF (payload->>'salaryMin')::numeric > (payload->>'salaryMax')::numeric THEN
        RAISE EXCEPTION 'Minimum salary cannot exceed maximum salary';
    END IF;
    IF NULLIF(payload->>'closesAt', '')::timestamptz IS NOT NULL
       AND NULLIF(payload->>'plannedPublishAt', '')::timestamptz IS NOT NULL
       AND (payload->>'closesAt')::timestamptz <= (payload->>'plannedPublishAt')::timestamptz THEN
        RAISE EXCEPTION 'Closing date must be after publication date';
    END IF;

    SELECT COALESCE(sum((value->>'weight')::integer), 0) INTO total
    FROM jsonb_array_elements(COALESCE(payload->'criteria', '[]'));
    IF publish_now AND (jsonb_array_length(COALESCE(payload->'criteria', '[]')) = 0 OR total <> 100) THEN
        RAISE EXCEPTION 'Publishing requires at least one criterion totaling exactly 100; current total is %', total;
    END IF;

    IF vacancy_id IS NULL THEN
        vacancy_id := gen_random_uuid();
        INSERT INTO talentflow.vacancies (
            id, code, title, department, description, work_mode, location, contract_type,
            seniority_level, openings, workday, schedule, salary_min, salary_max,
            salary_currency, salary_period, show_salary_publicly, planned_publish_at,
            closes_at, expected_start_date, responsible_hr_user_id, minimum_experience_months,
            expected_experience_min_months, expected_experience_max_months, minimum_education,
            related_academic_area, education_required, education_affects_score, status,
            created_by, updated_by, published_at
        ) VALUES (
            vacancy_id, upper(btrim(payload->>'code')), btrim(payload->>'title'), NULLIF(payload->>'department',''), payload->>'description',
            NULLIF(payload->>'workMode',''), NULLIF(payload->>'location',''), NULLIF(payload->>'contractType',''), NULLIF(payload->>'seniorityLevel',''),
            COALESCE((payload->>'openings')::integer, 1), NULLIF(payload->>'workday',''), NULLIF(payload->>'schedule',''),
            NULLIF(payload->>'salaryMin','')::numeric, NULLIF(payload->>'salaryMax','')::numeric, COALESCE(NULLIF(payload->>'salaryCurrency',''),'COP'),
            NULLIF(payload->>'salaryPeriod',''), COALESCE((payload->>'showSalaryPublicly')::boolean,false), NULLIF(payload->>'plannedPublishAt','')::timestamptz,
            NULLIF(payload->>'closesAt','')::timestamptz, NULLIF(payload->>'expectedStartDate','')::date, actor_id,
            NULLIF(payload->>'minimumExperienceMonths','')::integer, NULLIF(payload->>'expectedExperienceMinMonths','')::integer,
            NULLIF(payload->>'expectedExperienceMaxMonths','')::integer, COALESCE(NULLIF(payload->>'minimumEducation',''),'NONE'),
            NULLIF(payload->>'relatedAcademicArea',''), COALESCE((payload->>'educationRequired')::boolean,false),
            COALESCE((payload->>'educationAffectsScore')::boolean,false), requested_status, actor_id, actor_id,
            CASE WHEN publish_now THEN now() END
        );
        next_version := 1;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM talentflow.vacancies WHERE id = vacancy_id) THEN RAISE EXCEPTION 'Vacancy not found'; END IF;
        UPDATE talentflow.vacancies SET
            code=upper(btrim(payload->>'code')), title=btrim(payload->>'title'), department=NULLIF(payload->>'department',''), description=payload->>'description',
            work_mode=NULLIF(payload->>'workMode',''), location=NULLIF(payload->>'location',''), contract_type=NULLIF(payload->>'contractType',''),
            seniority_level=NULLIF(payload->>'seniorityLevel',''), openings=COALESCE((payload->>'openings')::integer,1), workday=NULLIF(payload->>'workday',''),
            schedule=NULLIF(payload->>'schedule',''), salary_min=NULLIF(payload->>'salaryMin','')::numeric, salary_max=NULLIF(payload->>'salaryMax','')::numeric,
            salary_currency=COALESCE(NULLIF(payload->>'salaryCurrency',''),'COP'), salary_period=NULLIF(payload->>'salaryPeriod',''),
            show_salary_publicly=COALESCE((payload->>'showSalaryPublicly')::boolean,false), planned_publish_at=NULLIF(payload->>'plannedPublishAt','')::timestamptz,
            closes_at=NULLIF(payload->>'closesAt','')::timestamptz, expected_start_date=NULLIF(payload->>'expectedStartDate','')::date,
            responsible_hr_user_id=actor_id, minimum_experience_months=NULLIF(payload->>'minimumExperienceMonths','')::integer,
            expected_experience_min_months=NULLIF(payload->>'expectedExperienceMinMonths','')::integer,
            expected_experience_max_months=NULLIF(payload->>'expectedExperienceMaxMonths','')::integer,
            minimum_education=COALESCE(NULLIF(payload->>'minimumEducation',''),'NONE'), related_academic_area=NULLIF(payload->>'relatedAcademicArea',''),
            education_required=COALESCE((payload->>'educationRequired')::boolean,false), education_affects_score=COALESCE((payload->>'educationAffectsScore')::boolean,false),
            updated_by=actor_id
        WHERE id=vacancy_id;
        SELECT s.id, s.status INTO config_id, current_config_status FROM talentflow.scoring_config_versions s WHERE s.vacancy_id=vacancy_id ORDER BY s.version DESC LIMIT 1;
        IF current_config_status IN ('PUBLISHED','ARCHIVED') THEN
            config_id := NULL;
        END IF;
        SELECT COALESCE(max(s.version),0)+1 INTO next_version FROM talentflow.scoring_config_versions s WHERE s.vacancy_id=vacancy_id;
    END IF;

    DELETE FROM talentflow.vacancy_benefits b WHERE b.vacancy_id=vacancy_id;
    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(payload->'benefits','[]')) LOOP
        INSERT INTO talentflow.vacancy_benefits(vacancy_id,name,display_order) VALUES(vacancy_id,btrim(item->>'name'),COALESCE((item->>'order')::smallint,0));
    END LOOP;

    IF config_id IS NULL THEN
        INSERT INTO talentflow.scoring_config_versions(vacancy_id,version,status,created_by)
        VALUES(vacancy_id,next_version,'DRAFT',actor_id) RETURNING id INTO config_id;
    ELSE
        DELETE FROM talentflow.scoring_criteria WHERE scoring_config_version_id=config_id;
        DELETE FROM talentflow.desirable_requirements WHERE scoring_config_version_id=config_id;
        DELETE FROM talentflow.added_value_requirements WHERE scoring_config_version_id=config_id;
    END IF;

    FOR criterion IN SELECT value FROM jsonb_array_elements(COALESCE(payload->'criteria','[]')) LOOP
        INSERT INTO talentflow.scoring_criteria(scoring_config_version_id,code,name,criterion_type,description,weight,evaluation_order,is_required,aliases)
        VALUES(config_id, upper(regexp_replace(btrim(criterion->>'name'),'[^a-zA-Z0-9]+','_','g')), btrim(criterion->>'name'), criterion->>'type',
               NULLIF(criterion->>'description',''), (criterion->>'weight')::smallint, COALESCE((criterion->>'order')::smallint,0),
               COALESCE((criterion->>'required')::boolean,false), ARRAY(SELECT jsonb_array_elements_text(COALESCE(criterion->'aliases','[]'))));
    END LOOP;
    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(payload->'desirables','[]')) LOOP
        INSERT INTO talentflow.desirable_requirements(scoring_config_version_id,name,description,relevance,display_order)
        VALUES(config_id,btrim(item->>'name'),NULLIF(item->>'description',''),item->>'relevance',COALESCE((item->>'order')::smallint,0));
    END LOOP;
    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(payload->'addedValues','[]')) LOOP
        INSERT INTO talentflow.added_value_requirements(scoring_config_version_id,name,description,requirement_type,relevance,display_order)
        VALUES(config_id,btrim(item->>'name'),NULLIF(item->>'description',''),item->>'type',item->>'relevance',COALESCE((item->>'order')::smallint,0));
    END LOOP;

    IF publish_now THEN
        UPDATE talentflow.scoring_config_versions s SET status='ARCHIVED'
        WHERE s.vacancy_id=vacancy_id AND s.status='PUBLISHED' AND s.id<>config_id;
        UPDATE talentflow.scoring_config_versions SET status='PUBLISHED',published_by=actor_id WHERE id=config_id;
        UPDATE talentflow.vacancies SET status='OPEN',published_at=COALESCE(published_at,now()) WHERE id=vacancy_id;
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;
    RETURN talentflow.admin_get_vacancy(vacancy_id);
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_change_vacancy_status(target_id uuid, target_status varchar)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
    IF target_status NOT IN ('PAUSED','OPEN','CLOSED','COMPLETED') THEN RAISE EXCEPTION 'Invalid target status'; END IF;
    IF target_status='OPEN' AND NOT EXISTS (
        SELECT 1 FROM talentflow.scoring_config_versions s JOIN talentflow.scoring_criteria c ON c.scoring_config_version_id=s.id
        WHERE s.vacancy_id=target_id AND s.status='PUBLISHED' GROUP BY s.id HAVING sum(c.weight)=100
    ) THEN RAISE EXCEPTION 'Reopening requires a published scoring configuration totaling 100'; END IF;
    UPDATE talentflow.vacancies SET status=target_status, closed_at=CASE WHEN target_status='CLOSED' THEN now() ELSE closed_at END WHERE id=target_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found'; END IF;
    RETURN talentflow.admin_get_vacancy(target_id);
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_duplicate_vacancy(source_id uuid, new_code varchar)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE source jsonb; copy_payload jsonb;
BEGIN
    source := talentflow.admin_get_vacancy(source_id);
    IF source IS NULL THEN RAISE EXCEPTION 'Vacancy not found'; END IF;
    copy_payload := (source->'vacancy') || jsonb_build_object('id',NULL,'code',upper(btrim(new_code)),'title',(source->'vacancy'->>'title') || ' (copia)',
      'responsibleHrUserId',source->'vacancy'->>'responsible_hr_user_id','workMode',source->'vacancy'->>'work_mode','contractType',source->'vacancy'->>'contract_type',
      'seniorityLevel',source->'vacancy'->>'seniority_level','salaryMin',source->'vacancy'->>'salary_min','salaryMax',source->'vacancy'->>'salary_max',
      'salaryCurrency',source->'vacancy'->>'salary_currency','salaryPeriod',source->'vacancy'->>'salary_period','showSalaryPublicly',source->'vacancy'->'show_salary_publicly',
      'plannedPublishAt',NULL,'closesAt',NULL,'expectedStartDate',NULL,'minimumExperienceMonths',source->'vacancy'->>'minimum_experience_months',
      'expectedExperienceMinMonths',source->'vacancy'->>'expected_experience_min_months','expectedExperienceMaxMonths',source->'vacancy'->>'expected_experience_max_months',
      'minimumEducation',source->'vacancy'->>'minimum_education','relatedAcademicArea',source->'vacancy'->>'related_academic_area',
      'educationRequired',source->'vacancy'->'education_required','educationAffectsScore',source->'vacancy'->'education_affects_score',
      'benefits',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',b->>'name','order',b->'display_order')) FROM jsonb_array_elements(source->'benefits') b),'[]'::jsonb),
      'criteria',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',c->>'name','type',c->>'criterion_type','description',c->>'description','weight',c->'weight','required',c->'is_required','aliases',c->'aliases','order',c->'evaluation_order')) FROM jsonb_array_elements(source->'scoring'->'criteria') c),'[]'::jsonb),
      'desirables',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',d->>'name','description',d->>'description','relevance',d->>'relevance','order',d->'display_order')) FROM jsonb_array_elements(source->'scoring'->'desirables') d),'[]'::jsonb),
      'addedValues',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',a->>'name','description',a->>'description','type',a->>'requirement_type','relevance',a->>'relevance','order',a->'display_order')) FROM jsonb_array_elements(source->'scoring'->'addedValues') a),'[]'::jsonb));
    RETURN talentflow.admin_save_vacancy(copy_payload,false);
END;
$$;

INSERT INTO talentflow.schema_migrations(version,description) VALUES('006','Parameterized administrative vacancy API');
COMMIT;
