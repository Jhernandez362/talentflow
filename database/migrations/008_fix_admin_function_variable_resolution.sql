BEGIN;

DO $$
DECLARE
    definition text;
BEGIN
    SELECT pg_get_functiondef('talentflow.admin_save_vacancy_impl(jsonb,boolean)'::regprocedure)
    INTO definition;
    definition := replace(definition, E'AS $function$\nDECLARE', E'AS $function$\n#variable_conflict use_variable\nDECLARE');
    EXECUTE definition;
END;
$$;

INSERT INTO talentflow.schema_migrations(version,description)
VALUES('008','Resolve admin vacancy function variable and column names');
COMMIT;
