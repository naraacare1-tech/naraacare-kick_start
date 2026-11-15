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
