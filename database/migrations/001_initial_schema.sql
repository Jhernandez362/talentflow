BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS talentflow;

CREATE TABLE talentflow.schema_migrations (
    version varchar(50) PRIMARY KEY,
    description text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE talentflow.hr_users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email citext NOT NULL UNIQUE,
    display_name varchar(150) NOT NULL,
    role varchar(30) NOT NULL DEFAULT 'RECRUITER',
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT hr_users_email_not_blank CHECK (btrim(email::text) <> ''),
    CONSTRAINT hr_users_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT hr_users_role_valid CHECK (role IN ('ADMIN', 'RECRUITER', 'REVIEWER'))
);

CREATE TABLE talentflow.vacancies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(50) NOT NULL UNIQUE,
    title varchar(180) NOT NULL,
    description text,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    created_by uuid NOT NULL REFERENCES talentflow.hr_users(id) ON DELETE RESTRICT,
    updated_by uuid REFERENCES talentflow.hr_users(id) ON DELETE SET NULL,
    published_at timestamptz,
    closed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT vacancies_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT vacancies_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT vacancies_status_valid CHECK (status IN ('DRAFT', 'PUBLISHED', 'PAUSED', 'CLOSED', 'CANCELLED')),
    CONSTRAINT vacancies_priority_valid CHECK (priority IN ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
    CONSTRAINT vacancies_published_at_valid CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL),
    CONSTRAINT vacancies_closed_at_valid CHECK (status <> 'CLOSED' OR closed_at IS NOT NULL)
);

CREATE TABLE talentflow.scoring_config_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vacancy_id uuid NOT NULL REFERENCES talentflow.vacancies(id) ON DELETE CASCADE,
    version integer NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    notes text,
    created_by uuid NOT NULL REFERENCES talentflow.hr_users(id) ON DELETE RESTRICT,
    published_by uuid REFERENCES talentflow.hr_users(id) ON DELETE RESTRICT,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT scoring_config_version_positive CHECK (version > 0),
    CONSTRAINT scoring_config_status_valid CHECK (status IN ('DRAFT', 'PUBLISHED', 'ARCHIVED')),
    CONSTRAINT scoring_config_publication_metadata CHECK (
        (status = 'DRAFT' AND published_at IS NULL AND published_by IS NULL)
        OR (status IN ('PUBLISHED', 'ARCHIVED') AND published_at IS NOT NULL AND published_by IS NOT NULL)
    ),
    CONSTRAINT scoring_config_vacancy_version_unique UNIQUE (vacancy_id, version),
    CONSTRAINT scoring_config_id_vacancy_unique UNIQUE (id, vacancy_id)
);

CREATE UNIQUE INDEX scoring_config_one_published_per_vacancy_idx
    ON talentflow.scoring_config_versions (vacancy_id)
    WHERE status = 'PUBLISHED';

CREATE TABLE talentflow.scoring_criteria (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scoring_config_version_id uuid NOT NULL REFERENCES talentflow.scoring_config_versions(id) ON DELETE CASCADE,
    code varchar(60) NOT NULL,
    name varchar(160) NOT NULL,
    criterion_type varchar(30) NOT NULL,
    description text,
    weight smallint NOT NULL,
    evaluation_order smallint NOT NULL DEFAULT 0,
    evaluation_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT scoring_criteria_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT scoring_criteria_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT scoring_criteria_type_valid CHECK (criterion_type IN ('SKILL', 'EXPERIENCE', 'EDUCATION', 'CERTIFICATION', 'LANGUAGE', 'OTHER')),
    CONSTRAINT scoring_criteria_weight_range CHECK (weight BETWEEN 0 AND 100),
    CONSTRAINT scoring_criteria_order_nonnegative CHECK (evaluation_order >= 0),
    CONSTRAINT scoring_criteria_rule_object CHECK (jsonb_typeof(evaluation_rule) = 'object'),
    CONSTRAINT scoring_criteria_config_code_unique UNIQUE (scoring_config_version_id, code)
);

CREATE TABLE talentflow.desirable_requirements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scoring_config_version_id uuid NOT NULL REFERENCES talentflow.scoring_config_versions(id) ON DELETE CASCADE,
    name varchar(160) NOT NULL,
    description text,
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT desirable_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT desirable_order_nonnegative CHECK (display_order >= 0),
    CONSTRAINT desirable_config_name_unique UNIQUE (scoring_config_version_id, name)
);

CREATE TABLE talentflow.added_value_requirements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scoring_config_version_id uuid NOT NULL REFERENCES talentflow.scoring_config_versions(id) ON DELETE CASCADE,
    name varchar(160) NOT NULL,
    description text,
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT added_value_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT added_value_order_nonnegative CHECK (display_order >= 0),
    CONSTRAINT added_value_config_name_unique UNIQUE (scoring_config_version_id, name)
);

CREATE TABLE talentflow.candidates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email citext NOT NULL UNIQUE,
    full_name varchar(180) NOT NULL,
    phone varchar(40),
    location varchar(160),
    consent_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT candidates_email_not_blank CHECK (btrim(email::text) <> ''),
    CONSTRAINT candidates_name_not_blank CHECK (btrim(full_name) <> '')
);

CREATE TABLE talentflow.applications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vacancy_id uuid NOT NULL REFERENCES talentflow.vacancies(id) ON DELETE RESTRICT,
    candidate_id uuid NOT NULL REFERENCES talentflow.candidates(id) ON DELETE RESTRICT,
    status varchar(30) NOT NULL DEFAULT 'RECEIVED',
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    source varchar(50) NOT NULL DEFAULT 'WEB',
    revision_manual_autorizada boolean NOT NULL DEFAULT false,
    applied_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT applications_status_valid CHECK (status IN ('RECEIVED', 'PROCESSING', 'READY_FOR_REVIEW', 'IN_REVIEW', 'ON_HOLD', 'ADVANCED', 'REJECTED', 'WITHDRAWN')),
    CONSTRAINT applications_priority_valid CHECK (priority IN ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
    CONSTRAINT applications_source_not_blank CHECK (btrim(source) <> ''),
    CONSTRAINT applications_candidate_vacancy_unique UNIQUE (vacancy_id, candidate_id),
    CONSTRAINT applications_id_vacancy_unique UNIQUE (id, vacancy_id)
);

CREATE TABLE talentflow.cv_references (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id uuid NOT NULL REFERENCES talentflow.candidates(id) ON DELETE RESTRICT,
    application_id uuid REFERENCES talentflow.applications(id) ON DELETE SET NULL,
    drive_file_id varchar(255) NOT NULL UNIQUE,
    drive_web_view_link text,
    original_filename varchar(255) NOT NULL,
    mime_type varchar(100) NOT NULL DEFAULT 'application/pdf',
    size_bytes bigint,
    sha256 char(64),
    is_current boolean NOT NULL DEFAULT true,
    uploaded_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cv_drive_id_not_blank CHECK (btrim(drive_file_id) <> ''),
    CONSTRAINT cv_filename_not_blank CHECK (btrim(original_filename) <> ''),
    CONSTRAINT cv_size_nonnegative CHECK (size_bytes IS NULL OR size_bytes >= 0),
    CONSTRAINT cv_sha256_format CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-fA-F]{64}$')
);

CREATE UNIQUE INDEX cv_one_current_per_application_idx
    ON talentflow.cv_references (application_id)
    WHERE is_current AND application_id IS NOT NULL;

CREATE INDEX cv_references_candidate_idx ON talentflow.cv_references (candidate_id);

CREATE TABLE talentflow.document_processing_attempts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cv_reference_id uuid NOT NULL REFERENCES talentflow.cv_references(id) ON DELETE CASCADE,
    attempt_number integer NOT NULL,
    status varchar(30) NOT NULL DEFAULT 'PENDING',
    processor varchar(80),
    error_code varchar(80),
    error_message text,
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT processing_attempt_positive CHECK (attempt_number > 0),
    CONSTRAINT processing_status_valid CHECK (status IN ('PENDING', 'RUNNING', 'SUCCEEDED', 'FAILED', 'CANCELLED')),
    CONSTRAINT processing_time_order CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at),
    CONSTRAINT processing_document_attempt_unique UNIQUE (cv_reference_id, attempt_number)
);

CREATE TABLE talentflow.ai_analyses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES talentflow.applications(id) ON DELETE CASCADE,
    processing_attempt_id uuid REFERENCES talentflow.document_processing_attempts(id) ON DELETE SET NULL,
    analysis_type varchar(40) NOT NULL,
    status varchar(30) NOT NULL DEFAULT 'PENDING',
    provider varchar(80),
    model varchar(120),
    prompt_code varchar(50),
    prompt_version varchar(30),
    structured_output jsonb,
    error_message text,
    started_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ai_analysis_type_valid CHECK (analysis_type IN ('CV_EXTRACTION', 'PROFESSIONAL_SUMMARY', 'INTERVIEW_QUESTIONS')),
    CONSTRAINT ai_analysis_status_valid CHECK (status IN ('PENDING', 'RUNNING', 'SUCCEEDED', 'FAILED', 'CANCELLED')),
    CONSTRAINT ai_analysis_output_object CHECK (structured_output IS NULL OR jsonb_typeof(structured_output) = 'object'),
    CONSTRAINT ai_analysis_time_order CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE INDEX ai_analyses_application_idx ON talentflow.ai_analyses (application_id, analysis_type, created_at DESC);

CREATE TABLE talentflow.score_evaluations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL,
    vacancy_id uuid NOT NULL,
    scoring_config_version_id uuid NOT NULL,
    total_score numeric(5,2) NOT NULL,
    algorithm_version varchar(50) NOT NULL,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT score_application_vacancy_fk FOREIGN KEY (application_id, vacancy_id)
        REFERENCES talentflow.applications(id, vacancy_id) ON DELETE CASCADE,
    CONSTRAINT score_config_vacancy_fk FOREIGN KEY (scoring_config_version_id, vacancy_id)
        REFERENCES talentflow.scoring_config_versions(id, vacancy_id) ON DELETE RESTRICT,
    CONSTRAINT score_total_range CHECK (total_score BETWEEN 0 AND 100),
    CONSTRAINT score_algorithm_not_blank CHECK (btrim(algorithm_version) <> ''),
    CONSTRAINT score_application_config_unique UNIQUE (application_id, scoring_config_version_id)
);

CREATE INDEX score_evaluations_application_idx ON talentflow.score_evaluations (application_id, calculated_at DESC);

CREATE TABLE talentflow.score_criterion_results (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    score_evaluation_id uuid NOT NULL REFERENCES talentflow.score_evaluations(id) ON DELETE CASCADE,
    scoring_criterion_id uuid NOT NULL REFERENCES talentflow.scoring_criteria(id) ON DELETE RESTRICT,
    matched boolean NOT NULL,
    points_awarded numeric(5,2) NOT NULL,
    evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
    explanation text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT score_result_points_nonnegative CHECK (points_awarded >= 0),
    CONSTRAINT score_result_evidence_array CHECK (jsonb_typeof(evidence) = 'array'),
    CONSTRAINT score_result_criterion_unique UNIQUE (score_evaluation_id, scoring_criterion_id)
);

CREATE TABLE talentflow.suggested_questions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES talentflow.applications(id) ON DELETE CASCADE,
    ai_analysis_id uuid REFERENCES talentflow.ai_analyses(id) ON DELETE SET NULL,
    question text NOT NULL,
    rationale text,
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT suggested_question_not_blank CHECK (btrim(question) <> ''),
    CONSTRAINT suggested_question_order_nonnegative CHECK (display_order >= 0),
    CONSTRAINT suggested_question_position_unique UNIQUE (application_id, display_order)
);

CREATE TABLE talentflow.hr_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES talentflow.applications(id) ON DELETE CASCADE,
    reviewer_id uuid NOT NULL REFERENCES talentflow.hr_users(id) ON DELETE RESTRICT,
    decision varchar(30) NOT NULL,
    notes text,
    reviewed_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT hr_review_decision_valid CHECK (decision IN ('PENDING', 'ADVANCE', 'HOLD', 'REJECT', 'REQUEST_INFORMATION'))
);

CREATE INDEX hr_reviews_application_idx ON talentflow.hr_reviews (application_id, reviewed_at DESC);
CREATE INDEX applications_status_priority_idx ON talentflow.applications (status, priority, applied_at DESC);
CREATE INDEX vacancies_status_priority_idx ON talentflow.vacancies (status, priority, created_at DESC);

CREATE TABLE talentflow.audit_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    actor_hr_user_id uuid REFERENCES talentflow.hr_users(id) ON DELETE SET NULL,
    action varchar(10) NOT NULL,
    schema_name name NOT NULL,
    table_name name NOT NULL,
    record_id uuid,
    old_data jsonb,
    new_data jsonb,
    source varchar(80),
    request_id varchar(120),
    CONSTRAINT audit_action_valid CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    CONSTRAINT audit_has_snapshot CHECK (old_data IS NOT NULL OR new_data IS NOT NULL)
);

CREATE INDEX audit_events_record_idx ON talentflow.audit_events (table_name, record_id, occurred_at DESC);
CREATE INDEX audit_events_actor_idx ON talentflow.audit_events (actor_hr_user_id, occurred_at DESC);
CREATE INDEX audit_events_occurred_at_idx ON talentflow.audit_events (occurred_at DESC);

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('001', 'Initial TalentFlow relational schema');

COMMIT;

