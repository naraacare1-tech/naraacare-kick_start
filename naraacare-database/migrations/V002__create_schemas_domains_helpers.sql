-- V002__create_schemas_domains_helpers: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> schemas/010_schemas.sql
-- Schemas (doc 05 §2). social, ai, support and report are created in later sessions.
CREATE SCHEMA IF NOT EXISTS common;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS activity;
CREATE SCHEMA IF NOT EXISTS nutrition;
CREATE SCHEMA IF NOT EXISTS hydration;
CREATE SCHEMA IF NOT EXISTS sleep;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS notify;
CREATE SCHEMA IF NOT EXISTS privacy;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS ops;

COMMENT ON SCHEMA common IS 'Domains and shared helper functions';
COMMENT ON SCHEMA auth IS 'Accounts, identities, OTP, refresh tokens, login attempts';
COMMENT ON SCHEMA app IS 'User profile, health target snapshots, activity days, streaks';
COMMENT ON SCHEMA ref IS 'Versioned reference data and calculation constants';
COMMENT ON SCHEMA activity IS 'Workouts';
COMMENT ON SCHEMA nutrition IS 'Food database, meals, daily nutrition summaries';
COMMENT ON SCHEMA hydration IS 'Drink intakes, custom drinks, temperature, daily hydration summaries';
COMMENT ON SCHEMA sleep IS 'Sleep entries and daily sleep summaries (STAR)';
COMMENT ON SCHEMA billing IS 'Store subscriptions, transactions, entitlements, referrals';
COMMENT ON SCHEMA notify IS 'Devices, notification preferences, reminders, notifications';
COMMENT ON SCHEMA privacy IS 'Consent records, export and deletion requests, retention policy';
COMMENT ON SCHEMA audit IS 'Change log and security events';
COMMENT ON SCHEMA ops IS 'Partition configuration and maintenance';

-- Nothing lives in public; nobody may create objects there.
REVOKE ALL ON SCHEMA public FROM public;

-- >>> schemas/020_domains.sql
-- Domains (doc 05 section 4, doc 07 section 4.5): layer 3 of input validation.
-- Rule enforced by tests/060: no column may use bare text/varchar; every text column uses one of these.
-- Regexes use PostgreSQL escapes only (e.g. \u200B), never literal invisible characters.

-- Free text: rejects markup, event handlers, script/data URIs, template syntax, encodings,
-- control/zero-width/bidi characters and look-alike angle brackets. Length is checked per column.
CREATE DOMAIN common.safe_text AS text
CONSTRAINT safe_text_no_control_chars CHECK (
    value !~ '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'
)
CONSTRAINT safe_text_no_markup CHECK (
    value !~ '[<>\uFF1C\uFF1E\uFE64\uFE65\u2039\u203A]'
)
CONSTRAINT safe_text_no_script CHECK (
    value !~* '(java|vb|live)\s*script\s*:'
    AND value !~* 'data\s*:\s*[a-z]+/[a-z0-9.+-]+'
    AND value !~* '(^|[^a-z0-9_])on[a-z]+\s*='
    AND value !~* '(expression|url)\s*\(|@import'
)
CONSTRAINT safe_text_no_templates CHECK (
    value !~ '(\{\{|\}\}|\$\{|<%|%>|#\{)'
)
CONSTRAINT safe_text_no_encoding CHECK (
    value !~* '&(#x?[0-9a-f]+;?|[a-z]+;)'
    AND value !~* '%[0-9a-f]{2}'
    AND value !~* '\\(u[0-9a-f]{4}|x[0-9a-f]{2})'
);
COMMENT ON DOMAIN common.safe_text IS 'User/staff free text with no markup or scripting (doc 07 section 4.2)';

-- Machine codes and enum-like values (lower snake case, dots allowed for namespaced keys).
CREATE DOMAIN common.code AS text
CONSTRAINT code_format CHECK (value ~ '^[a-z][a-z0-9_.]{0,62}$');

CREATE DOMAIN common.username AS text
CONSTRAINT username_format CHECK (
    value ~ '^[a-z0-9][a-z0-9._]{1,28}[a-z0-9]$' AND value !~ '[._]{2}'
);

CREATE DOMAIN common.argon2_hash AS text
CONSTRAINT argon2id_format CHECK (
    char_length(value) <= 256
    AND value ~ '^\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$'
);

-- SHA-256 digest of a secret that is never stored itself (refresh tokens only).
CREATE DOMAIN common.blind_index AS bytea
CONSTRAINT blind_index_length CHECK (octet_length(value) = 32);

-- Data is stored as plain text so it can be read while debugging (owner decision, 2026-11-03);
-- only passwords (Argon2id) and refresh tokens (SHA-256) are hashed.
-- Email, lower-cased and validated by the API.
CREATE DOMAIN common.email AS text
CONSTRAINT email_format CHECK (
    char_length(value) BETWEEN 3 AND 254
    AND value = lower(value)
    AND value ~ '^[^[:space:]@<>]+@[^[:space:]@<>]+$'
);

CREATE DOMAIN common.otp_code AS text
CONSTRAINT otp_code_format CHECK (value ~ '^[0-9]{6}$');

-- Tokens issued by Google, Apple or FCM (push tokens, purchase tokens, provider refresh tokens).
CREATE DOMAIN common.opaque_token AS text
CONSTRAINT opaque_token_format CHECK (
    char_length(value) BETWEEN 1 AND 4096 AND value ~ '^[A-Za-z0-9._~+/=:-]+$'
);

CREATE DOMAIN common.iana_timezone AS text
CONSTRAINT iana_timezone_format CHECK (
    char_length(value) <= 64 AND value ~ '^(UTC|[A-Za-z_]+(/[A-Za-z0-9_+-]+){1,2})$'
);

CREATE DOMAIN common.locale AS text
CONSTRAINT locale_format CHECK (value ~ '^[a-z]{2}(-[A-Z]{2})?$');

CREATE DOMAIN common.app_version AS text
CONSTRAINT app_version_format CHECK (value ~ '^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(\+[0-9]{1,9})?$');

CREATE DOMAIN common.version_label AS text
CONSTRAINT version_label_format CHECK (value ~ '^[0-9A-Za-z][0-9A-Za-z._-]{0,19}$');

-- Opaque external identifiers (store product/transaction ids, notification ids, row keys).
CREATE DOMAIN common.opaque_ref AS text
CONSTRAINT opaque_ref_format CHECK (value ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$');

CREATE DOMAIN common.https_url AS text
CONSTRAINT https_url_format CHECK (
    char_length(value) <= 300 AND value ~ '^https://[a-z0-9.-]+(/[A-Za-z0-9._~/-]*)?$'
);

CREATE DOMAIN common.deep_link AS text
CONSTRAINT deep_link_format CHECK (value ~ '^naraacare://[a-z0-9/_-]{1,200}$');

CREATE DOMAIN common.object_key AS text
CONSTRAINT object_key_format CHECK (
    value ~ '^[a-z]+/[0-9a-f-]{36}(/[a-z0-9_-]{1,40})?\.(png|jpg|pdf|zip)$'
);

CREATE DOMAIN common.asset_key AS text
CONSTRAINT asset_key_format CHECK (value ~ '^[a-z0-9_/-]{1,80}$');

CREATE DOMAIN common.barcode AS text
CONSTRAINT barcode_format CHECK (value ~ '^[0-9]{8,14}$');

CREATE DOMAIN common.referral_code AS text
CONSTRAINT referral_code_format CHECK (value ~ '^[A-Z0-9]{6,12}$');

CREATE DOMAIN common.currency AS text
CONSTRAINT currency_format CHECK (value ~ '^[A-Z]{3}$');

CREATE DOMAIN common.sha256_hex AS text
CONSTRAINT sha256_hex_format CHECK (value ~ '^[0-9a-f]{64}$');

-- >>> schemas/030_common_functions.sql
-- Current application user for RLS policies. NULL when not set (or reset to '' after a
-- transaction-local set_config), so policies match no rows instead of erroring.
CREATE OR REPLACE FUNCTION common.current_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$ SELECT nullif(current_setting('app.user_id', true), '')::uuid $$;

COMMENT ON FUNCTION common.current_user_id() IS
'app.user_id set per transaction by the API via set_config(..., true); used by RLS policies';
