-- Layer 3 text check for function parameters (doc 07 section 4.5). Casts to common.safe_text and
-- checks the length; both failures raise 22023 (invalid_parameter_value). The rejected value is
-- never echoed in the message, so it cannot leak into logs.
CREATE OR REPLACE FUNCTION common.fn_validate_text(p_value text, p_max_length integer)
RETURNS common.safe_text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_safe common.safe_text;
BEGIN
    IF p_value IS NULL THEN
        RETURN NULL;
    END IF;
    IF p_max_length IS NULL OR p_max_length < 1 THEN
        RAISE EXCEPTION 'p_max_length must be positive' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;
    IF char_length(p_value) > p_max_length THEN
        RAISE EXCEPTION 'text longer than % characters', p_max_length
            USING ERRCODE = '22023', DETAIL = 'TOO_LONG';
    END IF;
    BEGIN
        v_safe := p_value::common.safe_text;
    EXCEPTION WHEN check_violation THEN
        RAISE EXCEPTION 'text contains markup, scripting or unsafe characters'
            USING ERRCODE = '22023', DETAIL = 'UNSAFE_TEXT';
    END;
    RETURN v_safe;
END
$$;

COMMENT ON FUNCTION common.fn_validate_text(text, integer) IS
'Casts to common.safe_text and checks length; raises 22023 (UNSAFE_TEXT / TOO_LONG) without echoing the value';
REVOKE ALL ON FUNCTION common.fn_validate_text(text, integer) FROM public;
GRANT EXECUTE ON FUNCTION common.fn_validate_text(text, integer) TO api_definer;
