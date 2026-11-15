-- V017__grant_create_nutrition_to_api_definer: Session 08 creates the nutrition API routines as
-- api_definer (SET LOCAL ROLE api_definer in each R__ script, doc 05 section 7), which needs CREATE
-- on the schema. api_definer cannot log in and runs only our function bodies (no dynamic SQL).
GRANT CREATE ON SCHEMA nutrition TO api_definer;

-- Food search and voice matching call pg_trgm (similarity, %), installed in schema public. USAGE
-- only resolves those extension objects; nobody can create anything in public (bootstrap).
GRANT USAGE ON SCHEMA public TO api_definer;
