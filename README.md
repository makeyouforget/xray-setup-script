# xray-setup-script

One-command [VLESS-TCP-XTLS-Vision-REALITY](https://github.com/XTLS/Xray-core) server setup using Docker / Podman.

## Requirements

- A server with a public IP address
- Root access

## Quick Start

### 1. Update packages and install dependencies

```bash
apt update && apt upgrade -y
apt install -y curl openssl docker.io
```

### 2. Run the setup script

```bash
curl -fsSL https://raw.githubusercontent.com/makeyouforget/xray-setup-script/refs/heads/main/setup.sh | bash
```

Or with custom options:

```bash
curl -fsSL https://raw.githubusercontent.com/makeyouforget/xray-setup-script/refs/heads/main/setup.sh -o setup.sh
chmod +x setup.sh
./setup.sh --port 443 --dest 1.1.1.1:443 --sni cloudflare.com --name xray
```

## Options

| Flag | Long flag | Default | Description |
|------|-----------|---------|-------------|
| `-p` | `--port` | `443` | Listening port |
| `-d` | `--dest` | `1.1.1.1:443` | Reality destination target |
| `-s` | `--sni` | _(empty)_ | Server Name Indication |
| `-n` | `--name` | `xray` | Container name |
| `-r` | `--runtime` | `docker` | Container runtime (`docker` or `podman`) |
| `-h` | `--help` | | Show help and exit |

## What the script does

1. Pulls the latest `ghcr.io/xtls/xray-core` image
2. Generates a fresh UUID, X25519 key pair, and short ID
3. Writes a VLESS + XTLS-Reality config to `~/xray/config.json`
4. Starts the container with `--restart always`
5. Prints a ready-to-import VLESS link

## Using Podman instead of Docker

```bash
apt install -y podman
curl -fsSL https://raw.githubusercontent.com/makeyouforget/xray-setup-script/refs/heads/main/setup.sh -o setup.sh
chmod +x setup.sh
./setup.sh --runtime podman
```
