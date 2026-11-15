-- V027 (hand-written, 2026-11-07): the goal picker offers five goals only (owner): Standard Loss,
-- Mild Loss, Maintain, Mild Gain, Standard Gain. Aggressive Loss, Moderate Loss and Aggressive Gain
-- stay in the matrix (doc 06 section 2.4) so a profile that already has one keeps its targets, but
-- they are no longer offered or accepted as a new choice.
ALTER TABLE ref.weight_goal ADD COLUMN offered boolean NOT NULL DEFAULT TRUE;
COMMENT ON COLUMN ref.weight_goal.offered IS 'Shown in the goal picker and accepted as a new choice (V027)';
