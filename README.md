# Kairo

![Version](https://img.shields.io/badge/version-1.2.11-blue) ![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnome-terminal&logoColor=white) ![Platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu-A800D6?logo=ubuntu&logoColor=white) ![GitHub last commit](https://img.shields.io/github/last-commit/zeno528/kairo?color=orange) ![GitHub repo size](https://img.shields.io/github/repo-size/zeno528/kairo?color=teal)

轻量 Linux 服务器运维工具箱 — 纯 Bash，菜单驱动，一行命令安装。覆盖 SSH、防火墙、Docker、Nginx、SSL 证书、系统监控等日常运维场景。

## 一键安装/升级

```bash
curl -fsSL https://raw.githubusercontent.com/zeno528/kairo/main/install.sh | bash
```

## 已安装后的快捷升级

```bash
ka update
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/zeno528/kairo/main/install.sh | bash -s -- uninstall
```

## 安装目录结构

安装后 `ka` 命令及其运行库会落到以下位置（可通过 `KAIRO_BIN_DIR` / `KAIRO_LIB_DIR` 环境变量覆盖）：

| 用途 | 路径 | 备注 |
| --- | --- | --- |
| 命令入口 | `/usr/local/bin/ka` | 主菜单入口 |
| 运行库根目录 | `/usr/local/lib/kairo/` | 包含 `VERSION` / `lib/` / `modules/` |
| └ 版本号 | `/usr/local/lib/kairo/VERSION` | 安装时校验和升级比对都靠它 |
| └ 核心库 | `/usr/local/lib/kairo/lib/` | `core.sh` 等共享逻辑 |
| └ 模块 | `/usr/local/lib/kairo/modules/` | 完整列表见仓库根目录的 [`manifest.txt`](./manifest.txt) |
| 运行时缓存 | `/var/cache/kairo/` | 由各模块按需写入（如版本探测结果），丢失可自动重建 |




## 使用

```bash
ka  # 进入主菜单
```

## 功能列表

### SSH 管理
- **密码登录管理** — 开启/关闭密码登录、Root 登录状态查看
- **公钥管理** — 添加/删除/查看/重命名 authorized_keys 公钥

### 系统工具
- **系统信息** — 主机名、系统、内核、CPU、内存、磁盘、网络信息查看
- **端口/任务管理** — 查看监听端口、按端口/名称查找进程、按内存占用排行并终止进程
- **防火墙** — 支持 ufw / iptables，端口开关、防火墙启停
- **服务管理** — systemctl 服务状态查看、启停、重启、开关自启
- **定时任务** — 查看/添加/删除/编辑 crontab 定时任务
- **SSL 证书** — 自动发现本机 Let's Encrypt 证书、远程域名证书检查、批量到期检测
- **软件更新** — 检查可更新包、预演完整升级、执行常规升级/完整升级、清理缓存
- **网络测试** — 网络测速、三网回程路由、全国节点 Ping 延迟；测试文件仅在临时目录中使用，结束后自动清理

### Docker
- **Docker 管理** — 容器列表、启停重启、查看日志、镜像管理

### 工具管理
- **GitHub CLI** — 配置 GitHub 官方 apt 源后安装或升级 `gh`。
- **Go / jq / SQLite3** — 按系统现有官方安装渠道安装或升级开发与数据工具。

### AI Agent
- **Claude Code / Codex CLI / Kimi Code** — 使用各自官方安装器安装，并检查、升级 CLI。
- **OpenClaw** — 使用官方命令或 npm 升级，自动重启用户级 Gateway 并运行 doctor。

### Nginx 反向代理

反向代理：让 Nginx 统一接收外部请求再转发给本机各服务，所有域名共用 80/443 端口，服务本身不必直接暴露在公网。

- **安装 / 升级** — 从 nginx 官方源安装最新稳定版；已安装时检查并提示升级，版本信息本地缓存，进菜单不卡顿。
- **站点管理** — 添加反代站点只需填「域名 + 后台地址:端口」，自动生成含 HTTPS 和 WebSocket 的配置；可查看、删除单个站点。
- **站点禁用 / 启用** — 让某个站点暂时下线（保留配置和证书不删），之后一键重新上线，适合后台维护或临时关站。
- **证书** — 一键申请 Let's Encrypt 免费 HTTPS 证书并自动续期。
- **安全加固扫描** — 检查 Nginx 配置的安全项：HTTPS（TLS）版本新不新、安全响应头（防劫持、防点击劫持等）配没配、证书有没有。只读，列出还缺哪些，不自动改。
- **配置快照 / 回滚** — 改配置前先备份（留最近 5 份）；改错导致站打不开时，一键恢复到之前的好版本，恢复前自动校验语法。
- **日志 + Top 分析** — 实时查看访问和错误日志；Top 分析统计今天的访问：最活跃的 IP、最热门的地址、状态码分布、总流量，排查异常访问或报错时用。

## 支持系统

- Debian / Ubuntu
