# Linux Server Init & SSH Hardening Script

[![Test Matrix](https://github.com/247like/linux-ssh-init-sh/actions/workflows/test.yml/badge.svg)](https://github.com/247like/linux-ssh-init-sh/actions/workflows/test.yml)
![POSIX Shell](https://img.shields.io/badge/Shell-POSIX_sh-blue?style=flat-square)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/247like/linux-ssh-init-sh?style=flat-square)](https://github.com/247like/linux-ssh-init-sh/releases)
[![Stars](https://img.shields.io/github/stars/247like/linux-ssh-init-sh?style=flat-square)](https://github.com/247like/linux-ssh-init-sh/stargazers)

[![中文文档](https://img.shields.io/badge/中文-Chinese-blue)](README.md) [![English](https://img.shields.io/badge/English-EN-blue)](README_EN.md)

---

A production-ready, POSIX-compliant shell script designed to initialize Linux servers and harden SSH security in minutes.

It safely handles **SSH key deployment**, **port changing**, **user creation**, **TCP BBR enablement**, and **system updates**, while ensuring compatibility across Debian, Ubuntu, CentOS, RHEL, and Alpine Linux.

### ✨ Key Features

* **Universal Compatibility**: Works flawlessly on **Debian**, **Ubuntu**, **CentOS/RHEL**, **Alma/Rocky**, and **Alpine Linux**.
* **POSIX Compliant**: Written in pure `/bin/sh`. No `bash` dependency. Runs perfectly on `dash` (Debian) and `ash` (Alpine/Busybox).
* **Security Architecture (Fortress Pro)**:
    * **Managed Config Block**: Inserts configuration at the **top** of `sshd_config` to strictly override vendor defaults (bypasses the Debian 12 `Include` trap).
    * **Auto-Rollback**: If SSHD validation fails, port is not listening, or connection test fails during execution, the script **automatically reverts** all system changes.
    * **Service Protection (Anti-Kill)**: Adds a systemd `override.conf` to prevent OOM kills and ensures SSHD restarts automatically on failure.
    * **Deadlock Prevention**: Intelligently detects authentication states to prevent "Password Disabled + No Key" lockouts.
* **Automation Friendly**:
    * Supports **Headless Mode** allowing zero-interaction unattended installation.
    * **Audit & Reporting**: Automatically generates detailed operation audit logs and system health reports.

### 🚀 Quick Start

Run the following command as **root**.

#### 1. Interactive Run (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/247like/linux-ssh-init-sh/main/init.sh -o init.sh && chmod +x init.sh && ./init.sh
```

#### 2. Force English UI
```bash
./init.sh --lang=en
```

### 🤖 Automation (Headless Mode)

Suitable for CI/CD pipelines or bulk provisioning. Use command line arguments to pass configurations and `--yes` to skip confirmation.

#### Full Automatic Example
*(Configure Root user, random port, fetch key from GitHub, enable BBR, update system, auto-confirm)*

```bash
curl -fsSL https://raw.githubusercontent.com/247like/linux-ssh-init-sh/main/init.sh | sh -s -- \
    --user=root \
    --port=random \
    --key-gh=247like \
    --bbr \
    --update \
    --strict \
    --yes
```

#### Semi-Automatic Example
*(Specify key URL, choose other options manually)*

```bash
./init.sh --key-url=https://my-server.com/id_ed25519.pub
```

### ⚙️ Arguments

The script supports rich command-line arguments to control its behavior:

| Category | Argument | Description |
| :--- | :--- | :--- |
| **Control** | `--lang=en` | Force English UI |
| | `--yes` | **Auto Confirm**: Skip the final "Proceed?" prompt |
| | `--strict` | **Strict Mode**: Exit immediately on error (see below) |
| | `--delay-restart` | **Delay Restart**: Apply config but do not restart SSHD immediately |
| **User/Port** | `--user=root` | Specify login user (root or username) |
| | `--port=22` | Keep default port 22 |
| | `--port=random` | Generate random high port (49152-65535) |
| | `--port=2222` | Specify a specific port number |
| **Keys** | `--key-gh=username` | Fetch public key from GitHub |
| | `--key-url=url` | Download public key from URL |
| | `--key-raw="ssh-..."` | Pass public key string directly |
| **System** | `--update` | Enable system package update |
| | `--no-update` | Skip system update |
| | `--bbr` | Enable TCP BBR congestion control |
| | `--no-bbr` | Disable BBR |

### ⚙️ Normal Mode vs. Strict Mode

| Feature | Normal Mode (Default) | Strict Mode (`--strict`) |
| :--- | :--- | :--- |
| **Philosophy** | **"Don't Lockout"** (Best Effort) | **"Compliance First"** (Zero Tolerance) |
| **Key Failure** | If key download fails, script **keeps Password Auth enabled** and warns you.<br>👉 *Result: Server reachable but less secure.* | Script **exits immediately**. No changes applied.<br>👉 *Result: Deployment aborted, state unchanged.* |
| **Port Failure** | If random port fails, it falls back to **Port 22**. | Script **exits immediately**. |

### 📂 Logs & Audit

After execution, the following files are generated for troubleshooting and auditing:

* **Run Log**: `/var/log/server-init.log` (Detailed debug information)
* **Audit Log**: `/var/log/server-init-audit.log` (Records key actions, timestamps, and operators)
* **Health Report**: `/var/log/server-init-health.log` (Snapshot of the final system configuration state)

### 🆘 Disaster Recovery & Restore

The script features a dual-layer safety mechanism: **Runtime Auto-Rollback** and **Persistent Backup Restore**.

If you cannot connect to your server via SSH after the script finishes (after seeing "DONE"), log in via your Cloud Provider's **VNC / Console** and use one of the following methods.

#### Method A: One-Click Restore Script (Recommended)

The script automatically creates a backup and generates a restore script before applying changes.

1.  Find the latest backup directory:
    ```bash
    ls -ld /var/backups/ssh-config/*
    ```
2.  Enter the directory and run the restore script:
    ```bash
    # Enter the latest timestamp directory (e.g., 20250520_120000)
    cd /var/backups/ssh-config/<TIMESTAMP>/
    
    # Run the restore script
    sh restore.sh
    ```
    *This will automatically overwrite `sshd_config` and attempt to restart the SSH service.*

#### Method B: Manual Restore

If the restore script is unavailable, manually copy the files:

```bash
# 1. Overwrite configuration
cp /var/backups/ssh-config/<TIMESTAMP>/sshd_config /etc/ssh/sshd_config

# 2. Restart Service
systemctl restart sshd || service sshd restart
```

---

### ⚠️ Disclaimer

This script modifies critical system configurations (SSH). While it includes multiple safety checks and automatic rollback mechanisms, **please ensure you have an alternative access method** (such as a VNC/KVM Console) to your server to prevent lockout in case of network interruptions or unexpected configuration errors.

### 📄 License

This project is released under the [MIT License](LICENSE).

---

<div align="center">

If you found this tool helpful, please give it a ⭐ Star!

[Report Bug](https://github.com/247like/linux-ssh-init-sh/issues) · [Request Feature](https://github.com/247like/linux-ssh-init-sh/issues)

</div>
