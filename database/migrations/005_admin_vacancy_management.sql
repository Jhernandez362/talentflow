BEGIN;

ALTER TABLE talentflow.vacancies
    ADD COLUMN department varchar(120),
    ADD COLUMN work_mode varchar(20),
    ADD COLUMN location varchar(160),
    ADD COLUMN contract_type varchar(80),
    ADD COLUMN seniority_level varchar(20),
    ADD COLUMN openings integer NOT NULL DEFAULT 1,
    ADD COLUMN workday varchar(80),
    ADD COLUMN schedule varchar(160),
    ADD COLUMN salary_min numeric(14,2),
    ADD COLUMN salary_max numeric(14,2),
    ADD COLUMN salary_currency char(3) NOT NULL DEFAULT 'COP',
    ADD COLUMN salary_period varchar(20),
    ADD COLUMN show_salary_publicly boolean NOT NULL DEFAULT false,
    ADD COLUMN planned_publish_at timestamptz,
    ADD COLUMN closes_at timestamptz,
    ADD COLUMN expected_start_date date,
    ADD COLUMN responsible_hr_user_id uuid REFERENCES talentflow.hr_users(id) ON DELETE RESTRICT,
    ADD COLUMN minimum_experience_months integer,
    ADD COLUMN expected_experience_min_months integer,
    ADD COLUMN expected_experience_max_months integer,
    ADD COLUMN minimum_education varchar(30) NOT NULL DEFAULT 'NONE',
    ADD COLUMN related_academic_area varchar(160),
    ADD COLUMN education_required boolean NOT NULL DEFAULT false,
    ADD COLUMN education_affects_score boolean NOT NULL DEFAULT false,
    ADD CONSTRAINT vacancies_work_mode_valid CHECK (work_mode IS NULL OR work_mode IN ('ONSITE', 'REMOTE', 'HYBRID')),
    ADD CONSTRAINT vacancies_seniority_valid CHECK (seniority_level IS NULL OR seniority_level IN ('INTERN', 'JUNIOR', 'MID', 'SENIOR', 'LEAD', 'OTHER')),
    ADD CONSTRAINT vacancies_openings_positive CHECK (openings > 0),
    ADD CONSTRAINT vacancies_salary_nonnegative CHECK ((salary_min IS NULL OR salary_min >= 0) AND (salary_max IS NULL OR salary_max >= 0)),
    ADD CONSTRAINT vacancies_salary_range CHECK (salary_min IS NULL OR salary_max IS NULL OR salary_min <= salary_max),
    ADD CONSTRAINT vacancies_salary_period_valid CHECK (salary_period IS NULL OR salary_period IN ('HOUR', 'DAY', 'WEEK', 'MONTH', 'YEAR')),
    ADD CONSTRAINT vacancies_currency_format CHECK (salary_currency ~ '^[A-Z]{3}$'),
    ADD CONSTRAINT vacancies_experience_nonnegative CHECK (
        (minimum_experience_months IS NULL OR minimum_experience_months >= 0)
        AND (expected_experience_min_months IS NULL OR expected_experience_min_months >= 0)
        AND (expected_experience_max_months IS NULL OR expected_experience_max_months >= 0)
    ),
    ADD CONSTRAINT vacancies_experience_range CHECK (
        expected_experience_min_months IS NULL OR expected_experience_max_months IS NULL
        OR expected_experience_min_months <= expected_experience_max_months
    ),
    ADD CONSTRAINT vacancies_education_valid CHECK (minimum_education IN ('NONE', 'HIGH_SCHOOL', 'TECHNICAL', 'TECHNOLOGIST', 'PROFESSIONAL', 'SPECIALIZATION', 'MASTER', 'DOCTORATE')),
    ADD CONSTRAINT vacancies_dates_valid CHECK (closes_at IS NULL OR planned_publish_at IS NULL OR closes_at > planned_publish_at);

UPDATE talentflow.vacancies
SET responsible_hr_user_id = created_by
WHERE responsible_hr_user_id IS NULL;

CREATE TABLE talentflow.vacancy_benefits (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vacancy_id uuid NOT NULL REFERENCES talentflow.vacancies(id) ON DELETE CASCADE,
    name varchar(160) NOT NULL,
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT vacancy_benefit_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT vacancy_benefit_order_nonnegative CHECK (display_order >= 0),
    CONSTRAINT vacancy_benefit_unique UNIQUE (vacancy_id, name)
);

ALTER TABLE talentflow.scoring_criteria
    ADD COLUMN is_required boolean NOT NULL DEFAULT false,
    ADD COLUMN aliases text[] NOT NULL DEFAULT '{}',
    ADD CONSTRAINT scoring_aliases_no_blank CHECK (array_position(aliases, '') IS NULL);

ALTER TABLE talentflow.scoring_criteria DROP CONSTRAINT scoring_criteria_type_valid;
ALTER TABLE talentflow.scoring_criteria ADD CONSTRAINT scoring_criteria_type_valid
    CHECK (criterion_type IN ('TECNOLOGIA', 'CONOCIMIENTO', 'EXPERIENCIA', 'EDUCACION', 'IDIOMA', 'COMPETENCIA_TECNICA', 'OTRO')) NOT VALID;

ALTER TABLE talentflow.desirable_requirements
    ADD COLUMN relevance varchar(10) NOT NULL DEFAULT 'MEDIUM',
    ADD CONSTRAINT desirable_relevance_valid CHECK (relevance IN ('LOW', 'MEDIUM', 'HIGH'));

ALTER TABLE talentflow.added_value_requirements
    ADD COLUMN requirement_type varchar(30) NOT NULL DEFAULT 'OTHER',
    ADD COLUMN relevance varchar(10) NOT NULL DEFAULT 'MEDIUM',
    ADD CONSTRAINT added_value_type_valid CHECK (requirement_type IN ('COURSE', 'CERTIFICATION', 'PROJECT_MANAGEMENT', 'SCRUM', 'AI_USAGE', 'ADDITIONAL_LANGUAGE', 'OTHER')),
    ADD CONSTRAINT added_value_relevance_valid CHECK (relevance IN ('LOW', 'MEDIUM', 'HIGH'));

ALTER TABLE talentflow.vacancies DROP CONSTRAINT vacancies_status_valid;
ALTER TABLE talentflow.vacancies ADD CONSTRAINT vacancies_status_valid
    CHECK (status IN ('DRAFT', 'OPEN', 'PAUSED', 'CLOSED', 'COMPLETED'));

CREATE INDEX vacancies_responsible_idx ON talentflow.vacancies (responsible_hr_user_id, status);
CREATE INDEX scoring_config_vacancy_created_idx ON talentflow.scoring_config_versions (vacancy_id, version DESC);

CREATE TRIGGER vacancy_benefits_audit
AFTER INSERT OR UPDATE OR DELETE ON talentflow.vacancy_benefits
FOR EACH ROW EXECUTE FUNCTION talentflow.capture_audit_event();

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('005', 'Administrative vacancy fields and scoring metadata');

COMMIT;
