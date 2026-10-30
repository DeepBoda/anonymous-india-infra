#!/bin/sh
# Apply pending Prisma migrations before the API starts. Idempotent, so it is
# safe on every boot; set RUN_MIGRATIONS=false to skip (e.g. multi-instance).
set -e
if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
  echo "[entrypoint] prisma migrate deploy"
  npx prisma migrate deploy
fi
exec "$@"
