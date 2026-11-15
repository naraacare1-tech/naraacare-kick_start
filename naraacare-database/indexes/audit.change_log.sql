-- Indexes for audit.change_log. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX brin_change_log__occurred_at ON audit.change_log USING brin (occurred_at);
COMMENT ON INDEX audit.brin_change_log__occurred_at IS 'serves: append-only time-range scans';

CREATE INDEX ix_change_log__table_row ON audit.change_log (table_name, row_pk);
COMMENT ON INDEX audit.ix_change_log__table_row IS 'serves: history of one row';
