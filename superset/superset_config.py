import os
from flask_appbuilder.security.manager import AUTH_OAUTH
from superset.security import SupersetSecurityManager

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

AUTH_TYPE = AUTH_OAUTH

OAUTH_PROVIDERS = [
    {
        "name": "keycloak",
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": os.environ.get("SUPERSET_KEYCLOAK_CLIENT_ID", "superset"),
            "client_secret": os.environ.get("SUPERSET_KEYCLOAK_SECRET", "superset-dev-secret"),
            # Server-side: Superset backend → Keycloak (Docker internal network)
            "api_base_url": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect",
            "access_token_url": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token",
            "jwks_uri": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/certs",
            # Browser-side: user's browser → Keycloak (localhost)
            "authorize_url": f"{KEYCLOAK_EXTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/auth",
            "client_kwargs": {
                "scope": "openid profile email",
            },
        },
    }
]

# --- User registration & role sync ---
AUTH_USER_REGISTRATION = True
AUTH_USER_REGISTRATION_ROLE = "Public"
AUTH_ROLES_SYNC_AT_LOGIN = True

# Map Keycloak client_roles → Superset roles
# Keycloak client roles are defined in realm-openinsight.json under the superset client
AUTH_ROLES_MAPPING = {
    "superset-admin": ["Admin"],
    "superset-alpha": ["Alpha"],
    "superset-gamma": ["Gamma"],
}


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
            return {
                "username": data.get("preferred_username", ""),
                "first_name": data.get("given_name", ""),
                "last_name": data.get("family_name", ""),
                "email": data.get("email", ""),
                "role_keys": data.get("client_roles", []),
            }
        return {}


CUSTOM_SECURITY_MANAGER = OpenInsightSecurityManager
