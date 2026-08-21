BEGIN;

-- =========================================================================
-- Modulo 9: autorizar usuarios de Telegram desde un workflow ADMIN en vez
-- de un INSERT manual. Usa el mismo patron admin_* (actorId validado con
-- talentflow.require_active_hr) que el resto de TF-ADMIN-*. Este endpoint
-- corre con el rol de escritura normal de la app (talentflow_app), nunca
-- con talentflow_bot_readonly: el bot sigue sin poder autorizarse a si
-- mismo ni a nadie.
--
-- El panel de RRHH identifica al usuario por su correo (hr_users.email),
-- no por su UUID: la funcion resuelve el hr_user_id y el nombre a mostrar
-- a partir del correo.
-- =========================================================================

CREATE OR REPLACE FUNCTION talentflow.admin_authorize_telegram_user(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  actor uuid = (payload->>'actorId')::uuid;
  target_hr talentflow.hr_users%ROWTYPE;
  tg_id bigint = (payload->>'telegramUserId')::bigint;
  input_email text = NULLIF(btrim(payload->>'email'), '');
BEGIN
  PERFORM talentflow.require_active_hr(actor);

  IF tg_id IS NULL OR tg_id <= 0 THEN
    RAISE EXCEPTION 'INVALID_TELEGRAM_USER_ID';
  END IF;

  IF input_email IS NULL THEN
    RAISE EXCEPTION 'EMAIL_REQUIRED';
  END IF;

  SELECT * INTO target_hr FROM talentflow.hr_users WHERE email = input_email AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'HR_USER_NOT_FOUND';
  END IF;

  INSERT INTO talentflow.bot_authorized_telegram_users
    (telegram_user_id, hr_user_id, telegram_display_name, is_active, added_by)
  VALUES (tg_id, target_hr.id, target_hr.display_name, true, actor)
  ON CONFLICT (telegram_user_id) DO UPDATE SET
    hr_user_id = EXCLUDED.hr_user_id,
    telegram_display_name = EXCLUDED.telegram_display_name,
    is_active = true,
    added_by = EXCLUDED.added_by;

  RETURN jsonb_build_object(
    'telegramUserId', tg_id,
    'hrUserId', target_hr.id,
    'email', target_hr.email,
    'displayName', target_hr.display_name,
    'isActive', true
  );
END; $$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('028', 'Module 9 admin endpoint to authorize Telegram bot users')
ON CONFLICT (version) DO NOTHING;

COMMIT;
