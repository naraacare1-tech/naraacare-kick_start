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
-- ASCII addresses only, as the API accepts them (email-validator, no SMTPUTF8): RFC 5322 atoms
-- before the @, a hostname after it (S16: the old "no space, @ or angle bracket" rule let entity- and
-- full-width-encoded markup through).
CREATE DOMAIN common.email AS text
CONSTRAINT email_format CHECK (
    char_length(value) BETWEEN 3 AND 254
    AND value = lower(value)
    AND value ~ '^[a-z0-9!#$%&''*+/=?^_`{|}~-]+(\.[a-z0-9!#$%&''*+/=?^_`{|}~-]+)*@[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'
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
