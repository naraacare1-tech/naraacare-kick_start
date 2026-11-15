-- Internal: rebuild one day's nutrition.daily_summary from the non-deleted meals of that local date
-- (DOC "Table B"), and re-assign the hydration food credits to the first 3 meals of the day by
-- logged_at (doc 06 section 2.11, OQ-18). Targets come from the snapshot in force that day.
-- Callers hold the day's summary row lock (SELECT ... FOR UPDATE), so totals cannot interleave.
-- Not granted to any login role: called from the definer procedures (run as api_definer, RLS on).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE nutrition.pr_refresh_daily_summary(p_user_id uuid, p_date date)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_target integer;
    v_calc text;
BEGIN
    SELECT s.base_target_kcal, s.calc_version INTO v_target, v_calc
    FROM app.health_target_snapshot AS s
    WHERE s.user_id = p_user_id AND s.effective_date <= p_date
    ORDER BY s.effective_date DESC
    LIMIT 1;

    UPDATE nutrition.meal AS m
    SET hydration_credit = r.rn <= 3
    FROM (
        SELECT x.id, x.logged_at, row_number() OVER (ORDER BY x.logged_at, x.id) AS rn
        FROM nutrition.meal AS x
        WHERE x.user_id = p_user_id AND x.local_date = p_date AND x.deleted_at IS NULL
    ) AS r
    WHERE m.id = r.id AND m.logged_at = r.logged_at AND m.hydration_credit IS DISTINCT FROM (r.rn <= 3);

    UPDATE nutrition.daily_summary AS d
    SET calories_kcal_total = t.k, protein_g_total = t.pr, carbohydrates_g_total = t.cb,
        fat_g_total = t.ft, dietary_fiber_g_total = t.fb, total_sugar_g_total = t.sg,
        saturated_fat_g_total = t.sf, polyunsaturated_fat_g_total = t.pf,
        monounsaturated_fat_g_total = t.mf, trans_fat_g_total = t.tf, cholesterol_mg_total = t.ch,
        sodium_mg_total = t.na, potassium_mg_total = t.po, calcium_mg_total = t.ca,
        iron_mg_total = t.fe, vitamin_a_mcg_total = t.va, vitamin_c_mg_total = t.vc,
        meal_count = t.meals,
        base_target_kcal = v_target,
        effective_allowance_kcal = CASE WHEN v_target IS NULL THEN NULL ELSE v_target + d.exercise_kcal END,
        calc_version = v_calc,
        updated_at = now()
    FROM (
        SELECT
            coalesce(sum(i.calories_kcal), 0) AS k, coalesce(sum(i.protein_g), 0) AS pr,
            coalesce(sum(i.carbohydrates_g), 0) AS cb, coalesce(sum(i.fat_g), 0) AS ft,
            coalesce(sum(i.dietary_fiber_g), 0) AS fb, coalesce(sum(i.total_sugar_g), 0) AS sg,
            coalesce(sum(i.saturated_fat_g), 0) AS sf, coalesce(sum(i.polyunsaturated_fat_g), 0) AS pf,
            coalesce(sum(i.monounsaturated_fat_g), 0) AS mf, coalesce(sum(i.trans_fat_g), 0) AS tf,
            coalesce(sum(i.cholesterol_mg), 0) AS ch, coalesce(sum(i.sodium_mg), 0) AS na,
            coalesce(sum(i.potassium_mg), 0) AS po, coalesce(sum(i.calcium_mg), 0) AS ca,
            coalesce(sum(i.iron_mg), 0) AS fe, coalesce(sum(i.vitamin_a_mcg), 0) AS va,
            coalesce(sum(i.vitamin_c_mg), 0) AS vc,
            (
                SELECT count(*) FROM nutrition.meal AS m2
                WHERE m2.user_id = p_user_id AND m2.local_date = p_date AND m2.deleted_at IS NULL
            )::smallint AS meals
        FROM nutrition.meal AS m
        INNER JOIN nutrition.meal_item AS i
            ON i.meal_id = m.id AND i.meal_logged_at = m.logged_at AND i.deleted_at IS NULL
        WHERE m.user_id = p_user_id AND m.local_date = p_date AND m.deleted_at IS NULL
    ) AS t
    WHERE d.user_id = p_user_id AND d.local_date = p_date;
END
$$;

COMMENT ON PROCEDURE nutrition.pr_refresh_daily_summary (uuid, date) IS
'Internal: rebuild a day''s nutrition totals and hydration credits from its non-deleted meals';
REVOKE ALL ON PROCEDURE nutrition.pr_refresh_daily_summary(uuid, date) FROM public;
