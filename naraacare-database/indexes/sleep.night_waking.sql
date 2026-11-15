-- Indexes for sleep.night_waking. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_night_waking__entry_id ON sleep.night_waking (entry_id);
COMMENT ON INDEX sleep.ix_night_waking__entry_id IS 'serves: FK; wakings of an entry';

CREATE INDEX ix_night_waking__user_id ON sleep.night_waking (user_id);
COMMENT ON INDEX sleep.ix_night_waking__user_id IS 'serves: FK; account deletion';
