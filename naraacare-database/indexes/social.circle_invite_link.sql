-- Indexes for social.circle_invite_link. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_circle_invite_link__circle ON social.circle_invite_link (circle_id, created_at DESC);
COMMENT ON INDEX social.ix_circle_invite_link__circle IS 'serves: FK; links per circle; daily creation limit';

CREATE INDEX ix_circle_invite_link__created_by ON social.circle_invite_link (created_by);
COMMENT ON INDEX social.ix_circle_invite_link__created_by IS 'serves: FK; SET NULL on account deletion';
