CREATE TABLE notify.notification_preference (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    goal_completions boolean NOT NULL DEFAULT TRUE,
    streak_milestones boolean NOT NULL DEFAULT TRUE,
    health_insights boolean NOT NULL DEFAULT TRUE,
    hydration_reminders boolean NOT NULL DEFAULT TRUE,
    nutrition_reminders boolean NOT NULL DEFAULT TRUE,
    sleep_reminders boolean NOT NULL DEFAULT TRUE,
    daily_checkin boolean NOT NULL DEFAULT FALSE,
    health_profile_reminders boolean NOT NULL DEFAULT TRUE,
    connection_requests boolean NOT NULL DEFAULT TRUE,
    connection_activity boolean NOT NULL DEFAULT TRUE,
    reports_ready boolean NOT NULL DEFAULT TRUE,
    subscription_payments boolean NOT NULL DEFAULT TRUE,
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE notify.notification_preference IS 'Personal notification toggles (Figma Notification Settings)';
