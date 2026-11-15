-- Indexes for social.circle_member. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_circle_member__user_status ON social.circle_member (user_id, status);
COMMENT ON INDEX social.ix_circle_member__user_status IS 'serves: Your Circles + pending invites; FK';

CREATE INDEX ix_circle_member__circle_status_joined ON social.circle_member (circle_id, status, joined_at);
COMMENT ON INDEX social.ix_circle_member__circle_status_joined IS
'serves: member list, seat count, admin succession (earliest joined)';

CREATE INDEX ix_circle_member__invited_by ON social.circle_member (invited_by);
COMMENT ON INDEX social.ix_circle_member__invited_by IS 'serves: FK; SET NULL on account deletion';
