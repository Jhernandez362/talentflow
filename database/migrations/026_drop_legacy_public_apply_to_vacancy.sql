BEGIN;

-- public_apply_to_vacancy (migration 010) was superseded by the two-phase
-- public_begin_application + public_record_document_attempt flow introduced
-- in migration 012 (Module 4). It is not referenced by any n8n workflow or
-- by the frontend, and it predates the ticket_id NOT NULL constraint, so it
-- has been unusable since migration 012 landed.
DROP FUNCTION IF EXISTS talentflow.public_apply_to_vacancy(jsonb);

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('026', 'Drop unused legacy public_apply_to_vacancy function')
ON CONFLICT (version) DO NOTHING;

COMMIT;
