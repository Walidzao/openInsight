import os
from flask_appbuilder.security.manager import AUTH_OAUTH
from airflow.www.security import AirflowSecurityManager

# =============================================================================
# OpenInsight Airflow Webserver Configuration
# Auth: Keycloak OIDC (realm: openinsight, client: airflow)
# =============================================================================

KEYCLOAK_INTERNAL_URL = os.environ.get("KEYCLOAK_INTERNAL_URL", "http://keycloak:8080")
KEYCLOAK_EXTERNAL_URL = os.environ.get("KEYCLOAK_EXTERNAL_URL", "http://localhost:8080")
KEYCLOAK_REALM = os.environ.get("KEYCLOAK_REALM", "openinsight")

AUTH_TYPE = AUTH_OAUTH

OAUTH_PROVIDERS = [
    {
        "name": "keycloak",
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": os.environ.get("AIRFLOW_KEYCLOAK_CLIENT_ID", "airflow"),
            "client_secret": os.environ.get("AIRFLOW_KEYCLOAK_SECRET", "airflow-dev-secret"),
            # OIDC auto-discovery — Authlib fetches jwks_uri, token endpoint, etc.
            "server_metadata_url": (
                f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}"
                "/.well-known/openid-configuration"
            ),
            # Server-side: Airflow backend → Keycloak (Docker internal network)
            "api_base_url": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect",
            "access_token_url": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token",
            "jwks_uri": f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/certs",
            # Browser-side: user's browser → Keycloak (localhost)
            "authorize_url": f"{KEYCLOAK_EXTERNAL_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/auth",
            "client_kwargs": {
                "scope": "openid profile email",
                "token_endpoint_auth_method": "client_secret_post",
                # Keycloak tokens carry iss=http://localhost:8080/... but Airflow
                # fetches discovery from http://keycloak:8080/... (Docker internal).
                # The two differ — accept both issuers.
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

# Auto-register new users on first SSO login
AUTH_USER_REGISTRATION = True
AUTH_USER_REGISTRATION_ROLE = "Public"
AUTH_ROLES_SYNC_AT_LOGIN = True

# Map Keycloak client roles (airflow client) → Airflow FAB roles
AUTH_ROLES_MAPPING = {
    "airflow-admin": ["Admin"],
    "airflow-trigger": ["Op"],
    "airflow-viewer": ["Viewer"],
}


class OpenInsightAirflowSecurityManager(AirflowSecurityManager):
    """
    Custom security manager that extracts user info and client_roles
    from the Keycloak userinfo endpoint.
    """

    def oauth_user_info(self, provider, response=None):
        if provider == "keycloak":
            me = self.appbuilder.sm.oauth_remotes[provider].get(
                f"{KEYCLOAK_INTERNAL_URL}/realms/{KEYCLOAK_REALM}"
                "/protocol/openid-connect/userinfo"
            )
            me.raise_for_status()
            data = me.json()
            return {
                "username": data.get("preferred_username", ""),
                "first_name": data.get("given_name", ""),
                "last_name": data.get("family_name", ""),
                "email": data.get("email", ""),
                # client_roles is injected by the Keycloak "client-roles" protocol mapper
                "role_keys": data.get("client_roles", []),
            }
        return {}


SECURITY_MANAGER_CLASS = OpenInsightAirflowSecurityManager
