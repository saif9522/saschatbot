#!/usr/bin/env bash
# =====================================================================
#  SAS Chatbot backend – one-time VPS setup (BigRock or any Linux VPS)
#  Works on Ubuntu / Debian and AlmaLinux / Rocky / CentOS (with or without cPanel).
#  Database stays on Supabase. Run as root:
#     bash deploy/vps-setup.sh
#  Safe to run again: steps that are already done are skipped.
# =====================================================================
set -euo pipefail

APP_USER=sasbot
APP_HOME=/home/$APP_USER
APP_DIR=$APP_HOME/app
DATA_DIR=$APP_HOME/data
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # the folder this script came in

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mXX  %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" = 0 ] || die "Run as root (or: sudo bash deploy/vps-setup.sh)"

# ---------- 1. System packages + Node.js 22
if command -v apt-get >/dev/null; then PM=apt
elif command -v dnf >/dev/null; then PM=dnf
elif command -v yum >/dev/null; then PM=yum
else die "Unknown Linux (no apt/dnf/yum)"; fi
say "Linux package manager: $PM"

if [ "$PM" = apt ]; then
  apt-get update -y
  apt-get install -y curl git ca-certificates
else
  $PM install -y curl git ca-certificates
fi

NODE_MAJOR=$(node -v 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/' || true)
if [ "${NODE_MAJOR:-0}" -lt 22 ]; then
  say "Installing Node.js 22"
  if [ "$PM" = apt ]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  else
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
    $PM install -y nodejs
  fi
fi
say "Node $(node -v), npm $(npm -v)"

command -v pm2 >/dev/null || { say "Installing PM2 (keeps the bot running 24x7)"; npm install -g pm2; }

# ---------- 2. A separate Linux user for the app (not root)
id "$APP_USER" >/dev/null 2>&1 || { say "Creating user $APP_USER"; useradd -m -s /bin/bash "$APP_USER"; }
mkdir -p "$DATA_DIR/wa-sessions" "$DATA_DIR/uploads"

# ---------- 3. Code: copy from this folder (zip upload) or keep the existing git checkout
if [ ! -f "$APP_DIR/package.json" ]; then
  say "Copying code to $APP_DIR"
  mkdir -p "$APP_DIR"
  (cd "$SRC_DIR" && tar --exclude=node_modules --exclude=dist --exclude=.git -cf - .) | (cd "$APP_DIR" && tar -xf -)
elif [ "$SRC_DIR" != "$APP_DIR" ]; then
  say "Updating code in $APP_DIR from $SRC_DIR (your .env is kept)"
  (cd "$SRC_DIR" && tar --exclude=node_modules --exclude=dist --exclude=.git --exclude=.env -cf - .) | (cd "$APP_DIR" && tar -xf -)
fi
chown -R "$APP_USER:$APP_USER" "$APP_HOME"

# ---------- 4. Settings file
if [ ! -f "$APP_DIR/.env" ]; then
  cp "$APP_DIR/deploy/env.vps.example" "$APP_DIR/.env"
  chown "$APP_USER:$APP_USER" "$APP_DIR/.env"; chmod 600 "$APP_DIR/.env"
  warn "Created $APP_DIR/.env – fill it in now (copy values from Render → Environment):"
  echo "     nano $APP_DIR/.env"
  echo "   Then run this script again:  bash $APP_DIR/deploy/vps-setup.sh"
  exit 0
fi
chmod 600 "$APP_DIR/.env"
grep -qE '^SESSION_SECRET=.{32,}' "$APP_DIR/.env" || die "SESSION_SECRET in $APP_DIR/.env is empty or short – copy the SAME value from Render."
grep -qE '^DATABASE_URL=..+' "$APP_DIR/.env" || die "DATABASE_URL in $APP_DIR/.env is empty – copy it from Render."

# ---------- 5. Install + build (as the app user)
say "Installing packages and building (2–4 minutes)"
sudo -u "$APP_USER" -H bash -c "cd '$APP_DIR' && npm ci --no-audit --no-fund && npx prisma generate && npm run build"

# ---------- 6. Start with PM2 + start again after a reboot
say "Starting the backend with PM2"
if sudo -u "$APP_USER" -H pm2 describe sas-chatbot >/dev/null 2>&1; then
  sudo -u "$APP_USER" -H bash -c "cd '$APP_DIR' && pm2 reload deploy/ecosystem.config.js --update-env"
else
  sudo -u "$APP_USER" -H bash -c "cd '$APP_DIR' && pm2 start deploy/ecosystem.config.js"
fi
sudo -u "$APP_USER" -H pm2 save
env PATH="$PATH" pm2 startup systemd -u "$APP_USER" --hp "$APP_HOME" >/dev/null

# ---------- 7. Check
say "Waiting for the app to start"
for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:4100/api/health >/dev/null 2>&1; then
    curl -sS http://127.0.0.1:4100/api/health; echo
    say "Backend is running on this server (port 4100, only reachable from inside)."
    echo "   Next: make it public at https://api.saschatbot.com  →  bash $APP_DIR/deploy/proxy-setup.sh api.saschatbot.com"
    echo "   Logs: sudo -u $APP_USER pm2 logs sas-chatbot"
    exit 0
  fi
  sleep 2
done
warn "The app did not answer yet. Look at the logs:  sudo -u $APP_USER pm2 logs sas-chatbot --lines 80"
exit 1
