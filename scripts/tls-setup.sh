#!/usr/bin/env bash
set -euo pipefail

# =========================
# HARD-CODED SETTINGS
# =========================

DOMAIN="irc.blazium.online"
EMAIL="admin@blazium.online"

# UnrealIRCd runtime identity (created if missing)
UNREAL_USER="unrealircd"
UNREAL_GROUP="unrealircd"

# UnrealIRCd config + service/process names
UNREAL_CONF="/etc/unrealircd/unrealircd.conf"
UNREAL_SERVICE="unrealircd.service"
UNREAL_PROC_NAME="unrealircd"

# Ports
TLS_PORT="6697"
PLAIN_PORT="6667"

# Certbot validation mode
# standalone = certbot runs its own temporary webserver on :80 for validation.
CERTBOT_MODE="standalone"

# Firewall behavior (UFW only)
# Script will NOT deny/block 6667. It can optionally allow ports.
UFW_ALLOW_PORT_80="yes"     # needed for http-01 renewal in standalone mode
UFW_ALLOW_TLS_PORT="yes"    # allow 6697
UFW_ALLOW_PLAIN_PORT="yes"  # allow 6667 (NO DENY)

# STS policy (clients that support IRCv3 STS will learn to use TLS on TLS_PORT)
STS_ENABLE="yes"
STS_DURATION="5m"           # start low; raise later after confirming TLS works (e.g., 1d, 30d, 180d)

# =========================
# INTERNAL CONSTANTS
# =========================
CERT_FULLCHAIN="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
CERT_PRIVKEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
DEPLOY_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
DEPLOY_HOOK_PATH="${DEPLOY_HOOK_DIR}/reload-unrealircd.sh"

log()  { echo -e "\n[+] $*\n"; }
warn() { echo -e "\n[!] $*\n" >&2; }
die()  { echo -e "\n[✗] $*\n" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
[[ -f "$UNREAL_CONF" ]] || die "UnrealIRCd config not found at: $UNREAL_CONF"

log "Checking DNS for ${DOMAIN}..."
getent ahosts "$DOMAIN" >/dev/null 2>&1 || die "DNS for $DOMAIN does not resolve here yet. Fix DNS first."

if [[ "$CERTBOT_MODE" == "standalone" ]]; then
  if ss -ltnp 2>/dev/null | grep -qE '(:80\s)'; then
    warn "Something is listening on TCP :80. Certbot standalone may fail."
    warn "Stop the web server on :80 or switch to webroot/DNS validation."
  fi
fi

# =========================
# CREATE USER/GROUP
# =========================
log "Ensuring group/user exist: ${UNREAL_GROUP}/${UNREAL_USER}..."
if ! getent group "$UNREAL_GROUP" >/dev/null 2>&1; then
  groupadd --system "$UNREAL_GROUP"
fi
if ! id "$UNREAL_USER" >/dev/null 2>&1; then
  useradd --system --gid "$UNREAL_GROUP" --home /nonexistent --shell /usr/sbin/nologin "$UNREAL_USER"
fi

# =========================
# INSTALL CERTBOT (SNAP)
# =========================
log "Installing prerequisites..."
apt-get update -y
apt-get install -y snapd psmisc ca-certificates ufw

log "Installing certbot via snap..."
snap install core >/dev/null 2>&1 || true
snap refresh core >/dev/null 2>&1 || true
snap install certbot --classic
ln -sf /snap/bin/certbot /usr/local/bin/certbot

# Enable snap renewal timer (best-effort)
systemctl enable --now snap.certbot.renew.timer >/dev/null 2>&1 || true

# =========================
# FIREWALL (UFW) - NO DENY OF 6667
# =========================
if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
  log "UFW active: applying firewall allow rules (no denies)..."
  [[ "$UFW_ALLOW_PORT_80" == "yes"   ]] && ufw allow 80/tcp >/dev/null || true
  [[ "$UFW_ALLOW_TLS_PORT" == "yes"  ]] && ufw allow "${TLS_PORT}/tcp" >/dev/null || true
  [[ "$UFW_ALLOW_PLAIN_PORT" == "yes" ]] && ufw allow "${PLAIN_PORT}/tcp" >/dev/null || true
else
  warn "UFW not active (or not installed). Skipping firewall rules."
fi

# =========================
# CERTBOT DEPLOY HOOK (PERSISTENT)
# =========================
log "Creating persistent certbot deploy hook: ${DEPLOY_HOOK_PATH}"
mkdir -p "$DEPLOY_HOOK_DIR"
cat > "$DEPLOY_HOOK_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
# Reload TLS certs in UnrealIRCd after a successful renewal/issuance
killall -USR1 ${UNREAL_PROC_NAME} 2>/dev/null || true
systemctl restart ${UNREAL_SERVICE} 2>/dev/null || true
EOF
chmod 0755 "$DEPLOY_HOOK_PATH"

# =========================
# ISSUE CERTIFICATE
# =========================
log "Requesting Let's Encrypt certificate for ${DOMAIN} (mode: ${CERTBOT_MODE})..."
if [[ "$CERTBOT_MODE" == "standalone" ]]; then
  certbot certonly \
    --standalone \
    --preferred-challenges http-01 \
    -d "$DOMAIN" \
    -m "$EMAIL" \
    --agree-tos \
    --non-interactive
else
  die "Only CERTBOT_MODE=standalone is implemented in this script."
fi

# =========================
# LETSENCRYPT PERMISSIONS (GROUP-READABLE)
# =========================
log "Applying Let's Encrypt permissions for UnrealIRCd..."
chmod go+x /etc/letsencrypt/live/ /etc/letsencrypt/archive/ || true

chown -R "root:${UNREAL_GROUP}" "/etc/letsencrypt/live/${DOMAIN}" "/etc/letsencrypt/archive/${DOMAIN}"
chmod -R g+rx,o-rwx "/etc/letsencrypt/live/${DOMAIN}" "/etc/letsencrypt/archive/${DOMAIN}"

# =========================
# PATCH UNREALIRCD CONFIG
# - Ensure TLS listener uses LE cert on TLS_PORT
# - Ensure STS policy exists (NO plaintext deny changes)
# =========================
TS="$(date +%Y%m%d-%H%M%S)"
cp -a "$UNREAL_CONF" "${UNREAL_CONF}.bak.${TS}"
log "Backed up UnrealIRCd config to: ${UNREAL_CONF}.bak.${TS}"

# 1) Ensure TLS listen block on TLS_PORT with tls-options pointing to LE certs
perl -0777 -i -pe '
  my $tlsport = $ENV{"TLS_PORT"};
  my $cert = $ENV{"CERT_FULLCHAIN"};
  my $key  = $ENV{"CERT_PRIVKEY"};

  my $has_tls_listen = ($_ =~ m/listen\s*\{[^}]*\bport\s+\Q$tlsport\E\s*;[^}]*\boptions\s*\{\s*tls\s*;\s*\}\s*;[^}]*\}/s);

  if ($has_tls_listen) {
    # Inject tls-options if missing
    $_ =~ s{
      (listen\s*\{\s*[^}]*\bport\s+\Q$tlsport\E\s*;\s*[^}]*\boptions\s*\{\s*tls\s*;\s*\}\s*;\s*)
      (?![^}]*\btls-options\s*\{)
      ([^}]*\})
    }{
      $1 . qq{    tls-options {\n        certificate "$cert";\n        key "$key";\n    };\n} . $2
    }gsex;
  } else {
    $_ .= qq{

/* Added by setup script: TLS listener */
listen {
    ip *;
    port $tlsport;
    options { tls; };
    tls-options {
        certificate "$cert";
        key "$key";
    };
};
};
  }
' TLS_PORT="$TLS_PORT" CERT_FULLCHAIN="$CERT_FULLCHAIN" CERT_PRIVKEY="$CERT_PRIVKEY" "$UNREAL_CONF"

# The perl snippet above can’t know your config style; fix a common trailing artifact if it occurs.
# (If it didn't happen, this does nothing.)
perl -i -pe 's/\n};\n};\n$/\n};\n/s' "$UNREAL_CONF" || true

# 2) Add or update STS policy: set { tls { sts-policy { port ...; duration ...; }; }; };
if [[ "$STS_ENABLE" == "yes" ]]; then
  if ! grep -qE 'sts-policy\s*\{' "$UNREAL_CONF"; then
    cat >> "$UNREAL_CONF" <<EOF

/* Added by setup script: IRCv3 STS
 * STS helps compatible clients remember to use TLS on the specified port.
 * Start low (e.g. 1m/5m), then raise after you confirm TLS works.
 */
set {
    tls {
        sts-policy {
            port ${TLS_PORT};
            duration ${STS_DURATION};
        };
    };
};
EOF
  else
    # best-effort update existing STS policy
    perl -0777 -i -pe '
      my $port = $ENV{"TLS_PORT"};
      my $dur  = $ENV{"STS_DURATION"};
      $_ =~ s/(sts-policy\s*\{.*?\bport\s+)\d+(;)/$1$port$2/sg;
      $_ =~ s/(sts-policy\s*\{.*?\bduration\s+)[^;]+(;)/$1$dur$2/sg;
    ' TLS_PORT="$TLS_PORT" STS_DURATION="$STS_DURATION" "$UNREAL_CONF"
  fi
fi

# =========================
# RESTART UNREALIRCD
# =========================
log "Restarting UnrealIRCd service: ${UNREAL_SERVICE}"
systemctl restart "$UNREAL_SERVICE" || {
  warn "systemd restart failed. Trying USR1 reload + continuing..."
  killall -USR1 "$UNREAL_PROC_NAME" 2>/dev/null || true
}

# =========================
# SUMMARY
# =========================
log "Done."
echo "TLS cert: ${CERT_FULLCHAIN}"
echo "TLS key:  ${CERT_PRIVKEY}"
echo "STS duration: ${STS_DURATION}"
echo
echo "Quick test:"
echo "  openssl s_client -connect ${DOMAIN}:${TLS_PORT} -servername ${DOMAIN} </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates"
