# Make a user STAR (for testing)

Use this to test STAR features without a store purchase. It gives the user a **support grant** in `billing.entitlement_grant`, the table meant for server-side STAR grants (referrals, promos, support). It does not fake a store subscription.

The API reads the tier from the database on every request (no cache), so the change applies on the user's next request. The app may need a pull-to-refresh or reopen to show it.

## Connect to the database

Run as the `postgres` superuser (its password is `POSTGRES_PASSWORD` in `naraacare-database/.env`). From Git Bash:

```bash
"/c/Program Files/PostgreSQL/18/bin/psql.exe" -h localhost -U postgres -d naraacare
```

Or open the `naraacare` database in pgAdmin's Query Tool and run the queries below there.

## Grant STAR

Replace the email, and the length (`1 year`) if you want.

```sql
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
SELECT id, 'star', 'support', now(), now() + interval '1 year'
FROM auth.user_account
WHERE email = lower('user@example.com') AND deleted_at IS NULL
RETURNING user_id, tier_code, ends_at;
```

If it returns **0 rows**, no user has that email. Check it with `SELECT email, status FROM auth.user_account;`.

## Check a user's tier

`billing.fn_current_entitlement` only answers for the "current user", so set that first, in the same transaction:

```sql
BEGIN;
SELECT set_config('app.user_id', id::text, true) FROM auth.user_account WHERE email = lower('user@example.com');
SELECT tier_code, source, expires_at
FROM billing.fn_current_entitlement((SELECT id FROM auth.user_account WHERE email = lower('user@example.com')));
COMMIT;
```

`star` / `support` means the grant works. `standard` means the user has no active STAR.

## Back to STANDARD

```sql
UPDATE billing.entitlement_grant
SET deleted_at = now(), updated_at = now()
WHERE source = 'support' AND deleted_at IS NULL
  AND user_id = (SELECT id FROM auth.user_account WHERE email = lower('user@example.com'));
```

This only removes support grants. Referral rewards and real store subscriptions stay as they are.

Never use this to give STAR to real customers in production without a record of why. Production grants should go through a proper support process.
