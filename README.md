# OPSTOOL

通用运维脚本工具箱，一行命令部署。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/zeno528/opstool/main/install.sh | bash
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/zeno528/opstool/main/install.sh | bash -s -- uninstall
```

## 使用

```bash
ot  # 进入主菜单
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
- **安全更新** — 检查可更新包、执行安全更新/完整更新、清理缓存
- **网络测试** — 网络测速、三网回程路由、全国节点 Ping 延迟

### Docker
- **Docker 管理** — 容器列表、启停重启、查看日志、镜像管理

## 支持系统

- Debian / Ubuntu
