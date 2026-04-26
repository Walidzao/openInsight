import os
from typing import Optional
from urllib.parse import quote as _quote

from flask import request
from flask_appbuilder.security.manager import AUTH_OAUTH
from superset.security import SupersetSecurityManager
from itsdangerous import BadSignature, URLSafeSerializer

# =============================================================================
# OpenInsight Superset Configuration
# Auth: Keycloak OIDC (realm: openinsight, client: superset)
# =============================================================================

# --- Core ---
SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'changeme-generate-a-real-secret')
SQLALCHEMY_DATABASE_URI = os.environ.get(
    'SQLALCHEMY_DATABASE_URI',
    'postgresql+psycopg2://openinsight:openinsight_dev@postgres:5432/superset'
)

# --- Keycloak OIDC ---
# Internal URL: container-to-container (token exchange, userinfo)
# External URL: browser redirects (authorize endpoint)
KEYCLOAK_INTERNAL_URL = os.environ.get('KEYCLOAK_INTERNAL_URL', 'http://keycloak:8080')
KEYCLOAK_EXTERNAL_URL = os.environ.get('KEYCLOAK_EXTERNAL_URL', 'http://localhost:8080')
KEYCLOAK_REALM = os.environ.get('KEYCLOAK_REALM', 'openinsight')
TARGET_COOKIE_NAME = "oi_target"
TARGET_COOKIE_SECRET = os.environ.get("OI_TARGET_COOKIE_SECRET", "changeme-openinsight-target-cookie")
PILOT_CLIENT_ROLE = "superset-alpha-pilot"
TARGET_ROLE_MAP = {
    "openinsight": "target-openinsight",
    "engineering-data": "target-engineering-data",
}

AUTH_TYPE = AUTH_OAUTH

OAUTH_PROVIDERS = [
    {
        "name": "keycloak",
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": os.environ.get("SUPERSET_KEYCLOAK_CLIENT_ID", "superset"),
            "client_secret": os.environ.get("SUPERSET_KEYCLOAK_SECRET", "superset-dev-secret"),
            # OIDC auto-discovery (Authlib fetches jwks_uri, token endpoint, etc.)
            "server_metadata_url": (
                f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}"
                "/.well-known/openid-configuration"
            ),
            # Server-side: Superset backend → Keycloak (Docker internal network)
            "api_base_url": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect",
            "access_token_url": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token",
            "jwks_uri": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/certs",
            # Browser-side: user's browser → Keycloak (localhost)
            "authorize_url": f"{KEYCLOAK_EXTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/auth",
            "client_kwargs": {
                "scope": "openid profile email",
                "token_endpoint_auth_method": "client_secret_post",
                # Keycloak issues tokens with iss=<browser URL> (localhost:8080)
                # but Superset's backend fetches discovery from keycloak:8080
                # (internal Docker hostname) — the two differ. Accept both issuers.
                "claims_options": {
                    "iss": {
                        "values": [
                            f"{KEYCLOAK_EXTERNAL_URL}/realms/{KEYCLOAK_REALM}",
                            f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}",
                        ]
                    }
                },
            },
        },
    }
]

# --- User registration & role sync ---
AUTH_USER_REGISTRATION = True
AUTH_USER_REGISTRATION_ROLE = "Public"
AUTH_ROLES_SYNC_AT_LOGIN = True

# Map Keycloak client_roles + group names → Superset roles
# client_roles: defined in realm-openinsight.json under the superset client
# group names: come from the Keycloak "groups" claim (group membership mapper)
AUTH_ROLES_MAPPING = {
    # Functional roles (from Keycloak client roles)
    "superset-admin": ["Admin"],
    "superset-alpha": ["Alpha"],
    "superset-alpha-pilot": ["AlphaPilot"],
    "superset-gamma": ["Gamma"],
    "active-target-openinsight": ["DB_OpenInsight"],
    "active-target-engineering-data": ["DB_Engineering"],
    # Group-based RLS roles — each grants a row-level filter on fct_sales / fct_events.
    # No Executive mapping: executives use superset-admin which bypasses RLS.
    "Finance": ["Finance_RLS"],
    "HR": ["HR_RLS"],
    "Engineering": ["Engineering_RLS"],
}


def _target_serializer():
    return URLSafeSerializer(TARGET_COOKIE_SECRET, salt="openinsight-target")


def _read_selected_target() -> Optional[str]:
    raw_value = request.cookies.get(TARGET_COOKIE_NAME)
    if not raw_value:
        return None
    try:
        value = _target_serializer().loads(raw_value)
    except BadSignature:
        return None
    return value if value in TARGET_ROLE_MAP else None


def _resolve_active_target(realm_roles: list[str]) -> Optional[str]:
    allowed_targets = {
        target_id
        for target_id, role_name in TARGET_ROLE_MAP.items()
        if role_name in realm_roles
    }
    if not allowed_targets:
        return None

    selected_target = _read_selected_target()
    if selected_target in allowed_targets:
        return selected_target
    if "openinsight" in allowed_targets:
        return "openinsight"
    return sorted(allowed_targets)[0]


# --- Custom Security Manager ---
# Extracts user info + client_roles from Keycloak userinfo endpoint
class OpenInsightSecurityManager(SupersetSecurityManager):
    def oauth_user_info(self, provider, response=None):
        if provider == "keycloak":
            me = self.appbuilder.sm.oauth_remotes[provider].get(
                f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/userinfo"
            )
            me.raise_for_status()
            data = me.json()
            # Combine client roles (superset-alpha, superset-gamma, etc.) with
            # group memberships (Finance, HR, Engineering) so AUTH_ROLES_MAPPING
            # can assign both functional roles AND group-scoped RLS roles.
            client_roles = data.get("client_roles", [])
            groups = data.get("groups", [])
            realm_roles = data.get("roles", [])
            role_keys = client_roles + groups
            if PILOT_CLIENT_ROLE in client_roles:
                active_target = _resolve_active_target(realm_roles)
                if active_target:
                    role_keys.append(f"active-target-{active_target}")
            return {
                "username": data.get("preferred_username", ""),
                "first_name": data.get("given_name", ""),
                "last_name": data.get("family_name", ""),
                "email": data.get("email", ""),
                "role_keys": role_keys,
            }
        return {}


CUSTOM_SECURITY_MANAGER = OpenInsightSecurityManager

_SUPERSET_URL = os.environ.get("SUPERSET_URL", "http://localhost:8088")
LOGOUT_REDIRECT_URL = (
    f"{KEYCLOAK_EXTERNAL_URL}/realms/{KEYCLOAK_REALM}"
    f"/protocol/openid-connect/logout"
    f"?client_id={os.environ.get('SUPERSET_KEYCLOAK_CLIENT_ID', 'superset')}"
    f"&post_logout_redirect_uri={_quote(_SUPERSET_URL)}"
)

# --- Feature flags ---
FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
    "ROW_LEVEL_SECURITY": True,
}

# --- CSRF / session hardening ---
WTF_CSRF_ENABLED = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
