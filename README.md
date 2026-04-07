# OPSTOOL

通用运维脚本工具箱，一行命令部署。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Ekko7778/opstool/main/install.sh | bash
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/Ekko7778/opstool/main/install.sh | bash -s -- uninstall
```

## 使用

```bash
ot  # 进入主菜单
```

## 支持系统

- Debian / Ubuntu
- CentOS / RHEL / AlmaLinux
- Arch Linux

## 添加新模块

1. 在 `modules/` 目录创建 `xxx.sh`
2. 文件头部写 `# alias: xx` 定义快捷命令
3. 实现 `menu()` 函数作为二级菜单
4. 提交推送，目标机器重新运行安装命令即可
