BEGIN;

DO $$
DECLARE
    definition text;
BEGIN
    SELECT pg_get_functiondef('talentflow.ia01_begin_analysis(uuid,text,text)'::regprocedure)
    INTO definition;
    definition := replace(definition, 'gemini-2.5-flash', 'gemini-3.6-flash');
    EXECUTE definition;
END;
$$;

INSERT INTO talentflow.schema_migrations(version, description)
VALUES ('022', 'Use Gemini 3.6 Flash required by the configured Generative Language API')
ON CONFLICT (version) DO NOTHING;

COMMIT;
