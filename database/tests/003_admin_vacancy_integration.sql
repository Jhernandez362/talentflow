\set ON_ERROR_STOP on

BEGIN;

SELECT talentflow.admin_save_vacancy(
    jsonb_build_object(
        'title','Vacante Integral Temporal','code','TF-INTEGRATION-TEMP','department','Tecnologia',
        'description','Dato ficticio revertido al terminar la prueba','workMode','REMOTE','location','Colombia',
        'contractType','Indefinido','seniorityLevel','JUNIOR','openings',1,'workday','Completa','schedule','Flexible',
        'salaryMin','','salaryMax','','salaryCurrency','COP','salaryPeriod','MONTH','showSalaryPublicly',false,
        'plannedPublishAt',(now()+interval '1 day')::text,'closesAt',(now()+interval '30 days')::text,
        'responsibleHrUserId','10000000-0000-4000-8000-000000000001',
        'benefits',jsonb_build_array(jsonb_build_object('name','Horario flexible','order',0)),
        'criteria',jsonb_build_array(
            jsonb_build_object('name','Java','type','TECNOLOGIA','weight',50,'required',true,'aliases',jsonb_build_array('Java SE'),'order',0),
            jsonb_build_object('name','SQL','type','CONOCIMIENTO','weight',50,'required',false,'aliases','[]'::jsonb,'order',1)
        ),
        'desirables',jsonb_build_array(jsonb_build_object('name','Docker','description','','relevance','MEDIUM','order',0)),
        'addedValues',jsonb_build_array(jsonb_build_object('name','Scrum','description','','type','SCRUM','relevance','LOW','order',0))
    ), true
) AS published_vacancy;

DO $$
DECLARE
    status_found varchar(20);
    total_found integer;
BEGIN
    SELECT v.status, sum(c.weight)::integer INTO status_found, total_found
    FROM talentflow.vacancies v
    JOIN talentflow.scoring_config_versions s ON s.vacancy_id=v.id AND s.status='PUBLISHED'
    JOIN talentflow.scoring_criteria c ON c.scoring_config_version_id=s.id
    WHERE v.code='TF-INTEGRATION-TEMP'
    GROUP BY v.status;
    IF status_found <> 'OPEN' OR total_found <> 100 THEN
        RAISE EXCEPTION 'Expected OPEN/100, got %/%', status_found, total_found;
    END IF;
END;
$$;

SELECT talentflow.admin_duplicate_vacancy(
    (SELECT id FROM talentflow.vacancies WHERE code='TF-INTEGRATION-TEMP'),
    'TF-INTEGRATION-COPY'
) AS duplicated_vacancy;

DO $$
DECLARE copied_status varchar(20); copied_total integer;
BEGIN
    SELECT v.status, sum(c.weight)::integer INTO copied_status, copied_total
    FROM talentflow.vacancies v
    JOIN talentflow.scoring_config_versions s ON s.vacancy_id=v.id
    JOIN talentflow.scoring_criteria c ON c.scoring_config_version_id=s.id
    WHERE v.code='TF-INTEGRATION-COPY' GROUP BY v.status;
    IF copied_status <> 'DRAFT' OR copied_total <> 100 THEN
        RAISE EXCEPTION 'Expected duplicated vacancy DRAFT/100, got %/%', copied_status, copied_total;
    END IF;
END;
$$;

ROLLBACK;
SELECT 'Admin vacancy integration test passed and rolled back' AS result;
