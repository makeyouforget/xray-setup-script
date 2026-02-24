#!/usr/bin/env bash
# =============================================================================
# Xray Multihop Setup Script
# Architecture: Client → Server 1 (Entry) → Server 2 (Exit) → Internet
# Protocol:     VLESS + Reality + RPRX Vision on both hops
# =============================================================================


# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $*"; }
info()  { echo -e "${BLUE}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

# ── Dependency check (local) ──────────────────────────────────────────────────
for cmd in ssh scp openssl; do
    command -v "$cmd" >/dev/null 2>&1 || error "Required local tool not found: $cmd"
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}"
cat << 'BANNER'
 ╔══════════════════════════════════════════════════════════════╗
 ║        Xray Multihop Setup — VLESS + Reality + Vision        ║
 ║   Client → Server1 (Entry) → Server2 (Exit) → Internet       ║
 ╚══════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── State file ────────────────────────────────────────────────────────────────
STATE_FILE="$(pwd)/xray-multihop.state"

# Initialise all variables (required by set -u before state file is sourced)
S1_IP="" S1_USER="" S1_SSH_PORT="" S1_XRAY_PORT="" S1_SNI=""
S2_IP="" S2_USER="" S2_SSH_PORT="" S2_XRAY_PORT="" S2_SNI=""
S1_UUID="" S1_SHORT_ID="" S1_PRIVATE_KEY="" S1_PUBLIC_KEY=""
S2_UUID="" S2_SHORT_ID="" S2_PRIVATE_KEY="" S2_PUBLIC_KEY=""
OUTDIR="" DONE_INSTALL="" DONE_KEYS="" DONE_CONFIGS="" DONE_DEPLOY=""

save_state() {
    cat > "$STATE_FILE" << SEOF
# Xray Multihop state — saved $(date)
S1_IP="${S1_IP}"
S1_USER="${S1_USER}"
S1_SSH_PORT="${S1_SSH_PORT}"
S1_XRAY_PORT="${S1_XRAY_PORT}"
S1_SNI="${S1_SNI}"
S2_IP="${S2_IP}"
S2_USER="${S2_USER}"
S2_SSH_PORT="${S2_SSH_PORT}"
S2_XRAY_PORT="${S2_XRAY_PORT}"
S2_SNI="${S2_SNI}"
S1_UUID="${S1_UUID:-}"
S1_SHORT_ID="${S1_SHORT_ID:-}"
S1_PRIVATE_KEY="${S1_PRIVATE_KEY:-}"
S1_PUBLIC_KEY="${S1_PUBLIC_KEY:-}"
S2_UUID="${S2_UUID:-}"
S2_SHORT_ID="${S2_SHORT_ID:-}"
S2_PRIVATE_KEY="${S2_PRIVATE_KEY:-}"
S2_PUBLIC_KEY="${S2_PUBLIC_KEY:-}"
OUTDIR="${OUTDIR:-}"
DONE_INSTALL="${DONE_INSTALL:-}"
DONE_KEYS="${DONE_KEYS:-}"
DONE_CONFIGS="${DONE_CONFIGS:-}"
DONE_DEPLOY="${DONE_DEPLOY:-}"
SEOF
}

# ── Resume detection ──────────────────────────────────────────────────────────
if [[ -f "$STATE_FILE" ]]; then
    echo -e "${YELLOW}[!]${NC} Existing state file found: ${STATE_FILE}"
    read -r -p "  Resume previous run? [Y/n]: " _resume
    _resume="${_resume:-Y}"
    if [[ "$_resume" =~ ^[Yy]$ ]]; then
        # shellcheck source=/dev/null
        source "$STATE_FILE"
        log "State loaded — resuming."
        [[ -n "$DONE_INSTALL"  ]] && info "  ✓ Install step already done"
        [[ -n "$DONE_KEYS"     ]] && info "  ✓ Key generation already done"
        [[ -n "$DONE_CONFIGS"  ]] && info "  ✓ Config generation already done"
        [[ -n "$DONE_DEPLOY"   ]] && info "  ✓ Deployment already done"
    else
        rm -f "$STATE_FILE"
        log "Starting fresh — state file removed."
    fi
fi

# ── Input helpers ─────────────────────────────────────────────────────────────
prompt() {
    # prompt <var_name> <question> [default]
    local var="$1" question="$2" default="${3:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" [${default}]"
    read -r -p "  ${question}${hint}: " value
    value="${value:-$default}"
    [[ -z "$value" ]] && error "Value required for: ${question}"
    printf -v "$var" '%s' "$value"
}

# ── Collect server info (skip if already loaded from state) ───────────────────
if [[ -z "$S1_IP" ]]; then
    step "Server 1 — Entry Node"
    prompt S1_IP        "IP address"
    prompt S1_USER      "SSH user"          "root"
    prompt S1_SSH_PORT  "SSH port"          "22"
    prompt S1_XRAY_PORT "Xray listen port"  "443"
    prompt S1_SNI       "Reality SNI"       "www.microsoft.com"

    echo ""
    step "Server 2 — Exit Node"
    prompt S2_IP        "IP address"
    prompt S2_USER      "SSH user"          "root"
    prompt S2_SSH_PORT  "SSH port"          "22"
    prompt S2_XRAY_PORT "Xray listen port"  "443"
    prompt S2_SNI       "Reality SNI"       "www.microsoft.com"

    save_state
else
    step "Resuming with saved server config"
    info "  Server 1: ${S1_USER}@${S1_IP}:${S1_SSH_PORT}  (Xray :${S1_XRAY_PORT})"
    info "  Server 2: ${S2_USER}@${S2_IP}:${S2_SSH_PORT}  (Xray :${S2_XRAY_PORT})"
fi

# ── Build SSH/SCP option strings ──────────────────────────────────────────────
S1_OPTS="-p ${S1_SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=15"
S2_OPTS="-p ${S2_SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=15"
S1_SCP_OPTS="-P ${S1_SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=15"
S2_SCP_OPTS="-P ${S2_SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=15"

ssh_s1() { ssh $S1_OPTS "${S1_USER}@${S1_IP}" "$@"; }
ssh_s2() { ssh $S2_OPTS "${S2_USER}@${S2_IP}" "$@"; }

# ── Test connectivity ─────────────────────────────────────────────────────────
step "Testing SSH Connectivity"

log "Checking Server 1 (${S1_IP})..."
if ! ssh_s1 "echo ok" >/dev/null; then
    error "Cannot connect to Server 1 (${S1_USER}@${S1_IP}:${S1_SSH_PORT}). Check IP/user/port and ensure SSH access is configured."
fi
log "Server 1 reachable ✓"

log "Checking Server 2 (${S2_IP})..."
if ! ssh_s2 "echo ok" >/dev/null; then
    error "Cannot connect to Server 2 (${S2_USER}@${S2_IP}:${S2_SSH_PORT}). Check IP/user/port and ensure SSH access is configured."
fi
log "Server 2 reachable ✓"

# ── Working directory ─────────────────────────────────────────────────────────
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
chmod 700 "$WORKDIR"

# ── Install packages & Xray on a server ──────────────────────────────────────
install_server() {
    local label="$1" ssh_opts="$2" user="$3" ip="$4"
    log "Preparing ${label} (${ip}) — installing Xray..."

    ssh $ssh_opts "${user}@${ip}" bash << 'REMOTE'
set -euo pipefail

# ── Install / update Xray-core ─────────────────────────────────────────────
XRAY_INSTALL_SCRIPT="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
if command -v xray >/dev/null 2>&1; then
    echo "[*] Xray already installed: $(xray version 2>&1 | head -1)"
    echo "[*] Checking for updates..."
    bash -c "$(curl -fsSL ${XRAY_INSTALL_SCRIPT})" @ install 2>&1 | tail -5
else
    echo "[*] Installing Xray-core..."
    bash -c "$(curl -fsSL ${XRAY_INSTALL_SCRIPT})" @ install 2>&1 | tail -10
fi

# ── Ensure systemd service is enabled ──────────────────────────────────────
systemctl enable xray 2>/dev/null || true
echo "[+] Xray version: $(xray version 2>&1 | head -1)"

REMOTE
}

if [[ -z "$DONE_INSTALL" ]]; then
    step "Installing Packages & Xray"
    install_server "Server 1" "$S1_OPTS" "$S1_USER" "$S1_IP"
    install_server "Server 2" "$S2_OPTS" "$S2_USER" "$S2_IP"
    DONE_INSTALL="yes"
    save_state
else
    step "Installing Packages & Xray"
    info "Skipping — already completed."
fi

# ── Generate Reality x25519 keypairs (on remote, using xray binary) ───────────
gen_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

step "Generating Reality Keys"

if [[ -z "$DONE_KEYS" ]]; then
    log "Generating x25519 keypair for Server 1..."
    S1_KEYS=$(ssh_s1 "xray x25519")
    S1_PRIVATE_KEY=$(echo "$S1_KEYS" | grep -iE '^(privatekey):' | awk '{print $NF}')
    S1_PUBLIC_KEY=$(echo  "$S1_KEYS" | grep -iE '^(password):' | awk '{print $NF}')
    [[ -z "$S1_PRIVATE_KEY" ]] && error "Failed to generate keys on Server 1"

    log "Generating x25519 keypair for Server 2..."
    S2_KEYS=$(ssh_s2 "xray x25519")
    S2_PRIVATE_KEY=$(echo "$S2_KEYS" | grep -iE '^(privatekey):' | awk '{print $NF}')
    S2_PUBLIC_KEY=$(echo  "$S2_KEYS" | grep -iE '^(password):' | awk '{print $NF}')
    [[ -z "$S2_PRIVATE_KEY" ]] && error "Failed to generate keys on Server 2"

    S1_UUID=$(gen_uuid)
    S2_UUID=$(gen_uuid)
    S1_SHORT_ID=$(openssl rand -hex 8)
    S2_SHORT_ID=$(openssl rand -hex 8)

    DONE_KEYS="yes"
    save_state
else
    info "Skipping key generation — already completed."
fi

info "S1 Public Key: ${S1_PUBLIC_KEY}"
info "S1 UUID:      ${S1_UUID}"
info "S1 Short ID:  ${S1_SHORT_ID}"
info "S2 Public Key: ${S2_PUBLIC_KEY}"
info "S2 UUID:      ${S2_UUID}"
info "S2 Short ID:  ${S2_SHORT_ID}"

# ── Generate Server 1 config (Entry) ─────────────────────────────────────────
if [[ -n "$DONE_CONFIGS" ]]; then
    step "Generating Xray Configs"
    info "Skipping — already completed."
else
step "Generating Xray Configs"
log "Building Server 1 config (Entry node)..."

cat > "${WORKDIR}/server1.json" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "port": ${S1_XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${S1_UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${S1_SNI}:443",
          "xver": 0,
          "serverNames": [
            "${S1_SNI}"
          ],
          "privateKey": "${S1_PRIVATE_KEY}",
          "shortIds": [
            "${S1_SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "vless-to-exit",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${S2_IP}",
            "port": ${S2_XRAY_PORT},
            "users": [
              {
                "id": "${S2_UUID}",
                "flow": "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "serverName": "${S2_SNI}",
          "publicKey": "${S2_PUBLIC_KEY}",
          "shortId": "${S2_SHORT_ID}",
          "spiderX": "/"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["vless-in"],
        "outboundTag": "vless-to-exit"
      }
    ]
  }
}
EOF

# ── Generate Server 2 config (Exit) ──────────────────────────────────────────
log "Building Server 2 config (Exit node)..."

cat > "${WORKDIR}/server2.json" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "port": ${S2_XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${S2_UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${S2_SNI}:443",
          "xver": 0,
          "serverNames": [
            "${S2_SNI}"
          ],
          "privateKey": "${S2_PRIVATE_KEY}",
          "shortIds": [
            "${S2_SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

log "Configs generated ✓"

[[ -z "$OUTDIR" ]] && OUTDIR="$(pwd)/xray-multihop-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTDIR"
cp "${WORKDIR}/server1.json" "${OUTDIR}/server1.json"
cp "${WORKDIR}/server2.json" "${OUTDIR}/server2.json"

DONE_CONFIGS="yes"
save_state
fi  # end of config generation block

# ── Deploy configs ────────────────────────────────────────────────────────────
if [[ -z "$DONE_DEPLOY" ]]; then
    step "Deploying Configs"

    # Restore config files from OUTDIR if WORKDIR was cleaned up on resume
    if [[ ! -f "${WORKDIR}/server1.json" ]] && [[ -f "${OUTDIR}/server1.json" ]]; then
        cp "${OUTDIR}/server1.json" "${WORKDIR}/server1.json"
        cp "${OUTDIR}/server2.json" "${WORKDIR}/server2.json"
    fi

    log "Deploying to Server 1 (${S1_IP})..."
    scp $S1_SCP_OPTS "${WORKDIR}/server1.json" "${S1_USER}@${S1_IP}:/usr/local/etc/xray/config.json"

    ssh_s1 bash << 'REMOTE'
mkdir -p /var/log/xray
xray -test -config /usr/local/etc/xray/config.json && echo "[+] Config valid" || { echo "[!] Config test failed"; exit 1; }
systemctl restart xray
sleep 2
systemctl is-active xray && echo "[+] Xray running on Server 1" || { journalctl -u xray -n 30 --no-pager; exit 1; }
REMOTE

    log "Deploying to Server 2 (${S2_IP})..."
    scp $S2_SCP_OPTS "${WORKDIR}/server2.json" "${S2_USER}@${S2_IP}:/usr/local/etc/xray/config.json"

    ssh_s2 bash << 'REMOTE'
mkdir -p /var/log/xray
xray -test -config /usr/local/etc/xray/config.json && echo "[+] Config valid" || { echo "[!] Config test failed"; exit 1; }
systemctl restart xray
sleep 2
systemctl is-active xray && echo "[+] Xray running on Server 2" || { journalctl -u xray -n 30 --no-pager; exit 1; }
REMOTE

    DONE_DEPLOY="yes"
    save_state
else
    step "Deploying Configs"
    info "Skipping — already completed."
fi

# ── Generate client share link (VLESS URI for entry node) ────────────────────
# VLESS URI format: vless://uuid@host:port?security=reality&sni=...&fp=...&pbk=...&sid=...&flow=xtls-rprx-vision&type=tcp#name
CLIENT_LINK="vless://${S1_UUID}@${S1_IP}:${S1_XRAY_PORT}?security=reality&sni=${S1_SNI}&fp=chrome&pbk=${S1_PUBLIC_KEY}&sid=${S1_SHORT_ID}&flow=xtls-rprx-vision&type=tcp#multihop-entry"

cat > "${OUTDIR}/client.txt" << EOF
══════════════════════════════════════════════════════════════════
  Xray Multihop — Client Configuration
  Architecture: Client → ${S1_IP} → ${S2_IP} → Internet
══════════════════════════════════════════════════════════════════

── Server 1 (Entry) ──────────────────────────────────────────────
  Address:       ${S1_IP}
  Port:          ${S1_XRAY_PORT}
  Protocol:      VLESS
  UUID:          ${S1_UUID}
  Flow:          xtls-rprx-vision
  Security:      reality
  SNI:           ${S1_SNI}
  Fingerprint:   chrome
  Public Key:    ${S1_PUBLIC_KEY}
  Short ID:      ${S1_SHORT_ID}

── Server 2 (Exit — internal, no client config needed) ───────────
  Address:       ${S2_IP}
  Port:          ${S2_XRAY_PORT}
  UUID:          ${S2_UUID}
  Public Key:    ${S2_PUBLIC_KEY}
  Short ID:      ${S2_SHORT_ID}

── VLESS Share Link (paste into Xray/V2RayNG/NekoBox/etc) ────────
${CLIENT_LINK}

EOF

# ── Summary ───────────────────────────────────────────────────────────────────
step "Done"
echo -e "${GREEN}${BOLD}"
echo "  Multihop setup complete!"
echo -e "${NC}"
echo -e "  ${BOLD}Entry node:${NC}  ${S1_IP}:${S1_XRAY_PORT}"
echo -e "  ${BOLD}Exit node:${NC}   ${S2_IP}:${S2_XRAY_PORT}"
echo ""
echo -e "  ${BOLD}Client VLESS link:${NC}"
echo -e "  ${CYAN}${CLIENT_LINK}${NC}"
echo ""
echo -e "  ${BOLD}Output files saved to:${NC} ${OUTDIR}/"
echo "    • server1.json  — entry node Xray config"
echo "    • server2.json  — exit node Xray config"
echo "    • client.txt    — client credentials & share link"
echo ""

# Clean up state file — setup fully complete
rm -f "$STATE_FILE"