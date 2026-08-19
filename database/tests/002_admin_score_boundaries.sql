\set ON_ERROR_STOP on

DO $$
DECLARE
    base jsonb := jsonb_build_object(
        'title','Prueba Administrativa','code','TF-BOUNDARY','department','Tecnologia',
        'workMode','REMOTE','seniorityLevel','JUNIOR','openings',1,
        'closesAt','2099-12-31T23:59:59Z',
        'salaryMin','','salaryMax','','salaryCurrency','COP','salaryPeriod','MONTH',
        'responsibleHrUserId','10000000-0000-4000-8000-000000000001'
    );
BEGIN
    BEGIN
        PERFORM talentflow.validate_admin_vacancy_payload(base || jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('name','Prueba 99','type','OTRO','weight',99))), true);
        RAISE EXCEPTION 'Score 99 was unexpectedly accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'Score 99 was unexpectedly accepted%%' THEN RAISE; END IF;
    END;

    PERFORM talentflow.validate_admin_vacancy_payload(base || jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('name','Prueba 100','type','OTRO','weight',100))), true);

    BEGIN
        PERFORM talentflow.validate_admin_vacancy_payload(base || jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('name','Prueba 101','type','OTRO','weight',101))), true);
        RAISE EXCEPTION 'Score 101 was unexpectedly accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'Score 101 was unexpectedly accepted%%' THEN RAISE; END IF;
    END;
END;
$$;

SELECT 'Admin score boundaries 99/100/101 passed' AS result;
