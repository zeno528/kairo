# EKKOBOX

通用运维脚本工具箱，一行命令部署。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Ekko7778/vps-toolkit/main/install.sh | bash
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/Ekko7778/vps-toolkit/main/install.sh | bash -s -- uninstall
```

## 可用命令

| 命令 | 作用 |
|:-----|:-----|
| `eb` | 主菜单（一级） |
| `eb update` | 检查更新 |
| `eb uninstall` | 卸载 |
| `sp` | SSH 密码登录管理 |

## 支持系统

- Debian / Ubuntu
- CentOS / RHEL / AlmaLinux
- Arch Linux

## 添加新模块

1. 在 `modules/` 目录创建 `xxx.sh`
2. 文件头部写 `# alias: xx` 定义快捷命令
3. 实现 `menu()` 函数作为二级菜单
4. 提交推送，目标机器重新运行安装命令即可
