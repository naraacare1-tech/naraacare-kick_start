CREATE TABLE privacy.deletion_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_hash common.sha256_hex NOT NULL,
    requested_at timestamptz NOT NULL,
    completed_at timestamptz NOT NULL DEFAULT now(),
    rows_archived integer NOT NULL DEFAULT 0 CHECK (rows_archived >= 0)
);
COMMENT ON TABLE privacy.deletion_log IS
'Proof that an account was erased (no personal data: hashed user id and times only)';
