#!/usr/bin/env bash
set -e
docker rm -f cube-test 2>/dev/null || true
docker run -d \
  --name cube-test \
  --network openinsight \
  -p 4000:4000 \
  -p 15432:15432 \
  -e CUBEJS_DB_TYPE=clickhouse \
  -e CUBEJS_DB_HOST=clickhouse \
  -e CUBEJS_DB_PORT=8123 \
  -e CUBEJS_DB_NAME=openinsight \
  -e CUBEJS_DB_USER=openinsight \
  -e CUBEJS_DB_PASS=openinsight_dev \
  -e CUBEJS_REDIS_URL=redis://redis:6379 \
  -e CUBEJS_DEV_MODE=true \
  -e CUBEJS_API_SECRET=openinsight-cube-dev-secret \
  -v /Users/walidzaouch/Code/openInsight/cube/schema:/cube/conf/model \
  cubejs/cube:v0.35
