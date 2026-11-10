#!/usr/bin/env bash
# =====================================================================
#  Makes the backend public at https://<domain> (default api.saschatbot.com)
#  with a free SSL certificate and WebSocket support (live dashboard updates).
#   - Server WITH cPanel/WHM: uses cPanel's Apache + AutoSSL.
#     First create the subdomain in cPanel → Domains (Document root anything, e.g. public_html/api).
#   - Server WITHOUT cPanel: installs Nginx + Let's Encrypt (certbot).
#  Before running: DNS "A" record  api  →  this server's IP  must already exist.
#  Run as root:   bash deploy/proxy-setup.sh api.saschatbot.com you@email.com
# =====================================================================
set -euo pipefail
DOMAIN="${1:-api.saschatbot.com}"
EMAIL="${2:-}"
PORT=4100

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mXX  %s\033[0m\n' "$*"; exit 1; }
[ "$(id -u)" = 0 ] || die "Run as root"

curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 || die "Backend is not running on port $PORT. Run deploy/vps-setup.sh first."

MYIP=$(curl -fsS https://api.ipify.org 2>/dev/null || true)
DNSIP=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1{print $1}' || true)
if [ -z "$DNSIP" ]; then die "$DOMAIN has no DNS record yet. Add an A record: $DOMAIN → ${MYIP:-<server IP>} and wait 5–30 minutes."; fi
[ -n "$MYIP" ] && [ "$DNSIP" != "$MYIP" ] && warn "$DOMAIN points to $DNSIP but this server is $MYIP. SSL will fail until DNS is fixed."

# ---------------------------------------------------------------- cPanel / WHM
if [ -d /usr/local/cpanel ]; then
  say "cPanel found – configuring Apache"
  CPUSER=$(awk -F': ' -v d="$DOMAIN" '$1==d{print $2}' /etc/userdomains | head -1)
  [ -n "$CPUSER" ] || die "Subdomain $DOMAIN not found in cPanel. Create it in cPanel → Domains first, then run this again."

  # WebSocket proxy module (EasyApache 4)
  if ! httpd -M 2>/dev/null | grep -q proxy_wstunnel; then
    say "Installing Apache WebSocket module"
    (dnf install -y ea-apache24-mod_proxy_wstunnel || yum install -y ea-apache24-mod_proxy_wstunnel || apt-get install -y ea-apache24-mod-proxy-wstunnel) || \
      warn "Could not install mod_proxy_wstunnel – the bot works, only live dashboard updates fall back to polling."
  fi

  CONF='# keep /.well-known on Apache so AutoSSL can verify the domain
ProxyPass /.well-known !
ProxyPreserveHost On
ProxyRequests Off
RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
RewriteEngine On
RewriteCond %{REQUEST_URI} !^/\.well-known/
RewriteCond %{HTTP:Upgrade} =websocket [NC]
RewriteRule ^/(.*)$ ws://127.0.0.1:'"$PORT"'/$1 [P,L]
ProxyPass / http://127.0.0.1:'"$PORT"'/ timeout=120
ProxyPassReverse / http://127.0.0.1:'"$PORT"'/'
  for kind in std ssl; do
    d="/etc/apache2/conf.d/userdata/$kind/2_4/$CPUSER/$DOMAIN"
    mkdir -p "$d"; printf '%s\n' "$CONF" > "$d/sas-chatbot-proxy.conf"
  done
  /scripts/rebuildhttpdconf
  /scripts/restartsrv_httpd
  say "Requesting a free SSL certificate (AutoSSL) – can take a few minutes"
  /usr/local/cpanel/bin/autossl_check --user="$CPUSER" || warn "Run AutoSSL from WHM → Manage AutoSSL if https doesn't work in 10 minutes."
  /scripts/rebuildhttpdconf && /scripts/restartsrv_httpd
else
# ---------------------------------------------------------------- plain server: Nginx + certbot
  say "No cPanel – setting up Nginx"
  if command -v apt-get >/dev/null; then
    apt-get install -y nginx certbot python3-certbot-nginx
    SITE=/etc/nginx/sites-available/sas-chatbot; LINK=/etc/nginx/sites-enabled/sas-chatbot
  else
    (dnf install -y epel-release || yum install -y epel-release) || true
    (dnf install -y nginx certbot python3-certbot-nginx || yum install -y nginx certbot python3-certbot-nginx)
    SITE=/etc/nginx/conf.d/sas-chatbot.conf; LINK=""
  fi
  cat > "$SITE" <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 25m;          # flow images / documents

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;     # WebSocket (live dashboard)
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
NGINX
  [ -n "$LINK" ] && ln -sf "$SITE" "$LINK"
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  # open the firewall for web traffic only (port 4100 stays closed)
  if command -v ufw >/dev/null && ufw status | grep -q active; then ufw allow 'Nginx Full' || true; fi
  if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=http --add-service=https && firewall-cmd --reload
  fi
  command -v getenforce >/dev/null && [ "$(getenforce)" = Enforcing ] && setsebool -P httpd_can_network_connect 1 || true
  say "Getting a free SSL certificate (Let's Encrypt)"
  if [ -n "$EMAIL" ]; then certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
  else certbot --nginx -d "$DOMAIN" --redirect; fi
fi

say "Checking https://$DOMAIN/api/health"
sleep 3
if curl -fsS "https://$DOMAIN/api/health"; then
  echo; say "Done! Backend is live at https://$DOMAIN/api"
else
  warn "https not answering yet (SSL may still be issuing). Try in a few minutes:  curl https://$DOMAIN/api/health"
fi
