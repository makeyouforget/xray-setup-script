# Xray Setup Script

One-command setup for an [Xray](https://github.com/XTLS/Xray-core) VLESS + REALITY server on Linux.

## What it does

- Installs Xray if not already present (via the official installer)
- Generates a UUID, X25519 key pair, and a random Short ID
- Writes a VLESS + REALITY config to `/usr/local/etc/xray/config.json`
- Restarts the Xray systemd service
- Prints a ready-to-import VLESS share link

## Quick install

```bash
bash <(curl -L https://raw.githubusercontent.com/makeyouforget/xray-setup-script/refs/heads/main/setup.sh)
```

> **Requires root.** Run as root or prefix with `sudo`.

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-s`, `--sni <domain>` | SNI domain for REALITY | `icloud.com` |
| `-f`, `--fingerprint <fp>` | TLS fingerprint | `chrome` |
| `-p`, `--port <port>` | Listening port | Random 10000–60000 |
| `-n`, `--name <name>` | Link display name | Server IP |
| `-h`, `--help` | Show help | — |

**Supported fingerprints:** `chrome`, `firefox`, `safari`, `ios`, `android`, `edge`, `360`, `qq`, `random`, `randomized`

## Examples

```bash
# Default settings
bash <(curl -L https://raw.githubusercontent.com/makeyouforget/xray-setup-script/refs/heads/main/setup.sh)

# Custom SNI and port
bash <(curl -L https://raw.githubusercontent.com/makeyouforget/xray-setup-script/refs/heads/main/setup.sh) -s apple.com -p 443

# Firefox fingerprint with a custom link name
bash <(curl -L https://raw.githubusercontent.com/makeyouforget/xray-setup-script/refs/heads/main/setup.sh) -f firefox -n "my-server"
```

## Requirements

- Linux with systemd
- `curl`, `openssl`
- Root privileges