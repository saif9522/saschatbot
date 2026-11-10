#!/usr/bin/env bash
# Update the backend on the VPS after you have new code.
#  A) Code from GitHub (if the app folder is a git checkout):   bash /home/sasbot/app/deploy/update.sh
#  B) Code from a zip: upload + unzip it anywhere, then run its deploy/vps-setup.sh as root (it copies the code,
#     keeps your .env, rebuilds and reloads).
set -euo pipefail
APP_DIR=/home/sasbot/app
cd "$APP_DIR"
if [ -d .git ]; then git pull --ff-only; fi
npm ci --no-audit --no-fund
npx prisma generate
npm run build
pm2 reload deploy/ecosystem.config.js --update-env
sleep 5
curl -fsS http://127.0.0.1:4100/api/health && echo && echo "Updated."
