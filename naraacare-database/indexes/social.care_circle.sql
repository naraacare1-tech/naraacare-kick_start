-- Indexes for social.care_circle. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_care_circle__created_by_user ON social.care_circle (created_by_user);
COMMENT ON INDEX social.ix_care_circle__created_by_user IS 'serves: FK; cascade on account deletion';

CREATE INDEX ix_care_circle__wallpaper_code ON social.care_circle (wallpaper_code);
COMMENT ON INDEX social.ix_care_circle__wallpaper_code IS 'serves: FK to ref.wallpaper';
