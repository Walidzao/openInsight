import os

# Minimal Superset Config (M.3)
SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'changeme-generate-a-real-secret')
SQLALCHEMY_DATABASE_URI = os.environ.get('SQLALCHEMY_DATABASE_URI', 'postgresql+psycopg2://openinsight:openinsight_dev@postgres:5432/superset')
