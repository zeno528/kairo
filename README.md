# Kairo

![Version](https://img.shields.io/badge/version-1.1.24-blue) ![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnome-terminal&logoColor=white) ![Platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu-A800D6?logo=ubuntu&logoColor=white) ![GitHub last commit](https://img.shields.io/github/last-commit/zeno528/kairo?color=orange) ![GitHub repo size](https://img.shields.io/github/repo-size/zeno528/kairo?color=teal)

通用运维脚本工具箱，一行命令部署。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/zeno528/kairo/main/install.sh | sudo bash
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/zeno528/kairo/main/install.sh | sudo bash -s -- uninstall
```

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
- **端口/进程** — 查看监听端口、按端口/名称查找进程、终止进程
- **防火墙** — 支持 ufw / iptables，端口开关、防火墙启停
- **服务管理** — systemctl 服务状态查看、启停、重启、开关自启
- **定时任务** — 查看/添加/删除/编辑 crontab 定时任务
- **SSL 证书** — 本机证书检查、远程域名证书检查、批量到期检测
- **软件更新** — 检查可更新包、预演完整升级、执行常规升级/完整升级、清理缓存
- **网络测试** — 网络测速、三网回程路由、全国节点 Ping 延迟

### Docker
- **Docker 管理** — 容器列表、启停重启、查看日志、镜像管理

### Nginx 反向代理
- **安装/升级** — 走 nginx 官方 apt 源（永远拿到最新 stable），已装则自动跳过同版本、旧版本提示升级
- **站点管理** — 列出/添加/删除反代站点（sites-available + sites-enabled 软链，模板对齐现有写法）
- **证书** — 一键申请/续期 Let's Encrypt 证书（certbot，优先 snap 路径，按官方推荐）
- **运维** — 状态总览（含版本/服务/监听端口/证书数）、启停重启重载、开关开机自启、实时日志

## 支持系统

- Debian / Ubuntu
