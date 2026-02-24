#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
SNI="icloud.com"
FINGERPRINT="chrome"
PORT=""
LINK_NAME=""

# Help
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --sni <domain>       SNI domain for Reality (default: icloud.com)"
    echo "  -f, --fingerprint <fp>   TLS fingerprint (default: chrome)"
    echo "                          Supported: chrome, firefox, safari, ios, android,"
    echo "                          edge, 360, qq, random, randomized"
    echo "  -p, --port <port>        Listening port (default: random 10000-60000)"
    echo "  -n, --name <name>        Link name (default: server IP)"
    echo "  -h, --help               Show this help message"
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--sni)          SNI="$2";         shift 2 ;;
        -f|--fingerprint)  FINGERPRINT="$2"; shift 2 ;;
        -p|--port)         PORT="$2";        shift 2 ;;
        -n|--name)         LINK_NAME="$2";   shift 2 ;;
        -h|--help)      print_usage;      exit 0  ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

# Generate a random port in range 10000–60000 if none was specified
if [[ -z "$PORT" ]]; then
    PORT=$(( RANDOM % 50001 + 10000 ))
fi

# Root check
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: this script must be run as root (use sudo).${NC}"
    exit 1
fi

# Update OS and install required packages
echo -e "${YELLOW}Updating package lists and upgrading system...${NC}"
apt-get update -y
apt-get upgrade -y

echo ""
echo -e "${YELLOW}Installing required packages...${NC}"
apt-get install -y curl openssl unzip wget
echo -e "${GREEN}Packages installed.${NC}"

# Install Xray
if ! command -v xray &>/dev/null; then
    echo -e "${YELLOW}Xray not found - installing via official script...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    echo ""
    echo -e "${GREEN}Xray installed.${NC}"
else
    XRAY_VER=$(xray version 2>/dev/null | head -1 || echo "unknown")
    echo -e "${GREEN}Xray already installed: ${XRAY_VER}${NC}"
fi

# Generate cryptographic material
echo ""
echo -e "${YELLOW}Generating keys and identifiers...${NC}"

UUID=$(xray uuid)
KEYPAIR=$(xray x25519)
PRIVATE_KEY=$(printf '%s\n' "$KEYPAIR" | grep -iE '^(privatekey):' | awk '{print $NF}')
PUBLIC_KEY=$(printf '%s\n'  "$KEYPAIR" | grep -iE '^(password):' | awk '{print $NF}')
SHORT_ID=$(openssl rand -hex 8)

# Write Xray config
echo ""
echo -e "${YELLOW}Writing Xray configuration...${NC}"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
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
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

echo -e "${GREEN}Config written to ${CONFIG_FILE}${NC}"

# Restart Xray
echo ""
echo -e "${YELLOW}Restarting Xray service...${NC}"
systemctl restart xray 2>/dev/null

sleep 1

if systemctl is-active --quiet xray; then
    echo -e "${GREEN}Xray is running.${NC}"
else
    echo -e "${RED}Xray failed to start. Check logs with:${NC}"
    echo "journalctl -u xray -n 50 --no-pager"
    exit 1
fi

# Detect public IP
SERVER_IP=$(curl -s4 --max-time 5 ifconfig.me \
         || curl -s4 --max-time 5 icanhazip.com \
         || curl -s4 --max-time 5 api.ipify.org \
         || echo "YOUR_SERVER_IP")

[[ -z "$LINK_NAME" ]] && LINK_NAME="$SERVER_IP"

# Build VLESS share link
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${LINK_NAME}"

# Print summary
echo ""
echo -e "${GREEN}Address:     ${NC}${SERVER_IP}"
echo -e "${GREEN}Port:        ${NC}${PORT}"
echo -e "${GREEN}Protocol:    ${NC}VLESS"
echo -e "${GREEN}UUID:        ${NC}${UUID}"
echo -e "${GREEN}Flow:        ${NC}xtls-rprx-vision"
echo -e "${GREEN}Security:    ${NC}reality"
echo -e "${GREEN}SNI:         ${NC}${SNI}"
echo -e "${GREEN}Fingerprint: ${NC}${FINGERPRINT}"
echo -e "${GREEN}Public key:  ${NC}${PUBLIC_KEY}"
echo -e "${GREEN}Short ID:    ${NC}${SHORT_ID}"
echo ""
echo -e "${BLUE}VLESS share link:${NC}"
echo -e "${CYAN}${VLESS_LINK}${NC}"