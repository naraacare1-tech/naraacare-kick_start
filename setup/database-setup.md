# Database setup: folders to run

Run these folders from `naraacare-database/` against your PostgreSQL database, **in this order**:

| # | Folder | Notes |
|---|---|---|
| 1 | `bootstrap/` | Run once as the `postgres` superuser. Creates the `migration_owner` role. |
| 2 | `migrations/` | `V001` → `V018`, in number order. |
| 3 | `seed/` | Reference data. |
| 4 | `functions/` | All `R__*.sql` files, in file-name order. |
| 5 | `procedures/` | All `R__*.sql` files, in file-name order. |
| 6 | `triggers/` | All `R__*.sql` files. |

Skip all other folders (`schemas/`, `roles/`, `tables/`, `indexes/`, `views/`, `tests/`, `tools/`). They hold reference copies, tests or helper scripts and are not part of the setup.

## Recommended: let the script do it

```bash
cd naraacare-database
cp .env.example .env
bash tools/local_setup.sh
```

This script runs all six folders in the correct order through Flyway. It also fills in the `${...}` placeholders (role passwords and `seed_sample_foods`) used by `migrations/V003` and `seed/`. If you run the files by hand with `psql`, you must replace those placeholders yourself.
