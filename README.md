# Xray Setup Scripts

Bash scripts for deploying [Xray-core](https://github.com/XTLS/Xray-core) with **VLESS + Reality + XTLS-Vision** — either as a single-hop proxy or a two-hop (multihop) chain.

---

## Scripts

| Script | Description |
|---|---|
| `setup.sh` | Single-server setup — run directly on the target VPS |
| `setup-multihop.sh` | Two-server chain — run locally, connects to both servers via SSH |

---

## `setup.sh` — Single-Hop

### Requirements

- Debian/Ubuntu VPS
- Root or `sudo` access
- Run **on the server** itself

### Required packages

Before running the script, update the system and install the required packages on the server:

```bash
apt update -y && apt upgrade -y
apt install -y curl openssl unzip wget
```

### Usage

```bash
# One-liner
bash <(curl -L https://raw.githubusercontent.com/makeyouforget/xray-setup-scripts/refs/heads/main/setup.sh)

# With options
bash <(curl -L https://raw.githubusercontent.com/makeyouforget/xray-setup-scripts/refs/heads/main/setup.sh) --sni www.microsoft.com --port 8443

# Or download and run
curl -L -o setup.sh https://raw.githubusercontent.com/makeyouforget/xray-setup-scripts/refs/heads/main/setup.sh
bash setup.sh [OPTIONS]
```

### Options

| Flag | Description | Default |
|---|---|---|
| `-s`, `--sni <domain>` | SNI domain for Reality | `icloud.com` |
| `-f`, `--fingerprint <fp>` | TLS fingerprint | `chrome` |
| `-p`, `--port <port>` | Listening port | `443` |
| `-r`, `--random-port` | Use a random port (10000–60000) | — |
| `-n`, `--name <name>` | Link name shown in client | Server IP |
| `-h`, `--help` | Show help | — |

**Supported fingerprints:** `chrome`, `firefox`, `safari`, `ios`, `android`, `edge`, `360`, `qq`, `random`, `randomized`

### What it does

1. Installs Xray-core via the official install script
2. Generates a UUID, x25519 keypair, and a random short ID
3. Writes the Xray config to `/usr/local/etc/xray/config.json`
4. Restarts and validates the Xray systemd service
5. Prints a ready-to-import **VLESS share link**

### Example

```bash
# Defaults — port 443, icloud.com SNI, chrome fingerprint
bash setup.sh

# Random port
bash setup.sh --random-port

# Custom SNI and port
bash setup.sh --sni www.microsoft.com --port 8443 --name "my-vps"
```

---

## `setup-multihop.sh` — Two-Hop Chain

### Architecture

```
Client → Server 1 (Entry) → Server 2 (Exit) → Internet
```

The client only connects to Server 1. Server 1 forwards all traffic to Server 2, which then reaches the internet. Both hops use VLESS + Reality + XTLS-Vision.

### Requirements

- **Local machine:** `ssh`, `scp`, `openssl` must be installed
- **Both servers:** Debian/Ubuntu with SSH access (root or sudo user)
- SSH key-based authentication recommended (no password prompts during deployment)

### Required packages

Before running the script, install the required packages on **each server**:

```bash
apt update -qq
apt install -y curl wget unzip ca-certificates net-tools iproute2 iptables socat cron logrotate
```

### Usage

```bash
# One-liner
bash <(curl -L https://raw.githubusercontent.com/makeyouforget/xray-setup-scripts/refs/heads/main/setup-multihop.sh)

# Or download and run
curl -L -o setup-multihop.sh https://raw.githubusercontent.com/makeyouforget/xray-setup-scripts/refs/heads/main/setup-multihop.sh
bash setup-multihop.sh
```

The script is interactive — it will prompt for each server's details.

### Prompted values

| Prompt | Description | Default |
|---|---|---|
| IP address | Public IP of the server | — |
| SSH user | User to connect as | `root` |
| SSH port | SSH listening port | `22` |
| Xray listen port | Port Xray will bind to; enter `r` for a random port (10000–60000) | `443` |
| Reality SNI | Domain to impersonate | `www.microsoft.com` |

### What it does

1. Checks local dependencies (`ssh`, `scp`, `openssl`)
2. Collects connection details for both servers interactively
3. Tests SSH connectivity to both servers
4. Installs Xray-core on **both servers** remotely
5. Generates x25519 keypairs, UUIDs, and short IDs for each hop
6. Builds Xray configs:
   - **Server 1** — inbound from client, outbound to Server 2
   - **Server 2** — inbound from Server 1, outbound to internet
7. Deploys configs via `scp`, validates, and restarts Xray on both servers
8. Saves output files locally

### Output files

Saved to `./xray-multihop-<timestamp>/`:

| File | Contents |
|---|---|
| `server1.json` | Entry node Xray configuration |
| `server2.json` | Exit node Xray configuration |
| `client.txt` | All credentials and the importable VLESS share link |

### Resume support

If the script is interrupted, a `xray-multihop.state` file is saved in the current directory. Re-running the script will offer to resume from where it left off, skipping already-completed steps.

---

## Troubleshooting

**Xray failed to start:**
```bash
journalctl -u xray -n 50 --no-pager
```

**Check Xray config validity:**
```bash
xray -test -config /usr/local/etc/xray/config.json
```

**Check Xray service status:**
```bash
systemctl status xray
```
