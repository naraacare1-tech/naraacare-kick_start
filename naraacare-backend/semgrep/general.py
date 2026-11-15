# Semgrep test fixture for general.yml (run: semgrep --test semgrep/). Not application code.
from sqlalchemy import text


async def bad(conn, logger, request, user_id, name):
    # ruleid: no-sql-string-building
    await conn.execute(f"SELECT * FROM app.fn_get_profile('{user_id}')")
    # ruleid: no-sql-string-building
    await conn.execute("SELECT * FROM app.fn_x('%s')" % name)
    # ruleid: no-sql-string-building
    await conn.execute(text("SELECT * FROM app.fn_x('" + name + "')"))
    # ruleid: no-sql-string-building
    await conn.execute(text(f"SELECT * FROM app.fn_x('{name}')"))
    # ruleid: no-print
    print(user_id)
    # ruleid: no-logging-request-body
    logger.info("signup", body=await request.body())
    # ruleid: no-logging-request-body
    logger.warning("rejected", payload=name)


async def good(conn, logger, user_id, service, request):
    # ok: no-sql-string-building
    await conn.execute(text("SELECT * FROM app.fn_get_profile(:uid)"), {"uid": user_id})
    # ok: no-logging-request-body
    logger.info("profile_loaded", user_id=str(user_id))
    # ok: no-logging-request-body
    await service.send(user_id=user_id, body="hello")
    # ok: no-logging-request-body
    await service.webhook(request.headers, await request.body())


def dangerous(data, token, key, client, cmd):
    # ruleid: no-eval-exec
    eval(data)
    # ruleid: no-eval-exec
    exec(data)
    # ruleid: no-unsafe-deserialisation
    pickle.loads(data)
    # ruleid: no-unsafe-deserialisation
    yaml.load(data)
    # ok: no-unsafe-deserialisation
    yaml.safe_load(data)
    # ruleid: no-shell
    os.system(cmd)
    # ruleid: no-shell
    subprocess.run(cmd, shell=True)
    # ok: no-shell
    subprocess.run(["ls", "-l"])
    # ruleid: no-tls-verification-off
    client.get("https://x", verify=False)
    # ruleid: no-jwt-without-verification
    jwt.decode(token, key)
    # ruleid: no-jwt-without-verification
    jwt.decode(token, key, algorithms=["EdDSA"], options={"verify_signature": False})
    # ok: no-jwt-without-verification
    jwt.decode(token, key, algorithms=["EdDSA"], audience="naraacare-mobile")
    # ruleid: no-insecure-random
    random.randint(0, 999999)
    # ok: no-insecure-random
    secrets.randbelow(1_000_000)
    # ruleid: no-html-responses
    return HTMLResponse("<p>hi</p>")


# ruleid: no-param-default-validation-bypass
async def search_bad(q: SafeSearchQuery = Query()):
    return q


# ok: no-param-default-validation-bypass
async def search_good(q: Annotated[SafeSearchQuery, Query()]):
    return q
