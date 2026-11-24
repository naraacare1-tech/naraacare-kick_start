-- V030 (hand-written, 2026-11-24): the NaraaCare MVP document (2026-11 version, "Hydration Logic"
-- step 3) has four water activity levels, one per onboarding answer: Sedentary 1.55, Lightly Active
-- 1.70, Moderately Active 1.85, Very Active 2.00 plus the 699.7 mL athlete term. The table allowed
-- only sedentary / active / athlete; this adds 'light'. The values themselves are seed data
-- (seed/R__11_seed_ref_profile.sql). Owner decision 2026-11-24: use the new MVP values.
ALTER TABLE ref.hydration_activity DROP CONSTRAINT hydration_activity_code_check;
ALTER TABLE ref.hydration_activity
    ADD CONSTRAINT hydration_activity_code_check CHECK (code IN ('sedentary', 'light', 'active', 'athlete'));
