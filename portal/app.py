import os
from typing import Any

from authlib.integrations.starlette_client import OAuth
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from itsdangerous import URLSafeSerializer
from starlette.middleware.sessions import SessionMiddleware


PORTAL_SECRET_KEY = os.environ.get("PORTAL_SECRET_KEY", "changeme-openinsight-portal-secret")
PORTAL_KEYCLOAK_CLIENT_ID = os.environ.get("PORTAL_KEYCLOAK_CLIENT_ID", "openinsight-portal")
PORTAL_KEYCLOAK_CLIENT_SECRET = os.environ.get("PORTAL_KEYCLOAK_CLIENT_SECRET", "portal-dev-secret")
KEYCLOAK_INTERNAL_URL = os.environ.get("KEYCLOAK_INTERNAL_URL", "http://keycloak:8080")
KEYCLOAK_EXTERNAL_URL = os.environ.get("KEYCLOAK_EXTERNAL_URL", "http://localhost:8080")
KEYCLOAK_REALM = os.environ.get("KEYCLOAK_REALM", "openinsight")
PORTAL_URL = os.environ.get("PORTAL_URL", "http://localhost:8091")
SUPERSET_URL = os.environ.get("SUPERSET_URL", "http://localhost:8088")
TARGET_COOKIE_SECRET = os.environ.get("OI_TARGET_COOKIE_SECRET", "changeme-openinsight-target-cookie")
TARGET_COOKIE_NAME = "oi_target"
PORTAL_SESSION_COOKIE = "portal_session"

TARGETS = {
    "openinsight": {
        "label": "OpenInsight",
        "required_role": "target-openinsight",
    },
    "engineering-data": {
        "label": "Engineering Data",
        "required_role": "target-engineering-data",
    },
}

app = FastAPI(title="OpenInsight Portal")
app.add_middleware(
    SessionMiddleware,
    secret_key=PORTAL_SECRET_KEY,
    session_cookie=PORTAL_SESSION_COOKIE,
    same_site="lax",
    https_only=False,
)
templates = Jinja2Templates(directory="/app/templates")
target_serializer = URLSafeSerializer(TARGET_COOKIE_SECRET, salt="openinsight-target")

oauth = OAuth()
oauth.register(
    name="keycloak",
    client_id=PORTAL_KEYCLOAK_CLIENT_ID,
    client_secret=PORTAL_KEYCLOAK_CLIENT_SECRET,
    server_metadata_url=(
        f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}"
        "/.well-known/openid-configuration"
    ),
    authorize_url=f"{KEYCLOAK_EXTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/auth",
    access_token_url=f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token",
    jwks_uri=f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/certs",
    userinfo_endpoint=f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/userinfo",
    client_kwargs={
        "scope": "openid profile email",
        "token_endpoint_auth_method": "client_secret_post",
        "claims_options": {
            "iss": {
                "values": [
                    f"{KEYCLOAK_EXTERNAL_URL}/realms/{KEYCLOAK_REALM}",
                    f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}",
                ]
            }
        },
    },
)


def _user_from_session(request: Request) -> dict[str, Any] | None:
    return request.session.get("user")


def _allowed_targets(user: dict[str, Any]) -> list[dict[str, str]]:
    roles = set(user.get("roles", []))
    allowed: list[dict[str, str]] = []
    for target_id, spec in TARGETS.items():
        if spec["required_role"] in roles:
            allowed.append({"id": target_id, "label": spec["label"]})
    return allowed


def _clear_superset_cookies(response, clear_target: bool = True):
    response.delete_cookie("session", path="/")
    if clear_target:
        response.delete_cookie(TARGET_COOKIE_NAME, path="/")
    return response


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/login")
async def login(request: Request):
    redirect_uri = request.url_for("auth_callback")
    return await oauth.keycloak.authorize_redirect(request, str(redirect_uri))


@app.get("/auth/callback")
async def auth_callback(request: Request):
    token = await oauth.keycloak.authorize_access_token(request)
    userinfo = await oauth.keycloak.userinfo(token=token)

    request.session["user"] = {
        "username": userinfo.get("preferred_username", ""),
        "email": userinfo.get("email", ""),
        "name": userinfo.get("name") or userinfo.get("preferred_username", ""),
        "roles": userinfo.get("roles", []),
        "groups": userinfo.get("groups", []),
    }
    return RedirectResponse(url="/", status_code=302)


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    user = _user_from_session(request)
    if not user:
        return RedirectResponse(url="/login", status_code=302)

    if "portal-pilot" not in set(user.get("roles", [])):
        response = templates.TemplateResponse(
            "forbidden.html",
            {"request": request, "user": user},
            status_code=403,
        )
        return _clear_superset_cookies(response)

    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "user": user,
            "targets": _allowed_targets(user),
        },
    )


@app.post("/launch/{target_id}")
async def launch_target(request: Request, target_id: str):
    user = _user_from_session(request)
    if not user:
        return RedirectResponse(url="/login", status_code=302)

    if "portal-pilot" not in set(user.get("roles", [])):
        raise HTTPException(status_code=403, detail="Portal access denied")

    spec = TARGETS.get(target_id)
    if not spec or spec["required_role"] not in set(user.get("roles", [])):
        raise HTTPException(status_code=403, detail="Target access denied")

    response = RedirectResponse(url=f"{SUPERSET_URL}/login/keycloak", status_code=302)
    response.set_cookie(
        TARGET_COOKIE_NAME,
        target_serializer.dumps(target_id),
        httponly=True,
        samesite="lax",
        path="/",
    )
    return _clear_superset_cookies(response, clear_target=False)


@app.get("/logout")
async def logout(request: Request):
    request.session.clear()
    response = RedirectResponse(url="/", status_code=302)
    response.delete_cookie(PORTAL_SESSION_COOKIE, path="/")
    return _clear_superset_cookies(response)
