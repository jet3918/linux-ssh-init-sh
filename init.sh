#!/bin/sh
# =========================================================
# linux-ssh-init-sh
# Server Init & SSH Hardening Script
#
# Release: v4.0.0 (Platinum Edition)
#
# POSIX sh compatible (works on Debian/CentOS/Alpine/Ubuntu)
#
# Change Log v4.0.0:
#   - FEAT: Added 'preflight_checks' for core commands/disk/mem
#   - FEAT: Robust Triple-Check IPv6 detection (Proc/IP/Ifconfig)
#   - FEAT: Backup metadata generation (.meta files)
#   - FEAT: Final Health Report generation
#   - FIX: Random port math comment clarification
#   - FIX: Replaced bash-isms (arrays) with POSIX string handling
# =========================================================

set -u
SCRIPT_START_TIME=$(date +%s)

# ---------------- Configuration ----------------
LANG_CUR="zh" # Default Language
LOG_FILE="/var/log/server-init.log"
AUDIT_FILE="/var/log/server-init-audit.log"
BACKUP_REPO="/var/backups/ssh-config"
SSH_CONF="/etc/ssh/sshd_config"
SSH_CONF_D="/etc/ssh/sshd_config.d"
DEFAULT_USER="deploy"
BLOCK_BEGIN="# BEGIN SERVER-INIT MANAGED BLOCK"
BLOCK_END="# END SERVER-INIT MANAGED BLOCK"

# Create Secure Temp Directory
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'ssh-init-XXXXXX')
chmod 700 "$TMP_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---------------- Automation Variables ----------------
ARG_USER=""
ARG_PORT=""      
ARG_KEY_TYPE="" 
ARG_KEY_VAL=""
ARG_UPDATE=""   
ARG_BBR=""      
AUTO_CONFIRM="n"
STRICT_MODE="n"
ARG_DELAY_RESTART="n"

# Parse Arguments
for a in "$@"; do
  case "$a" in
    --lang=zh)     LANG_CUR="zh" ;;
    --lang=en)     LANG_CUR="en" ;;
    --strict)      STRICT_MODE="y" ;;
    --yes)         AUTO_CONFIRM="y" ;;
    --user=*)      ARG_USER="${a#*=}" ;;
    --port=random) ARG_PORT="random" ;;
    --port=*)      ARG_PORT="${a#*=}" ;;
    --key-gh=*)    ARG_KEY_TYPE="gh";  ARG_KEY_VAL="${a#*=}" ;;
    --key-url=*)   ARG_KEY_TYPE="url"; ARG_KEY_VAL="${a#*=}" ;;
    --key-raw=*)   ARG_KEY_TYPE="raw"; ARG_KEY_VAL="${a#*=}" ;;
    --update)      ARG_UPDATE="y" ;;
    --no-update)   ARG_UPDATE="n" ;;
    --bbr)         ARG_BBR="y" ;;
    --no-bbr)      ARG_BBR="n" ;;
    --delay-restart) ARG_DELAY_RESTART="y" ;;
  esac
done

# ---------------- Logging & Audit ----------------
touch "$LOG_FILE" "$AUDIT_FILE" 2>/dev/null || true
chmod 600 "$LOG_FILE" "$AUDIT_FILE" 2>/dev/null || true

log() { echo "$(date '+%F %T') $*" >>"$LOG_FILE"; }

audit_log() {
  action="$1"
  details="$2"
  {
    echo "=== $(date '+%F %T') ==="
    echo "ACTION: $action"
    echo "USER: $(whoami 2>/dev/null || echo root)"
    echo "DETAILS: $details"
    echo "---"
  } >> "$AUDIT_FILE" 2>/dev/null || true
  log "[AUDIT] $action - $details"
}

info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; log "[INFO] $*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; log "[WARN] $*"; }
err()  { printf "${RED}[ERR ]${NC} %s\n" "$*"; log "[ERR ] $*"; }
ok()   { printf "${GREEN}[ OK ]${NC} %s\n" "$*"; log "[OK] $*"; }

die() {
  err "$*"
  exit 1
}

# ---------------- Internationalization ----------------
msg() {
  key="$1"
  if [ "$LANG_CUR" = "zh" ]; then
    case "$key" in
      MUST_ROOT)    echo "必须以 root 权限运行此脚本" ;;
      BANNER)       echo "服务器初始化 & SSH 安全加固 (v4.0.0 Platinum)" ;;
      STRICT_ON)    echo "STRICT 模式已开启：任何关键错误将直接退出" ;;
      ASK_USER)     echo "SSH 登录用户 (root 或普通用户，默认 " ;;
      ERR_USER_INV) echo "❌ 用户名无效 (仅限小写字母/数字/下划线，且避开系统保留名)" ;;
      ASK_PORT_T)   echo "SSH 端口配置：" ;;
      OPT_PORT_1)   echo "1) 使用 22 (默认)" ;;
      OPT_PORT_2)   echo "2) 随机高端口 (49152+, 自动避开 K8s)" ;;
      OPT_PORT_3)   echo "3) 手动指定" ;;
      SELECT)       echo "请选择 [1-3]: " ;;
      INPUT_PORT)   echo "请输入端口号 (1024-65535): " ;;
      PORT_ERR)     echo "❌ 端口输入无效 (非数字或超范围)" ;;
      PORT_RES)     echo "❌ 端口被系统保留或不建议使用 (如 80, 443, 3306 等)" ;;
      PORT_K8S)     echo "⚠️  警告: 此端口位于 Kubernetes NodePort 常用范围 (30000-32767)，可能冲突" ;;
      ASK_KEY_T)    echo "SSH 公钥来源：" ;;
      OPT_KEY_1)    echo "1) GitHub 用户导入" ;;
      OPT_KEY_2)    echo "2) URL 下载" ;;
      OPT_KEY_3)    echo "3) 手动粘贴" ;;
      INPUT_GH)     echo "请输入 GitHub 用户名: " ;;
      INPUT_URL)    echo "请输入公钥 URL: " ;;
      INPUT_RAW)    echo "请粘贴公钥内容 (空行结束输入): " ;;
      ASK_UPD)      echo "是否更新系统软件包? [y/n] (默认 n): " ;;
      ASK_BBR)      echo "是否开启 BBR 加速? [y/n] (默认 n): " ;;
      CONFIRM_T)    echo "---------------- 执行确认 ----------------" ;;
      C_USER)       echo "登录用户: " ;;
      C_PORT)       echo "端口模式: " ;;
      C_KEY)        echo "密钥来源: " ;;
      C_UPD)        echo "系统更新: " ;;
      C_BBR)        echo "开启 BBR: " ;;
      WARN_FW)      echo "⚠ 注意：修改端口前，请确认云厂商防火墙/安全组已放行对应 TCP 端口" ;;
      ASK_SURE)     echo "确认执行? [y/n]: " ;;
      CANCEL)       echo "已取消操作" ;;
      I_INSTALL)    echo "正在安装基础依赖..." ;;
      I_UPD)        echo "正在更新系统..." ;;
      I_BBR)        echo "正在配置 BBR..." ;;
      I_USER)       echo "正在配置用户..." ;;
      I_SSH_INSTALL) echo "未检测到 OpenSSH，正在安装..." ;;
      I_KEY_OK)     echo "公钥部署成功" ;;
      W_KEY_FAIL)   echo "公钥部署失败，将保留密码登录以防失联" ;;
      I_BACKUP)     echo "已全量备份配置 (SSH/User/Firewall): " ;;
      E_SSHD_CHK)   echo "sshd 配置校验失败，正在回滚..." ;;
      E_GREP_FAIL)  echo "配置验证失败：关键参数未生效，正在回滚..." ;;
      W_RESTART)    echo "无法自动重启 SSH 服务，请手动重启" ;;
      W_LISTEN_FAIL) echo "SSHD 已重启但端口未监听，可能启动失败，正在回滚..." ;;
      DONE_T)       echo "================ 完成 ================" ;;
      DONE_MSG1)    echo "请【不要关闭】当前窗口。" ;;
      DONE_MSG2)    echo "请新开一个终端窗口测试登录：" ;;
      DONE_FW)      echo "⚠ 若无法连接，请再次检查防火墙设置" ;;
      AUTO_SKIP)    echo "检测到参数输入，跳过询问: " ;;
      RB_START)     echo "脚本执行出现关键错误，开始自动回滚..." ;;
      RB_DONE)      echo "回滚完成。系统状态已恢复。" ;;
      RB_FAIL)      echo "致命错误：回滚失败！请立即手动检查 /etc/ssh/sshd_config" ;;
      SELINUX_DET)  echo "检测到 SELinux Enforcing 模式，正在配置端口规则..." ;;
      SELINUX_OK)   echo "SELinux 端口规则添加成功" ;;
      SELINUX_FAIL) echo "SELinux 规则添加失败，请手动执行: semanage port -a -t ssh_port_t -p tcp PORT" ;;
      SELINUX_INS)  echo "正在安装 SELinux 管理工具..." ;;
      CLEAN_D)      echo "检测到冲突的配置片段，已备份并移除: " ;;
      TEST_CONN)    echo "正在进行 SSH 连接测试 (IPv4/IPv6/Local)..." ;;
      TEST_OK)      echo "SSH 连接测试通过" ;;
      TEST_FAIL)    echo "SSH 连接测试全部失败！新配置可能无法连接，正在回滚..." ;;
      IPV6_CFG)     echo "检测到全局 IPv6 环境，已添加 :: 监听支持" ;;
      SYS_PROT)     echo "正在添加 systemd 服务防误杀保护..." ;;
      MOTD_UPD)     echo "正在更新登录提示信息 (MotD)..." ;;
      COMPAT_WARN)  echo "检测到旧版 OpenSSH，自动调整配置兼容性..." ;;
      AUDIT_START)  echo "开始执行审计记录..." ;;
      BOX_TITLE)    echo "初始化完成 - 安全配置已生效" ;;
      BOX_SSH)      echo "SSH 连接信息:" ;;
      BOX_KEY_ON)   echo "🔐 密钥认证: 已启用 (密码登录已禁用)" ;;
      BOX_KEY_OFF)  echo "⚠️ 密钥认证: 未启用 (密码登录保持可用)" ;;
      BOX_PORT)     echo "📍 端口变更: 22 → " ;;
      BOX_FW)       echo "⚠️  请确认防火墙已开放 TCP 端口" ;;
      BOX_WARN)     echo "重要: 请在新窗口中测试连接，确认成功后再关闭此窗口！" ;;
      BOX_K8S_WARN) echo "⚠️  注意: 使用了 Kubernetes NodePort 范围端口" ;;
      ERR_MISSING)  echo "❌ 缺少必要命令，无法继续: " ;;
      WARN_DISK)    echo "⚠️  磁盘空间不足: " ;;
      WARN_MEM)     echo "⚠️  可用内存不足: " ;;
      *)            echo "$key" ;;
    esac
  else
    # English Full Support
    case "$key" in
      MUST_ROOT)    echo "Must be run as root" ;;
      BANNER)       echo "Server Init & SSH Hardening (v4.0.0 Platinum)" ;;
      STRICT_ON)    echo "STRICT mode ON: Critical errors will abort" ;;
      ASK_USER)     echo "SSH Login User (root or normal user, default " ;;
      ERR_USER_INV) echo "❌ Invalid username (lowercase/digits/underscore only, no reserved words)" ;;
      ASK_PORT_T)   echo "SSH Port Configuration:" ;;
      OPT_PORT_1)   echo "1) Use 22 (Default)" ;;
      OPT_PORT_2)   echo "2) Random High Port (49152+, avoids K8s)" ;;
      OPT_PORT_3)   echo "3) Manual Input" ;;
      SELECT)       echo "Select [1-3]: " ;;
      INPUT_PORT)   echo "Enter Port (1024-65535): " ;;
      PORT_ERR)     echo "❌ Invalid port (not numeric or out of range)" ;;
      PORT_RES)     echo "❌ Port is reserved (e.g. 80, 443, 3306)" ;;
      PORT_K8S)     echo "⚠️  Warning: Port falls in Kubernetes NodePort range (30000-32767)" ;;
      ASK_KEY_T)    echo "SSH Public Key Source:" ;;
      OPT_KEY_1)    echo "1) GitHub User" ;;
      OPT_KEY_2)    echo "2) URL Download" ;;
      OPT_KEY_3)    echo "3) Manual Paste" ;;
      INPUT_GH)     echo "Enter GitHub Username: " ;;
      INPUT_URL)    echo "Enter Key URL: " ;;
      INPUT_RAW)    echo "Paste Key (Empty line to finish): " ;;
      ASK_UPD)      echo "Update system packages? [y/n] (default n): " ;;
      ASK_BBR)      echo "Enable TCP BBR? [y/n] (default n): " ;;
      CONFIRM_T)    echo "---------------- Confirmation ----------------" ;;
      C_USER)       echo "User: " ;;
      C_PORT)       echo "Port: " ;;
      C_KEY)        echo "Key Source: " ;;
      C_UPD)        echo "Update: " ;;
      C_BBR)        echo "Enable BBR: " ;;
      WARN_FW)      echo "⚠ WARNING: Ensure Cloud Firewall/Security Group allows the new TCP port" ;;
      ASK_SURE)     echo "Proceed? [y/n]: " ;;
      CANCEL)       echo "Cancelled." ;;
      I_INSTALL)    echo "Installing dependencies..." ;;
      I_UPD)        echo "Updating system..." ;;
      I_BBR)        echo "Configuring BBR..." ;;
      I_USER)       echo "Configuring user..." ;;
      I_SSH_INSTALL) echo "OpenSSH not found, installing..." ;;
      I_KEY_OK)     echo "SSH Key deployed successfully" ;;
      W_KEY_FAIL)   echo "Key deployment failed. Password login kept enabled to avoid lockout." ;;
      I_BACKUP)     echo "Full backup created (SSH/User/Firewall): " ;;
      E_SSHD_CHK)   echo "sshd config validation failed, rolling back..." ;;
      E_GREP_FAIL)  echo "Config validation failed: Critical settings not active. Rolling back..." ;;
      W_RESTART)    echo "Could not restart sshd automatically. Please restart manually." ;;
      W_LISTEN_FAIL) echo "SSHD restarted but port is not listening. Rolling back..." ;;
      DONE_T)       echo "================ DONE ================" ;;
      DONE_MSG1)    echo "Please DO NOT close this window yet." ;;
      DONE_MSG2)    echo "Open a NEW terminal to test login:" ;;
      DONE_FW)      echo "⚠ If connection fails, check your Firewall settings." ;;
      AUTO_SKIP)    echo "Argument detected, skipping prompt: " ;;
      RB_START)     echo "Critical error. Starting automatic rollback..." ;;
      RB_DONE)      echo "Rollback complete. System state restored." ;;
      RB_FAIL)      echo "FATAL: Rollback failed! Manually check /etc/ssh/sshd_config" ;;
      SELINUX_DET)  echo "SELinux Enforcing detected. Configuring port rules..." ;;
      SELINUX_OK)   echo "SELinux port rule added successfully." ;;
      SELINUX_FAIL) echo "SELinux rule failed. Manually run: semanage port -a -t ssh_port_t -p tcp PORT" ;;
      SELINUX_INS)  echo "Installing SELinux management tools..." ;;
      CLEAN_D)      echo "Detected conflicting config fragment, backed up and removed: " ;;
      TEST_CONN)    echo "Testing SSH connection (IPv4/IPv6/Local)..." ;;
      TEST_OK)      echo "SSH connection test passed." ;;
      TEST_FAIL)    echo "SSH connection test FAILED! Rolling back..." ;;
      IPV6_CFG)     echo "Global IPv6 detected. Added listen address :: support." ;;
      SYS_PROT)     echo "Adding systemd service protection (anti-kill)..." ;;
      MOTD_UPD)     echo "Updating Message of the Day (MotD)..." ;;
      COMPAT_WARN)  echo "Older OpenSSH detected. Adjusting compatibility settings..." ;;
      AUDIT_START)  echo "Starting audit logging..." ;;
      BOX_TITLE)    echo "Init Complete - Security Applied" ;;
      BOX_SSH)      echo "SSH Connection Info:" ;;
      BOX_KEY_ON)   echo "🔐 Key Auth: ENABLED (Password Disabled)" ;;
      BOX_KEY_OFF)  echo "⚠️ Key Auth: DISABLED (Password Enabled)" ;;
      BOX_PORT)     echo "📍 Port Change: 22 → " ;;
      BOX_FW)       echo "⚠️  Verify Firewall Open for TCP Port" ;;
      BOX_WARN)     echo "IMPORTANT: Test connection in NEW window before closing this one!" ;;
      BOX_K8S_WARN) echo "⚠️  NOTE: Using K8s NodePort range" ;;
      ERR_MISSING)  echo "❌ Missing essential commands: " ;;
      WARN_DISK)    echo "⚠️  Low disk space: " ;;
      WARN_MEM)     echo "⚠️  Low memory: " ;;
      *)            echo "$key" ;;
    esac
  fi
}

# =========================================================
# Core Logic
# =========================================================

# v4.0.0: Preflight Checks (POSIX compatible)
preflight_checks() {
    # Check essential commands
    essential_cmds="cat grep awk sed cp mv chmod chown mkdir rm"
    missing_cmds=""
    
    for cmd in $essential_cmds; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_cmds="$missing_cmds $cmd"
        fi
    done
    
    if [ -n "$missing_cmds" ]; then
        die "$(msg ERR_MISSING)$missing_cmds"
    fi
    
    # Check Disk Space (Need ~5MB)
    available_kb=$(df -k / | awk 'NR==2 {print $4}' 2>/dev/null || echo 99999)
    if [ "$available_kb" -lt 5120 ]; then
        warn "$(msg WARN_DISK)${available_kb}KB"
    fi
    
    # Check Memory (Need ~50MB)
    if [ -f /proc/meminfo ]; then
        mem_avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}' 2>/dev/null || echo 999999)
        if [ "$mem_avail" -lt 51200 ]; then
             warn "$(msg WARN_MEM)${mem_avail}KB"
        fi
    fi
}

# ---------------- Robust Rollback ----------------
# Use secure temp dir for backups too
ROLLBACK_DIR="$TMP_DIR/rollback"
setup_rollback() {
  mkdir -p "$ROLLBACK_DIR"
  
  # 1. Config Backup
  [ -f "$SSH_CONF" ] && cp -p "$SSH_CONF" "$ROLLBACK_DIR/sshd_config"
  if [ -d "$SSH_CONF_D" ]; then
    mkdir -p "$ROLLBACK_DIR/sshd_config.d"
    cp -p "$SSH_CONF_D"/* "$ROLLBACK_DIR/sshd_config.d/" 2>/dev/null || true
  fi

  # 2. User/Shadow Backup
  cp -p /etc/passwd /etc/shadow /etc/group "$ROLLBACK_DIR/" 2>/dev/null || true
  [ -d /etc/sudoers.d ] && cp -rp /etc/sudoers.d "$ROLLBACK_DIR/" 2>/dev/null || true

  # 3. Firewall State Backup
  if command -v iptables-save >/dev/null 2>&1; then
    iptables-save > "$ROLLBACK_DIR/iptables.backup" 2>/dev/null || true
  fi
  
  # Catch signals (Wait for exit code in handler)
  trap 'rollback_handler' INT TERM EXIT HUP
}

# v4.0.0: Persistent Versioned Backup with Metadata
backup_config_persistent() {
  timestamp=$(date +%Y%m%d_%H%M%S)
  mkdir -p "$BACKUP_REPO"
  chmod 700 "$BACKUP_REPO" 2>/dev/null || true

  if [ -f "$SSH_CONF" ]; then
      cp -p "$SSH_CONF" "$BACKUP_REPO/sshd_config.$timestamp"
      chmod 600 "$BACKUP_REPO/sshd_config.$timestamp" 2>/dev/null || true
      
      # Generate Metadata
      cat > "$BACKUP_REPO/sshd_config.$timestamp.meta" <<EOF
Backup-Time: $(date)
SSH-Port: $SSH_PORT
User: $TARGET_USER
Key-Auth: $KEY_OK
Script-Version: 4.0.0
EOF
      chmod 600 "$BACKUP_REPO/sshd_config.$timestamp.meta" 2>/dev/null || true
  fi
  
  # Keep last 10 backups (exclude meta files in count, remove both)
  ls -t "$BACKUP_REPO"/sshd_config.* 2>/dev/null | grep -v '\.meta$' | tail -n +11 | \
    while read -r backup; do
        rm -f "$backup" "${backup}.meta" 2>/dev/null || true
    done
}

rollback_handler() {
  RET=$? # Capture exit code immediately
  trap - INT TERM EXIT HUP # Disable trap
  
  # Only rollback on error (RET != 0)
  if [ "$RET" -ne 0 ]; then
    warn ""
    warn "$(msg RB_START)"
    
    # Restore SSH Config
    if [ -f "$ROLLBACK_DIR/sshd_config" ]; then
      cp -p "$ROLLBACK_DIR/sshd_config" "$SSH_CONF"
      chmod 600 "$SSH_CONF"
    fi
    
    # Restore .d configs
    if [ -d "$ROLLBACK_DIR/sshd_config.d" ]; then
      cp -p "$ROLLBACK_DIR/sshd_config.d"/* "$SSH_CONF_D/" 2>/dev/null || true
    fi

    # Attempt restart to restore service
    restart_sshd >/dev/null 2>&1
    
    warn "$(msg RB_DONE)"
    audit_log "ROLLBACK" "System rolled back due to error code $RET"
  else
    # Success cleanup - Remove the whole temp dir
    rm -rf "$TMP_DIR"
  fi
  
  exit "$RET"
}

[ "$(id -u)" -eq 0 ] || { echo "$(msg MUST_ROOT)"; exit 1; }
audit_log "START" "Script started with args: $*"

# ---------------- Package Manager ----------------
detect_pm() {
  [ -f /etc/alpine-release ] && { echo apk; return; }
  [ -f /etc/debian_version ] && { echo apt; return; }
  [ -f /etc/redhat-release ] && { echo yum; return; }
  echo unknown
}
PM="$(detect_pm)"
APT_UPDATED="n"
APK_UPDATED="n"
YUM_PREPARED="n"

pm_prepare_once() {
  case "$PM" in
    apt) [ "$APT_UPDATED" != "y" ] && { apt-get update -y >>"$LOG_FILE" 2>&1; APT_UPDATED="y"; } ;;
    apk) [ "$APK_UPDATED" != "y" ] && { apk update >>"$LOG_FILE" 2>&1 || true; APK_UPDATED="y"; } ;;
    yum) [ "$YUM_PREPARED" != "y" ] && { 
         if command -v dnf >/dev/null 2>&1; then dnf makecache -y >>"$LOG_FILE" 2>&1;
         else yum makecache -y >>"$LOG_FILE" 2>&1; fi
         YUM_PREPARED="y"; } ;;
  esac
}

install_pkg() {
  case "$PM" in
    apt) pm_prepare_once; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >>"$LOG_FILE" 2>&1 ;;
    yum) pm_prepare_once; 
         if command -v dnf >/dev/null 2>&1; then dnf install -y "$@" >>"$LOG_FILE" 2>&1;
         else yum install -y "$@" >>"$LOG_FILE" 2>&1; fi ;;
    apk) pm_prepare_once; apk add --no-cache "$@" >>"$LOG_FILE" 2>&1 ;;
  esac
}

install_pkg_try() {
  for p in "$@"; do
    if install_pkg "$p" >/dev/null 2>&1; then return 0; fi
  done
  return 1
}

# ---------------- System Update ----------------
update_system() {
  case "$PM" in
    apt) pm_prepare_once; DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >>"$LOG_FILE" 2>&1 ;;
    yum) pm_prepare_once; 
         if command -v dnf >/dev/null 2>&1; then dnf upgrade -y >>"$LOG_FILE" 2>&1;
         else yum update -y >>"$LOG_FILE" 2>&1; fi ;;
    apk) pm_prepare_once; apk upgrade >>"$LOG_FILE" 2>&1 ;;
  esac
}

# ---------------- BBR ----------------
enable_bbr() {
  command -v sysctl >/dev/null 2>&1 || return
  if ! sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
    warn "Kernel does not support BBR, skipping."
    return
  fi
  sysctl_conf="/etc/sysctl.conf"
  grep -q '^net.core.default_qdisc=fq$' "$sysctl_conf" 2>/dev/null || echo 'net.core.default_qdisc=fq' >>"$sysctl_conf"
  grep -q '^net.ipv4.tcp_congestion_control=bbr$' "$sysctl_conf" 2>/dev/null || echo 'net.ipv4.tcp_congestion_control=bbr' >>"$sysctl_conf"
  sysctl -p >>"$LOG_FILE" 2>&1 || true
}

# ---------------- SSHD Helpers ----------------
ensure_ssh_server() {
  [ -f "$SSH_CONF" ] && return 0
  info "$(msg I_SSH_INSTALL)"
  case "$PM" in
    apk) install_pkg openssh ;;
    *)   install_pkg openssh-server ;;
  esac
  [ -f "$SSH_CONF" ] || die "OpenSSH Install Failed"
}

protect_sshd_service() {
  if command -v systemctl >/dev/null 2>&1; then
    info "$(msg SYS_PROT)"
    systemctl enable ssh sshd 2>/dev/null || true
    systemctl unmask ssh sshd 2>/dev/null || true
    
    mkdir -p /etc/systemd/system/sshd.service.d/ 2>/dev/null || true
    cat > /etc/systemd/system/sshd.service.d/override.conf <<EOF
[Service]
Restart=on-failure
RestartSec=5s
OOMScoreAdjust=-500
EOF
    systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  fi
}

restart_sshd() {
  if [ "$ARG_DELAY_RESTART" = "y" ]; then
     warn "DELAY RESTART: Please manually restart sshd later."
     return 0
  fi

  local res=1
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd >>"$LOG_FILE" 2>&1 || systemctl restart ssh >>"$LOG_FILE" 2>&1
    res=$?
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sshd restart >>"$LOG_FILE" 2>&1
    res=$?
  elif command -v service >/dev/null 2>&1; then
    service sshd restart >>"$LOG_FILE" 2>&1 || service ssh restart >>"$LOG_FILE" 2>&1
    res=$?
  else
    [ -x /etc/init.d/sshd ] && /etc/init.d/sshd restart >>"$LOG_FILE" 2>&1 && res=0
    [ -x /etc/init.d/ssh ]  && /etc/init.d/ssh  restart >>"$LOG_FILE" 2>&1 && res=0
  fi

  if [ "$res" -ne 0 ]; then
     if [ "$STRICT_MODE" = "y" ]; then
        die "SSHD Restart Failed (Exit Code: $res)"
     else
        return 1
     fi
  fi
  return 0
}

verify_sshd_listening() {
  local port="$1"
  local timeout=10
  local elapsed=0
  
  ensure_port_tools
  
  while [ $elapsed -lt $timeout ]; do
    if ! is_port_free "$port"; then
       # Port is occupied, which means SSHD (or something) is up
       return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

# v4.0.0: Robust Connection Testing with Fallback
test_ssh_connection() {
  port="$1"
  user="$2"
  info "$(msg TEST_CONN)"
  
  sleep 2
  
  # Try to install clients if missing
  if ! command -v ssh >/dev/null 2>&1; then
    install_pkg_try openssh-clients openssh-client >/dev/null 2>&1 || true
  fi

  # Determine IPv6 capability for testing
  local targets="127.0.0.1 localhost"
  if has_global_ipv6; then targets="$targets ::1"; fi

  # METHOD 1: SSH Client
  if command -v ssh >/dev/null 2>&1; then
    for target in $targets; do
      if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p "$port" "$user"@"$target" "echo ok" >/dev/null 2>&1; then
        ok "$(msg TEST_OK) ($target via SSH)"
        return 0
      fi
    done
  fi

  # METHOD 2: Netcat (Fallback if keyauth fails or client missing)
  if command -v nc >/dev/null 2>&1; then
     # Use first target for port check
     if nc -z -w 5 127.0.0.1 "$port" 2>/dev/null; then
        ok "SSH port $port is open (verified via Netcat)"
        return 0
     fi
  fi

  err "$(msg TEST_FAIL)"
  return 1
}

# ---------------- Firewall & SELinux ----------------
allow_firewall_port() {
  p="$1"
  # IPv4
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${p}/tcp" >>"$LOG_FILE" 2>&1 || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${p}/tcp" >>"$LOG_FILE" 2>&1 || true
    firewall-cmd --reload >>"$LOG_FILE" 2>&1 || true
  elif command -v iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>>"$LOG_FILE" || true
  fi
  
  # IPv6
  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>>"$LOG_FILE" || true
  fi
}

handle_selinux() {
  port="$1"
  if command -v getenforce >/dev/null 2>&1; then
    if getenforce | grep -qi "Enforcing"; then
       info "$(msg SELINUX_DET)"
       
       if ! command -v semanage >/dev/null 2>&1; then
         info "$(msg SELINUX_INS)"
         case "$PM" in
           yum) install_pkg_try policycoreutils-python-utils policycoreutils-python ;;
           apt) install_pkg_try policycoreutils python3-policycoreutils ;;
         esac
       fi

       if command -v semanage >/dev/null 2>&1; then
         if semanage port -a -t ssh_port_t -p tcp "$port" >>"$LOG_FILE" 2>&1 || \
            semanage port -m -t ssh_port_t -p tcp "$port" >>"$LOG_FILE" 2>&1; then
            ok "$(msg SELINUX_OK)"
         else
            warn "$(msg SELINUX_FAIL)"
         fi
       else
         warn "$(msg SELINUX_FAIL)"
       fi
    fi
  fi
}

# ---------------- Port Logic ----------------
is_hard_reserved() {
  case "$1" in
    80|443|3306|5432|6379|8080|8443|21|23|25|110|143) return 0 ;;
  esac
  return 1
}

is_k8s_nodeport() {
  [ "$1" -ge 30000 ] && [ "$1" -le 32767 ]
}

rand_u16() {
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' '
  elif command -v shuf >/dev/null 2>&1; then
    shuf -i 1024-65535 -n 1
  else
    echo $(( ( $(date +%s 2>/dev/null || echo 12345) + $$ ) % 65536 ))
  fi
}

ensure_port_tools() {
  command -v ss >/dev/null 2>&1 && return 0
  command -v netstat >/dev/null 2>&1 && return 0
  case "$PM" in
    apt) install_pkg_try iproute2 >/dev/null 2>&1 || true ;;
    yum) install_pkg_try iproute  >/dev/null 2>&1 || true ;;
    apk) install_pkg_try iproute2 iproute2-ss >/dev/null 2>&1 || true ;;
  esac
  install_pkg_try net-tools >/dev/null 2>&1 || true
}

is_port_free() {
  p="$1"
  if command -v ss >/dev/null 2>&1; then
    # Reliable parsing for IPv4 (0.0.0.0:22) and IPv6 ([::]:22)
    if ss -lnt 2>/dev/null | awk -v port="$p" '
      {
        n = split($4, parts, ":")
        last = parts[n]
        if (last == port) { found=1; exit }
      }
      END { exit !found }
    '; then
       return 1 # Found (Occupied)
    else
       return 0 # Free
    fi
  fi
  # Fallback
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -q ":$p$" && return 1 || return 0
  fi
  return 1 # Conservative fail
}

pick_random_port() {
  ensure_port_tools
  i=0
  while [ $i -lt 100 ]; do
    r="$(rand_u16)"
    # Logic: 49152 + (0 to 16383) = 49152 to 65535.
    # This range is strictly above K8s NodePort (30000-32767).
    p=$(( 49152 + (r % (65535 - 49152)) ))
    
    if is_port_free "$p"; then echo "$p"; return 0; fi
    i=$((i+1))
  done
  return 1
}

# ---------------- User & Key ----------------
validate_username() {
    u="$1"
    # Length 2-32
    len=${#u}
    if [ "$len" -lt 2 ] || [ "$len" -gt 32 ]; then return 1; fi
    # Regex: Lowercase, digits, underscore, dash. Must start with letter/underscore.
    echo "$u" | grep -Eq '^[a-z_][a-z0-9_-]*$' || return 1
    # Reserved words
    case "$u" in
        root|bin|daemon|adm|lp|sync|shutdown|halt|mail|operator|games|ftp|nobody) return 1 ;;
    esac
    return 0
}

ensure_user() {
  u="$1"
  [ "$u" = "root" ] && return 0
  id "$u" >/dev/null 2>&1 && return 0

  info "$(msg I_USER) $u"
  install_pkg_try bash sudo >/dev/null 2>&1 || true
  shell="/bin/sh"
  [ -x /bin/bash ] && shell="/bin/bash"

  if command -v useradd >/dev/null 2>&1; then
    useradd -m -s "$shell" "$u"
  else
    adduser -D -s "$shell" "$u"
  fi

  if [ -d /etc/sudoers.d ]; then
    echo "$u ALL=(ALL) NOPASSWD:ALL" >"/etc/sudoers.d/$u" 2>/dev/null || true
    chmod 440 "/etc/sudoers.d/$u" 2>/dev/null || true
  fi
}

fetch_keys() {
  local url=""
  case "$1" in
    gh)  url="https://github.com/$2.keys" ;;
    url) url="$2" ;;
    raw) printf "%s\n" "$2"; return ;;
  esac

  local max_retries=3
  local retry=0

  while [ $retry -lt $max_retries ]; do
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL --connect-timeout 10 --max-time 30 "$url" 2>>"$LOG_FILE"; then
         return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -qO- --timeout=30 "$url" 2>>"$LOG_FILE"; then
         return 0
      fi
    else
      warn "Need curl or wget to fetch keys"
      return 1
    fi
    retry=$((retry + 1))
    [ $retry -lt $max_retries ] && sleep 2
  done
  
  warn "Failed to fetch keys after $max_retries attempts"
  return 1
}

deploy_keys() {
  user="$1"
  keys="$2"
  home="$(eval echo "~$user")"
  dir="$home/.ssh"
  auth="$dir/authorized_keys"

  mkdir -p "$dir"
  chmod 700 "$dir"
  touch "$auth"
  chmod 600 "$auth"
  chown -R "$user:" "$dir" 2>/dev/null || true

  printf "%s\n" "$keys" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | grep -Eq '^(ssh-(rsa|ed25519|dss)|ecdsa-|sk-)' || continue
    grep -qxF "$line" "$auth" || echo "$line" >>"$auth"
  done
  grep -Eq '^(ssh-|ecdsa-|sk-)' "$auth"
}

# ---------------- Config Management ----------------
cleanup_sshd_config_d() {
  if [ -d "$SSH_CONF_D" ]; then
    for conf in "$SSH_CONF_D"/*.conf; do
      [ -f "$conf" ] || continue
      if grep -Eq '^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication)' "$conf"; then
        mv "$conf" "${conf}.bak_server_init"
        warn "$(msg CLEAN_D) $conf"
      fi
    done
  fi
}

remove_managed_block() {
  tmp="$TMP_DIR/sshd_config.tmp"
  cp -p "$SSH_CONF" "$tmp"
  
  awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    skip!=1 {print}
  ' "$SSH_CONF" >"$tmp"
  
  cat "$tmp" > "$SSH_CONF"
  rm -f "$tmp"
}

# v4.0.0: Robust Triple-Check IPv6
has_global_ipv6() {
    # Method 1: Proc file (Common Linux)
    if [ -f /proc/net/if_inet6 ]; then
        if grep -v '^fe80::' /proc/net/if_inet6 2>/dev/null | grep -q '^[0-9a-f]'; then
            return 0
        fi
    fi
    
    # Method 2: ip command
    if command -v ip >/dev/null 2>&1; then
        if ip -6 addr show scope global 2>/dev/null | grep -q inet6; then
            return 0
        fi
    fi
    
    # Method 3: ifconfig (Legacy/BSD-like)
    if command -v ifconfig >/dev/null 2>&1; then
        if ifconfig 2>/dev/null | grep -i 'inet6.*global' >/dev/null; then
            return 0
        fi
    fi
    return 1
}

build_block() {
  file="$1"
  {
    echo "$BLOCK_BEGIN"
    echo "# Managed by server-init v4.0.0"
    echo "# Generated: $(date)"
    echo "# Do NOT edit inside this block. Changes will be overwritten."
    echo ""
    echo "Port $SSH_PORT"
    
    echo "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256"
    echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com"
    echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com"

    # Smart IPv6 Check
    if has_global_ipv6; then
       echo "AddressFamily any"
       echo "ListenAddress ::"
       echo "ListenAddress 0.0.0.0"
       info "$(msg IPV6_CFG)"
    else
       echo "AddressFamily inet"
       echo "ListenAddress 0.0.0.0"
    fi

    if [ "$KEY_OK" = "y" ]; then
      echo "PasswordAuthentication no"
      echo "ChallengeResponseAuthentication no"
      echo "PubkeyAuthentication yes"
    fi

    if [ "$TARGET_USER" = "root" ]; then
      if [ "$KEY_OK" = "y" ]; then
        if sshd -V 2>&1 | grep -q "OpenSSH_[1-6]"; then
           echo "PermitRootLogin without-password"
           warn "$(msg COMPAT_WARN)"
        else
           echo "PermitRootLogin prohibit-password"
        fi
      else
        echo "PermitRootLogin yes"
      fi
    else
      echo "PermitRootLogin no"
    fi

    echo ""
    echo "$BLOCK_END"
    echo ""
  } >"$file"
}

insert_block_at_top() {
  block="$1"
  tmp="$TMP_DIR/sshd_config.merge"
  cat "$block" "$SSH_CONF" >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$SSH_CONF"
}

update_motd() {
  info "$(msg MOTD_UPD)"
  motd="/etc/motd"
  tmp="$TMP_DIR/motd.new"
  
  if [ -f "$motd" ]; then
      grep -v "Server Init Complete" "$motd" > "$tmp" 2>/dev/null || true
  fi

  {
    echo "==============================================================================="
    echo "                      Server Init Complete - SSH Hardened"
    echo "==============================================================================="
    echo " Login User: $TARGET_USER"
    echo " SSH Port:   $SSH_PORT"
    echo " Auth Type:  $([ "$KEY_OK" = "y" ] && echo "Key Only" || echo "Password")"
    echo " Firewall:   Please ensure TCP/$SSH_PORT is allowed."
    echo "==============================================================================="
    echo ""
    [ -s "$tmp" ] && cat "$tmp"
  } > "${motd}.final"
  
  mv "${motd}.final" "$motd"
}

# v4.0.0: Final Health Report
generate_health_report() {
    report_file="/var/log/server-init-health.log"
    # Calculate Duration
    end_time=$(date +%s)
    duration=$((end_time - SCRIPT_START_TIME))
    
    {
      echo "=== Server Init Health Report ==="
      echo "Generated: $(date)"
      echo "Version: v4.0.0 Platinum"
      echo "Execution Time: ${duration}s"
      echo ""
      echo "--- SSH Config ---"
      echo "Port: $SSH_PORT"
      echo "User: $TARGET_USER"
      echo "KeyAuth: $([ "$KEY_OK" = "y" ] && echo "YES" || echo "NO")"
      echo ""
      echo "--- Network ---"
      echo "Public IP: ${public_ip:-unknown}"
      echo "IPv6: $(has_global_ipv6 && echo "Enabled" || echo "Disabled")"
      echo "Port Listening: $(is_port_free "$SSH_PORT" && echo "NO (Error)" || echo "YES")"
    } > "$report_file"
    
    chmod 600 "$report_file"
    info "Health report saved to: $report_file"
}

print_final_summary() {
  
  # Try to detect public IP
  public_ip=""
  if command -v curl >/dev/null 2>&1; then
    public_ip=$(curl -4fsSL --max-time 2 https://api.ipify.org 2>/dev/null || echo "")
  fi
  local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
  
  end_time=$(date +%s)
  duration=$((end_time - SCRIPT_START_TIME))

  echo ""
  echo "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
  printf "${CYAN}║ %-66s ║${NC}\n" "$(msg BOX_TITLE)"
  echo "${CYAN}╠════════════════════════════════════════════════════════════════════╣${NC}"
  printf "${CYAN}║ %-66s ║${NC}\n" " $(msg BOX_SSH)"
  
  if [ -n "$public_ip" ]; then
     printf "${CYAN}║     Public: ssh -p %-5s %s@%s %-16s ║${NC}\n" "$SSH_PORT" "$TARGET_USER" "$public_ip" ""
  fi
  if [ -n "$local_ip" ]; then
     printf "${CYAN}║     Local:  ssh -p %-5s %s@%s %-16s ║${NC}\n" "$SSH_PORT" "$TARGET_USER" "$local_ip" ""
  fi

  echo "${CYAN}║                                                                    ║${NC}"
  
  if [ "$KEY_OK" = "y" ]; then
    printf "${CYAN}║ %-66s ║${NC}\n" " $(msg BOX_KEY_ON)"
  else
    printf "${CYAN}║ %-66s ║${NC}\n" " $(msg BOX_KEY_OFF)"
  fi
  
  if [ "$SSH_PORT" != "22" ]; then
    printf "${CYAN}║ %-66s ║${NC}\n" " $(msg BOX_PORT)$SSH_PORT"
    printf "${CYAN}║ %-66s ║${NC}\n" " $(msg BOX_FW)"
    if is_k8s_nodeport "$SSH_PORT"; then
       printf "${CYAN}║ %-66s ║${NC}\n" " $(msg BOX_K8S_WARN)"
    fi
  fi
  
  echo "${CYAN}║                                                                    ║${NC}"
  printf "${CYAN}║ %-66s ║${NC}\n" " $(msg BOX_WARN)"
  echo "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "Log: $LOG_FILE"
  echo "Time: ${duration}s"
}

# =========================================================
# Phase 1: Input
# =========================================================
clear
echo "================================================="
msg BANNER
echo "================================================="
[ "$STRICT_MODE" = "y" ] && msg STRICT_ON

# Preflight Checks
preflight_checks

# 1. User
if [ -n "$ARG_USER" ]; then
  TARGET_USER="$ARG_USER"
  # Validating argument user
  validate_username "$TARGET_USER" || die "$(msg ERR_USER_INV): $TARGET_USER"
  printf "%s%s\n" "$(msg AUTO_SKIP)" "$TARGET_USER"
else
  while :; do
      printf "%s%s): " "$(msg ASK_USER)" "$DEFAULT_USER"
      read TARGET_USER
      [ -z "$TARGET_USER" ] && TARGET_USER="$DEFAULT_USER"
      if validate_username "$TARGET_USER"; then
         break
      else
         msg ERR_USER_INV
      fi
  done
fi

# 2. Port
if [ -n "$ARG_PORT" ]; then
  case "$ARG_PORT" in
    22)     PORT_OPT="1"; SSH_PORT="22" ;;
    random) PORT_OPT="2"; SSH_PORT="22" ;; 
    *)      PORT_OPT="3"; SSH_PORT="$ARG_PORT" ;;
  esac
  printf "%s%s\n" "$(msg AUTO_SKIP)" "$ARG_PORT (Mode $PORT_OPT)"
else
  echo ""
  msg ASK_PORT_T
  msg OPT_PORT_1
  msg OPT_PORT_2
  msg OPT_PORT_3
  printf "%s" "$(msg SELECT)"
  read PORT_OPT
  [ -z "$PORT_OPT" ] && PORT_OPT="1"

  SSH_PORT="22"
  if [ "$PORT_OPT" = "3" ]; then
    while :; do
      printf "%s" "$(msg INPUT_PORT)"
      read MANUAL_PORT
      echo "$MANUAL_PORT" | grep -Eq '^[0-9]+$' || { msg PORT_ERR; continue; }
      [ "$MANUAL_PORT" -ge 1024 ] 2>/dev/null && [ "$MANUAL_PORT" -le 65535 ] 2>/dev/null || { msg PORT_ERR; continue; }
      
      if is_hard_reserved "$MANUAL_PORT"; then
         msg PORT_RES
         continue
      elif is_k8s_nodeport "$MANUAL_PORT"; then
         msg PORT_K8S
         printf "%s" "$(msg ASK_SURE)"
         read force_port
         [ "${force_port:-n}" = "y" ] || continue
      fi
      
      SSH_PORT="$MANUAL_PORT"
      break
    done
  fi
fi

# 3. Key
if [ -n "$ARG_KEY_TYPE" ]; then
  KEY_OPT="auto"
  KEY_TYPE="$ARG_KEY_TYPE"
  KEY_VAL="$ARG_KEY_VAL"
  printf "%s%s\n" "$(msg AUTO_SKIP)" "$KEY_TYPE ($KEY_VAL)"
else
  echo ""
  msg ASK_KEY_T
  msg OPT_KEY_1
  msg OPT_KEY_2
  msg OPT_KEY_3
  printf "%s" "$(msg SELECT)"
  read KEY_OPT

  case "$KEY_OPT" in
    1) KEY_TYPE="gh";  printf "%s" "$(msg INPUT_GH)"; read KEY_VAL ;;
    2) KEY_TYPE="url"; printf "%s" "$(msg INPUT_URL)"; read KEY_VAL ;;
    3)
        KEY_TYPE="raw"
        msg INPUT_RAW
        raw=""
        while IFS= read -r l; do
          [ -z "$l" ] && break
          raw="${raw}${l}\n"
        done
        KEY_VAL="$(printf "%b" "$raw")"
        ;;
    *) die "Invalid Option" ;;
  esac
fi

# 4. Update
if [ -n "$ARG_UPDATE" ]; then
  DO_UPDATE="$ARG_UPDATE"
  printf "%s%s\n" "$(msg AUTO_SKIP)" "Update=$DO_UPDATE"
else
  printf "%s" "$(msg ASK_UPD)"
  read DO_UPDATE
  [ -z "$DO_UPDATE" ] && DO_UPDATE="n"
fi

# 5. BBR
if [ -n "$ARG_BBR" ]; then
  DO_BBR="$ARG_BBR"
  printf "%s%s\n" "$(msg AUTO_SKIP)" "BBR=$DO_BBR"
else
  printf "%s" "$(msg ASK_BBR)"
  read DO_BBR
  [ -z "$DO_BBR" ] && DO_BBR="n"
fi

# =========================================================
# Phase 2: Confirm
# =========================================================
if [ "$AUTO_CONFIRM" = "y" ]; then
  echo ""
  info "Auto-Confirm: Skipping interactive confirmation."
else
  echo ""
  msg CONFIRM_T
  echo "$(msg C_USER)$TARGET_USER"
  echo "$(msg C_PORT)$SSH_PORT (Mode: $PORT_OPT)"
  echo "$(msg C_KEY)$KEY_TYPE"
  echo "$(msg C_UPD)$DO_UPDATE"
  echo "$(msg C_BBR)$DO_BBR"
  [ "$PORT_OPT" != "1" ] && msg WARN_FW

  printf "%s" "$(msg ASK_SURE)"
  read CONFIRM
  [ "${CONFIRM:-n}" = "y" ] || die "$(msg CANCEL)"
fi

# =========================================================
# Phase 3: Execute (With Enhanced Rollback)
# =========================================================
msg AUDIT_START
setup_rollback
backup_config_persistent

info "$(msg I_INSTALL)"
ensure_ssh_server
install_pkg_try curl >/dev/null 2>&1 || true # Soft check, fetch_keys handles fail
install_pkg_try wget >/dev/null 2>&1 || true

# Updates & BBR
if [ "$DO_UPDATE" = "y" ]; then
  info "$(msg I_UPD)"
  update_system
fi

if [ "$DO_BBR" = "y" ]; then
  info "$(msg I_BBR)"
  enable_bbr
fi

# Random Port Calculation
if [ "$PORT_OPT" = "2" ]; then
  p="$(pick_random_port || true)"
  if [ -n "$p" ]; then
    SSH_PORT="$p"
    info "Random Port: $SSH_PORT"
  else
    [ "$STRICT_MODE" = "y" ] && die "STRICT: Random port failed"
    warn "Random port failed, fallback to 22"
    SSH_PORT="22"
  fi
fi

# Firewall & SELinux
if [ "$SSH_PORT" != "22" ]; then
  allow_firewall_port "$SSH_PORT"
  handle_selinux "$SSH_PORT"
fi

# User ensure
ensure_user "$TARGET_USER"

# Key Deploy
KEY_OK="n"
KEY_DATA="$(fetch_keys "$KEY_TYPE" "$KEY_VAL")"
if [ -n "$KEY_DATA" ] && deploy_keys "$TARGET_USER" "$KEY_DATA"; then
  KEY_OK="y"
  info "$(msg I_KEY_OK)"
else
  [ "$STRICT_MODE" = "y" ] && die "STRICT: Key deploy failed"
  warn "$(msg W_KEY_FAIL)"
fi

# SSH Config Manipulation
info "$(msg I_BACKUP)$SSH_CONF"
cleanup_sshd_config_d
remove_managed_block

tmp="$TMP_DIR/sshd_block_final"
build_block "$tmp"
insert_block_at_top "$tmp"

# Optimized: Apply Systemd protection once
if [ "$ARG_DELAY_RESTART" != "y" ]; then
   protect_sshd_service
fi

# Validation 1: Syntax
if ! sshd -t -f "$SSH_CONF" 2>>"$LOG_FILE"; then
  die "$(msg E_SSHD_CHK)"
fi

# Restart
if ! restart_sshd; then
  warn "$(msg W_RESTART)"
fi

# Validation 2: Verification (Grep)
if ! grep -q "^Port $SSH_PORT" "$SSH_CONF"; then
    die "$(msg E_GREP_FAIL)"
fi

# Validation 3: Active Listening (Network)
if ! verify_sshd_listening "$SSH_PORT"; then
    die "$(msg W_LISTEN_FAIL)"
fi

# Self-Test Connection (Check BEFORE removing trap)
if ! test_ssh_connection "$SSH_PORT" "$TARGET_USER"; then
  die "$(msg TEST_FAIL)"
fi

# MotD Update
update_motd
generate_health_report

# Only remove trap if EVERYTHING passed
trap - INT TERM EXIT HUP
rm -rf "$TMP_DIR"

# =========================================================
# Done
# =========================================================
print_final_summary
