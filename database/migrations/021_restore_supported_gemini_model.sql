BEGIN;

DO $$
DECLARE
    definition text;
BEGIN
    SELECT pg_get_functiondef('talentflow.ia01_begin_analysis(uuid,text,text)'::regprocedure)
    INTO definition;
    definition := replace(definition, 'gemini-3.6-flash', 'gemini-2.5-flash');
    EXECUTE definition;
END;
$$;

INSERT INTO talentflow.schema_migrations(version, description)
VALUES ('021', 'Restore supported Gemini 2.5 Flash model for IA-01')
ON CONFLICT (version) DO NOTHING;

COMMIT;
