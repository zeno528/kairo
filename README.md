# VPS Toolkit

多 VPS 通用运维脚本工具箱，一行命令部署。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Ekko7778/vps-toolkit/main/install.sh | bash
```

## 可用命令

### ssh-passwd — SSH 密码登录开关

```bash
ssh-passwd on      # 开启密码登录
ssh-passwd off     # 关闭密码登录
ssh-passwd status  # 查看当前状态
```

## 支持系统

- Debian / Ubuntu
- CentOS / RHEL / AlmaLinux
- Arch Linux

## 添加新脚本

1. 在仓库根目录创建 `xxx.sh`
2. 在 `install.sh` 的 `scripts` 数组中添加文件名
3. 提交推送，目标 VPS 重新运行安装命令即可
