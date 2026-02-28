#!/usr/bin/env bash
# Usage: sudo ./setup.sh [OPTIONS]
#   -p, --port  PORT  listening port          (default: 443)
#   -d, --dest  DEST  reality dest target     (default: 1.1.1.1:443)
#   -s, --sni   SNI   server name indication  (default: "")
#   -n, --name  NAME  container name          (default: xray)
#   -h, --help        show this help and exit
set -euo pipefail

# parameters
PORT="443"
DEST="1.1.1.1:443"
SNI=""
NAME=""

usage() {
    tail -n +2 "$0" | awk '/^[^#]/{exit} {sub(/^# ?/,""); print}'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)  PORT="$2"; shift 2 ;;
        -d|--dest)  DEST="$2"; shift 2 ;;
        -s|--sni)   SNI="$2";  shift 2 ;;
        -n|--name)  NAME="$2"; shift 2 ;;
        -h|--help)  usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# constants
IMAGE="ghcr.io/xtls/xray-core"
CONTAINER_NAME="${NAME:-xray}"
CONFIG_DIR="$HOME/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"

# colours
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "${CYAN}[*]${RESET} $*"; }
ok()    { echo -e "${GREEN}[+]${RESET} $*"; }
die()   { echo -e "${RED}[!]${RESET} $*" >&2; exit 1; }

# root check
[[ $EUID -eq 0 ]] || die "Run as root: sudo $0 $*"

# check runtime
command -v docker &>/dev/null || die "'docker' not found."
ok "Runtime: $(docker --version 2>&1 | head -1)"

# pull image
info "Pulling $IMAGE ..."
docker pull "$IMAGE"
ok "Image up to date."

# stop and remove old container
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    info "Removing existing container '$CONTAINER_NAME' ..."
    docker rm -f "$CONTAINER_NAME"
fi

# generate credentials
info "Generating credentials..."

UUID=$(docker run --rm "$IMAGE" uuid)

KEYS=$(docker run --rm "$IMAGE" x25519)
PRIVATE_KEY=$(printf '%s\n' "$KEYS" | grep -iE '^(privatekey):' | awk '{print $NF}')
PUBLIC_KEY=$(printf '%s\n'  "$KEYS" | grep -iE '^(password):' | awk '{print $NF}')

SHORT_ID=$(openssl rand -hex 8)

ok "UUID:        $UUID"
ok "Public key:  $PUBLIC_KEY"
ok "Short ID:    $SHORT_ID"

# build config
info "Writing config to $CONFIG_FILE ..."
rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
{
    "log": {
        "loglevel": "info"
    },
    "inbounds": [
        {
            "port": ${PORT},
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": "${DEST}",
                    "serverNames": [
                        "${SNI}"
                    ],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": [
                        "",
                        "${SHORT_ID}"
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
        { "protocol": "freedom",   "tag": "direct" },
        { "protocol": "blackhole", "tag": "block"  }
    ]
}
EOF
ok "Config written."

# start container
info "Starting container '$CONTAINER_NAME' ..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "${PORT}:${PORT}/tcp" \
    -v "${CONFIG_FILE}:/etc/xray/config.json:ro" \
    "$IMAGE" \
    run -c /etc/xray/config.json

ok "Container started (restart policy: always)."

# detect public IP
info "Detecting server IP..."
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
         || curl -s --max-time 5 https://ifconfig.me \
         || echo "YOUR_SERVER_IP")

# build vless link
LINK_LABEL="${NAME:-${SERVER_IP}}"
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${LINK_LABEL}"

# summary
echo ""
echo -e "${BOLD}  VLESS link:${RESET}"
echo ""
echo -e "  ${GREEN}${VLESS_LINK}${RESET}"
echo ""
echo -e "${BOLD}  Config:     ${RESET}${CONFIG_FILE}"
