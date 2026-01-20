# Linux 服务器初始化与 SSH 安全加固

[![Test Matrix](https://github.com/247like/linux-ssh-init-sh/actions/workflows/test.yml/badge.svg)](https://github.com/247like/linux-ssh-init-sh/actions/workflows/test.yml)
![POSIX Shell](https://img.shields.io/badge/Shell-POSIX_sh-blue?style=flat-square)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/247like/linux-ssh-init-sh?style=flat-square)](https://github.com/247like/linux-ssh-init-sh/releases)
[![Stars](https://img.shields.io/github/stars/247like/linux-ssh-init-sh?style=flat-square)](https://github.com/247like/linux-ssh-init-sh/stargazers)

[![中文文档](https://img.shields.io/badge/中文-Chinese-blue)](README.md) [![English](https://img.shields.io/badge/English-EN-blue)](README_EN.md)

---

一个生产就绪、符合 POSIX 标准的 Shell 脚本，用于 Linux 服务器的一键初始化与 SSH 安全加固。

该脚本可自动完成 **SSH 密钥配置**、**修改端口**、**创建用户**、**开启 BBR** 以及 **系统更新**，并完美兼容 Debian, Ubuntu, CentOS, RHEL 以及 Alpine Linux。

### ✨ 核心特性

* **全平台兼容**: 完美支持 **Debian**, **Ubuntu**, **CentOS/RHEL**, **Alma/Rocky**, 以及 **Alpine Linux**。
* **POSIX 标准**: 纯 `/bin/sh` 编写，无需安装 `bash`。在 `dash` (Debian) 和 `ash` (Alpine/Busybox) 上稳定运行。
* **安全架构 (Fortress Pro)**:
    * **托管配置块**: 使用 `# BEGIN SERVER-INIT MANAGED BLOCK` 头部插入配置，确保优先级最高，不受 `Include` 指令干扰。
    * **自动回滚 (Auto-Rollback)**: 运行时若发生 SSHD 校验失败、端口未监听或连接测试失败，自动还原系统状态。
    * **进程防杀 (Anti-Kill)**: 为 SSHD 服务添加 systemd `override.conf`，防止 OOM 误杀并配置自动重启。
    * **防失联死锁检测**: 智能检测认证方式，防止出现“既禁用密码又未配好密钥”的死锁。
* **自动化友好**:
    * 支持 **无头模式 (Headless)**，通过命令行参数实现零交互无人值守安装。
    * **审计与报告**: 自动生成详细的操作审计日志与系统健康检查报告。

### 🚀 快速开始

请以 **root** 身份运行。

#### 1. 交互式运行 (推荐)
```bash
curl -fsSL https://raw.githubusercontent.com/jet3918/linux-ssh-init-sh/main/init.sh -o init.sh && chmod +x init.sh && ./init.sh
```

#### 2. 强制使用英文界面
```bash
./init.sh --lang=en
```

### 🤖 自动化部署 (无头模式)

适用于 CI/CD 或批量装机场景。使用命令行参数传递配置，配合 `--yes` 跳过确认。

#### 全自动运行示例
*(配置 Root 用户、随机端口、从 GitHub 拉取公钥、开启 BBR、更新系统、自动确认)*

```bash
curl -fsSL https://raw.githubusercontent.com/jet3918/linux-ssh-init-sh/main/init.sh | sh -s -- \
    --user=root \
    --port=random \
    --key-gh=jet3918 \
    --bbr \
    --update \
    --strict \
    --yes
```

#### 半自动示例
*(指定公钥来源，其他选项手动选择)*

```bash
./init.sh --key-url=https://my-server.com/id_ed25519.pub
```

### ⚙️ 参数详解

脚本支持丰富的命令行参数来控制行为：

| 参数类别 | 参数 | 说明 |
| :--- | :--- | :--- |
| **基础控制** | `--lang=en` | 强制使用英文界面 |
| | `--yes` | **自动确认**：跳过脚本最后的 "确认执行?" 询问 |
| | `--strict` | **严格模式**：遇到任何错误立即退出 (详见下方) |
| | `--delay-restart` | **延迟重启**：修改配置但不重启 SSH 服务 (适用于特殊环境) |
| **用户与端口** | `--user=root` | 指定登录用户 (root 或普通用户名) |
| | `--port=22` | 保持默认 22 端口 |
| | `--port=random` | 生成随机高位端口 (49152-65535) |
| | `--port=2222` | 指定具体端口号 |
| **密钥来源** | `--key-gh=username` | 从 GitHub 用户拉取公钥 |
| | `--key-url=url` | 从指定 URL 下载公钥 |
| | `--key-raw="ssh-..."` | 直接传递公钥内容字符串 |
| **系统选项** | `--update` | 开启系统软件包更新 |
| | `--no-update` | 跳过系统更新 |
| | `--bbr` | 开启 TCP BBR 拥塞控制 |
| | `--no-bbr` | 不开启 BBR |

### ⚙️ 普通模式 vs 严格模式

| 场景 | 普通模式 (默认) | 严格模式 (`--strict`) |
| :--- | :--- | :--- |
| **设计理念** | **"优先保命"** (尽力而为) | **"优先合规"** (零容忍) |
| **公钥失败** | 若下载失败，脚本**保留密码登录**并警告。<br>👉 *结果：服务器不安全，但能登录修补。* | 脚本**立即报错退出**，不修改任何配置。<br>👉 *结果：部署中断，保持原样。* |
| **端口失败** | 若随机端口失败，回退使用 **端口 22**。 | 脚本**立即报错退出**。 |

### 📂 日志与审计

脚本执行后会生成以下重要文件，用于排查问题或审计合规：

* **运行日志**: `/var/log/server-init.log` (包含详细的 debug 信息)
* **审计日志**: `/var/log/server-init-audit.log` (记录关键操作 Action、时间戳及操作人)
* **健康报告**: `/var/log/server-init-health.log` (最终的系统配置状态快照)

### 🆘 灾难恢复与配置还原

脚本拥有两层安全机制：**运行时自动回滚** 和 **持久化备份恢复**。

如果在脚本执行完成后（显示 "DONE" 后）您无法连接服务器，请通过云服务商的 VNC / Console 控制台登录，并使用以下方法恢复。

#### 方法 A：使用一键恢复脚本 (推荐)

脚本在修改前会自动创建备份，并生成恢复脚本。

1.  找到最近的备份目录：
    ```bash
    ls -ld /var/backups/ssh-config/*
    ```
2.  进入目录并运行恢复脚本：
    ```bash
    # 进入最新的备份目录 (例如 20250520_120000)
    cd /var/backups/ssh-config/<TIMESTAMP>/
    
    # 执行恢复
    sh restore.sh
    ```
    *该脚本会自动覆盖 sshd_config 并尝试重启 SSH 服务。*

#### 方法 B：手动恢复

如果无法运行脚本，可手动复制文件：

```bash
# 1. 覆盖配置文件
cp /var/backups/ssh-config/<TIMESTAMP>/sshd_config /etc/ssh/sshd_config

# 2. 重启服务
systemctl restart sshd || service sshd restart
```

---

### ⚠️ 免责声明

本脚本会修改核心系统配置（SSH）。虽然脚本内置了多重安全检查和回滚机制，但请务必确保你拥有服务器的备用访问方式（如 VNC 控制台），以防网络波动或配置意外导致的连接中断。

### 📄 开源协议

本项目采用 [MIT License](LICENSE) 开源。

---

<div align="center">

如果您觉得这个工具好用，请给一颗 ⭐ 星！

[报告问题](https://github.com/247like/linux-ssh-init-sh/issues) · [功能建议](https://github.com/247like/linux-ssh-init-sh/issues)

</div>
