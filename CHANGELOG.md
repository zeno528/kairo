# 更新日志

## v1.2.27 (2026-08-04)
- ✨ feat(docker): 优化 Docker 安装、升级和卸载过程中的信息输出，提升用户体验

## v1.2.26 (2026-08-04)
- ✨ feat(docker): 优化安装、升级和卸载过程中的命令输出，提升用户体验

## v1.2.25 (2026-08-04)
- ✨ feat(docker): 添加支持保留本机代理变量的 sudo 网络命令功能

## v1.2.24 (2026-08-04)
- ✨ feat(kairo): 添加更新后返回主菜单的功能，优化用户体验

## v1.2.23 (2026-08-04)
- ✨ feat(docker): 优化镜像列表显示，增加状态和编号列，提升可读性

## v1.2.22 (2026-08-04)
- ✨ feat(docker): 添加支持 Debian 和 Ubuntu 的 apt 源选择功能

## v1.2.21 (2026-08-04)
- ✨ feat(tests): 优化测试输出格式，增强可读性和一致性

## v1.2.20 (2026-08-04)
- ✨ feat(menu): 统一动态编号范围显示，优化菜单选项的可读性

## v1.2.19 (2026-08-04)
- ✨ feat(docker): 更新镜像管理功能，使用完整 Image ID 关联容器状态，增强输出信息

## v1.2.18 (2026-08-04)
- ✨ feat(docker): 优化镜像列表显示，支持按最长名称对齐列

## v1.2.17 (2026-08-04)
- 🐛 fix(install): 调整输出格式，确保提示信息前有空格

## v1.2.16 (2026-08-04)
- ✨ feat(docker): 增强状态显示功能，支持中文时间格式和端口打印

## v1.2.15 (2026-08-04)
- ✨ feat(menu): 将返回主菜单的选项从 H 改为 00

## v1.2.14 (2026-08-04)
- 🐛 fix(docker): 按状态显示容器与 Agent 操作
  - 运行项仅显示红色停止，已停止项仅显示绿色启动
  - latest 镜像优先显示 OCI 声明的实际版本
  - 升级版本至 1.2.13 并添加菜单回归测试

## v1.2.13 (2026-08-04)
- 🐛 fix(docker): 按实际状态显示容器与哪吒 Agent 的启停操作
- 🐛 fix(docker): 将带 OCI 版本标签的 latest 镜像显示为实际版本

## v1.2.12 (2026-08-01)
- ✨ feat(port-proc): 内存占用排行终止进程支持默认回车确认
  - 从内存占用排行中终止进程时，按回车默认确认，无需手动输入 y。
  - 修复 SIGTERM 成功后仍误报“无法终止进程（权限不足？）”的问题。
  - kill 失败时输出错误信息并返回 1，而不是提示“已取消”。
  - 新增相应的 Bats 测试。

## v1.2.11 (2026-08-01)
- ✨ feat(port-proc): 内存占用排行支持循环查看与刷新
  - 内存排行页改为循环展示，支持直接返回管理菜单
  - 新增 [R] 选项刷新内存排行
  - 修正无效选项的判断逻辑，避免误退出
  - 补充内存排行刷新功能的 bats 测试

## v1.2.10 (2026-08-01)
- ✨ feat(port-proc): 新增系统内存总览显示
  - 读取 /proc/meminfo 计算总内存、已用、可用及使用占比
  - 在内存占用排行前展示系统内存总览
  - 补充测试断言验证输出内容

## v1.2.9 (2026-08-01)
- ✨ feat(port-proc): 端口/任务管理新增内存占用排行功能
  - 新增 do_list_memory 函数，按内存占用排序显示 Top N 进程
  - 菜单增加 [M] 内存占用排行入口，支持选择进程直接终止
  - 更新模块注册信息、README 文档及 Bats 测试

## v1.2.8 (2026-07-31)
- 🎨 style(update): 更新流程输出统一为 >>> 引导风格
  - ka update 与 install.sh 的提示行统一 >>> 前缀与配色，消除交互 UI 与安装器两种风格混排
  - 下载进度行加 \033[K 清行并改为 [N/M] 前置，根除回车残留字符与宽度跳动

## v1.2.7 (2026-07-31)
- 🔧 chore(ci): 固定 shellcheck 0.11.0 并统一本地验证命令
  - CI 镜像自带 shellcheck 版本漂移，曾致 SC2120 误报（本地 0.11 不报、CI 旧版报）
  - 固定 v0.11.0 使 CI 行为可复现；本地 AGENTS.md 验证门槛同步为同一命令与版本

## v1.2.6 (2026-07-31)
- 🐛 fix(core): 消除旧版 shellcheck 对 kairo_pause 的 SC2120 误报
  CI 镜像的 shellcheck 版本较旧，单文件分析无法感知 kairo_pause 由主入口和各模块菜单跨文件调用，误报从未传参；按 nezha-agent do_mgmt 的既有惯例加 disable 注释

## v1.2.5 (2026-07-31)
- 🎨 style(kairo): 重构启动横幅 K logo 与信息布局
  - K 字形重绘为标准 V 形双笔，竖线亮青、斜线暗青渐变层次
  - 右侧信息与 logo 等高排布：标题+版本号 / 副标题 / 启动命令与仓库链接
  - 版本号亮色强调，ka 命令加粗标注，仓库链接完整 URL 悬停可点击

## v1.2.4 (2026-07-31)
- 🔧 refactor(modules): 抽取工具菜单与 apt 升级共享逻辑
  - lib/core.sh 新增 _tool_menu / _tool_apt_upgrade / _tool_run_remote_installer 三个共享辅助
  - claude / codex / github-cli / go / jq / kimi / openclaw / sqlite3 共 8 个工具模块的 menu 与 apt 升级改为调用共享辅助
  - registry 同步开放 firewall.delete_rule、docker.uninstall/reset/overview、github-cli.auth 五个新 action
  - install.sh 校验流程去掉对 kairo.sh 的重复 bash -n
  - 新增 tests/modules-extra.bats，覆盖此前无专项测试的 fail2ban / crontab / nezha-agent / swap / optimize / proxy-setup 模块

## v1.2.3 (2026-07-31)
- 🔧 refactor(registry): 合并代理分组到网络，精简主菜单
  - 移除仅 2 个模块的 🚀 代理分组
  - nginx 和节点搭建迁移到 🌐 网络与代理

## v1.2.2 (2026-07-31)
- 🐛 fix(crontab): 修复 */N 小时和 @reboot 特殊调度报错，恢复自适应列宽
  - 补充 */N 小时字段的语义解释，修复 printf 无效数字报错
  - 支持 @reboot/@daily/@hourly 等 cron 特殊关键字，不再按五字段误解析
  - 恢复两遍遍历自适应列宽和 ⏱ 图标样式
  ✨ feat(swap): 新增虚拟内存管理模块（zram + disk swap）
  - 支持 zram 内存压缩（推荐）和传统磁盘交换文件
  - 交互式大小选择，支持自定义输入（如 768M、3G）
  - 状态显示中文格式化输出，含开机自启检测
  - 开机自启支持 @reboot cron 持久化

## v1.2.1 (2026-07-31)
- 🐛 fix(registry): 移除 crontab 不存在的 remove action

## v1.2.0 (2026-07-31)
- ✨ feat(crontab): 全面重构定时任务模块，UX 完全重做
- ✨ feat(crontab): 新增引导式任务创建，无需记忆 cron 语法
- ✨ feat(crontab): 新增语义解释，每条任务显示人类可读含义
- ✨ feat(crontab): 新增任务启用/禁用功能（#KAIRO_OFF# 标记）
- ✨ feat(crontab): 新增批量操作（批量删除/启用/禁用）
- ✨ feat(crontab): 新增任务编辑子菜单（编辑调度/命令）
- ✨ feat(crontab): 调度编辑支持逗号多值语义解释
- 🔥 chore(crontab): 移除 [E] 编辑全部（vi 依赖，UX 差）
- 🎨 refactor(services): 服务列表 active/inactive/failed 添加彩色圆点
- 🎨 refactor(ssh-passwd): 状态显示用 _pad_right 对齐文案

## v1.1.99 (2026-07-31)
- 🐛 fix(docker): 镜像清理缺 -a 导致只清悬空镜像
- 🎨 refactor(docker): 重构 Docker 菜单布局，双列+底栏，UX 更清晰
- 🎨 refactor(docker): 重构状态缓存渲染，版本信息精简紧凑
- 🎨 refactor(docker): 资源总览列头 名称→镜像/容器，大小内联到镜像名
- 🔥 chore(docker): 移除 [R] 从镜像运行功能（无实用价值）
- 🎨 refactor(docker): 镜像列表增加列标题，图例独立行，列宽收紧

## v1.1.98 (2026-07-31)
- 👷 ci(lint): 更新 GitHub Actions 与 Bats 版本

## v1.1.97 (2026-07-31)
- ✨ feat(docker): 新增 Compose 项目自动发现并重构清理逻辑

## v1.1.96 (2026-07-31)
- ✨ feat(github-cli): do_status 增加 gh 认证状态显示
- ✨ feat(github-cli): 新增 [A] 认证登录，支持 Token/浏览器/设备码三种方式
- 🐛 fix(github-cli): 认证状态显示修复单引号导致颜色变量未展开

## v1.1.95 (2026-07-31)
- ✨ feat(docker): 总览新增端口映射列和名称/状态/端口中文列标题
- 🎨 refactor(docker): 优化总览列宽与对齐，使用 _pad_right 统一排版
- 🎨 refactor(docker): [R] 从镜像运行容简化交互，容器名可选，运行后显示 ID

## v1.1.94 (2026-07-31)
- ✨ feat(docker): 新增资源总览视图，树形结构整合容器与镜像
- ✨ feat(docker): 新增 [R] 从镜像快速运行容器
- ✨ feat(docker): 新增 [X] 重置环境，清空容器/镜像/卷但保留 Docker
- 🎨 refactor(docker): 提取 _container_ops_menu 公共函数，消除重复代码

## v1.1.93 (2026-07-31)
- ✨ feat(docker): 新增 Docker 完整卸载功能
- 🐛 fix(docker): 修复 _docker_installed 因 bash 命令哈希缓存误判为已安装
- 🐛 fix(docker): 修复容器列表重复显示两次的问题
- 🎨 refactor(docker): 卸载确认改为 y/N 风格，与项目其他提示一致

## v1.1.92 (2026-07-31)
- ✨ feat(docker): 改进 Docker 升级时的版本比较逻辑

## v1.1.91 (2026-07-31)
- ✨ feat(nezha): 新增 agent 版本信息显示功能

## v1.1.90 (2026-07-31)
- ✨ feat(docker): 新增 Docker 升级功能

## v1.1.89 (2026-07-31)
- ✨ feat(nezha): 新增 Nezha 管理面板入口与独立安装脚本

## v1.1.88 (2026-07-31)
- ✨ feat(menu): 为各模块子菜单添加返回主菜单快捷键 (H) 并更新模块描述

## v1.1.87 (2026-07-31)
- 🌈 style(docker): 优化镜像列表中的使用状态提示文本

## v1.1.86 (2026-07-31)
- ⚡️ perf(modules): 优化 Docker 状态检测性能并重构镜像列表收集

## v1.1.85 (2026-07-31)
- ✨ feat(modules): 重构 Docker Compose 管理，支持镜像版本切换

## v1.1.84 (2026-07-31)
- ✨ feat(modules): 重构 Docker 镜像管理，增加镜像删除与清理菜单

## v1.1.83 (2026-07-31)
- ✨ feat(modules): 重构哪吒监控 Agent 管理，支持多实例管理

## v1.1.82 (2026-07-31)
- ⚡️ perf(modules): 引入状态缓存优化 Docker 管理菜单的显示性能

## v1.1.81 (2026-07-31)
- ♻️ refactor(modules): 重构基础工具渲染逻辑并清理 Docker 状态输出

## v1.1.80 (2026-07-31)
- ✨ feat(modules): 增强基础工具与SSL证书管理功能

## v1.1.79 (2026-07-31)
- ✨ feat(modules): 新增基础工具管理模块（basics）

## v1.1.78 (2026-07-31)
- ✨ feat(modules): 整合代理与网络测试模块并统一 apt 操作入口

## v1.1.77 (2026-07-31)
- ✨ feat(docker): 增加Docker安装、状态监控、容器操作及Compose管理等功能

## v1.1.76 (2026-07-31)
- ✨ feat(modules): 新增多个功能模块并重构分类注册

## v1.1.75 (2026-07-31)
- 🌈 style(menu-output): 统一使用 _menu_actions 函数重构菜单输出格式

## v1.1.74 (2026-07-31)
- 🌈 style(menu-output): 重构菜单输出格式，统一使用 _menu_actions 函数

## v1.1.73 (2026-07-31)
- 🌈 style(security-update): 调整菜单项输出格式，统一使用 echo -e

## v1.1.72 (2026-07-31)
- ✨ feat(firewall): 重构防火墙模块，仅支持 ufw，新增 IP 黑白名单功能

## v1.1.71 (2026-07-31)
- 🌈 style(crontab): 调整定时任务列表的列对齐宽度

## v1.1.70 (2026-07-31)
- ✨ feat(modules): 新增 CPU 线程数显示并改进核心数计算

## v1.1.69 (2026-07-31)
- ✨ feat(modules): 新增菜单操作按钮格式化函数并应用到各模块

## v1.1.68 (2026-07-31)
- ✨ feat(modules): 改进定时任务模块和系统信息模块，新增内存类型与 IPv6 检测

## v1.1.67 (2026-07-31)
- 🌈 style(modules): 统一脚本中的代码风格与格式化

## v1.1.66 (2026-07-31)
- ✨ feat(system): 重构系统信息模块并优化安全更新菜单交互

## v1.1.65 (2026-07-31)
- ✨ feat(optimize): 合并 BBR 加速与内核调优模块为系统优化模块，新增 BBRv3 支持

## v1.1.64 (2026-07-30)
- ✨ feat(ui): 统一将各模块菜单中的返回选项从"返回上级"更新为"返回主菜单"

## v1.1.63 (2026-07-30)
- ✨ feat(system): 添加 BBR 加速、fail2ban 防暴破和内核调优模块，扩展网络测试与清理功能

## v1.1.62 (2026-07-30)
- ♻️ refactor(ui): 重构主菜单自适应布局，优化框宽度计算

## v1.1.61 (2026-07-30)
- ✨ feat(ui): 重构启动横幅，简化布局并添加对齐工具函数

## v1.1.60 (2026-07-30)
- ✨ feat(ui): 重构启动横幅，增加 logo 并自适应终端宽度

## v1.1.59 (2026-07-30)
- ✨ feat(install): 升级完成后提示返回命令行而非自动重启

## v1.1.58 (2026-07-30)
- ✨ feat(ui): 在所有模块菜单中添加清屏功能

## v1.1.57 (2026-07-30)
- ✨ feat(ui): 改进安装完成提示与主菜单横幅显示

## v1.1.56 (2026-07-30)
- ✨ feat(install): 改进安装与更新流程中的输出消息

## v1.1.55 (2026-07-30)
- ✨ feat(modules): 改进版本检测逻辑，优先从包管理器获取版本号

## v1.1.54 (2026-07-30)
- ✨ feat(sqlite3): 改进版本检测逻辑，优先从包管理器获取版本号

## v1.1.53 (2026-07-30)
- ♻️ refactor(core): 清理旧版入口和运行库的残留引用

## v1.1.52 (2026-07-30)
- ✨ feat(core): 支持非 root 用户安装时自动使用 sudo 权限

## v1.1.51 (2026-07-30)
- ✨ feat(core): 更新安装器非 root 模式下向 sudo 透传代理环境

## v1.1.50 (2026-07-30)
- ✨ feat(security-update): 改进清理功能，增加孤立包预览和用户确认

## v1.1.49 (2026-07-30)
- ♻️ refactor(core): 统一将 `apt` 命令替换为 `apt-get`

## v1.1.48 (2026-07-30)
- ♻️ refactor(core): 移除持续输出命令的 spinner 包装，并添加验证测试

## v1.1.47 (2026-07-30)
- ♻️ refactor(core): 重构菜单显示并优化软件更新流程

## v1.1.46 (2026-07-30)
- ✨ feat(menu): 支持双列菜单布局并新增 AI Agent 分组

## v1.1.45 (2026-07-30)
- ✨ feat(tools): 为 Codex 和 OpenClaw 升级流程添加版本缓存与更新状态检查

## v1.1.44 (2026-07-30)
- 🐛 fix(tools): 修复 spinner 调用语法并优化 apt 更新输出

## v1.1.43 (2026-07-30)
- ♻️ refactor(tools): 移除安装前的已安装检测，支持覆盖安装

## v1.1.42 (2026-07-30)
- ✨ feat(codex): 添加 Codex CLI 工具支持

## v1.1.41 (2026-07-30)
- ♻️ refactor(core): 移除 `kairo_link` 函数，改用纯文本 URL 输出

## v1.1.40 (2026-07-30)
- ♻️ refactor(tools): 重构工具模块安装渠道检测逻辑，新增 SQLite3 模块

## v1.1.39 (2026-07-30)
- 🐛 fix(entrypoint): 修正测试用例中的 grep 命令参数

## v1.1.38 (2026-07-30)
- ✨ feat(tools): 添加 Go 与 jq 工具管理模块，支持安装与升级

## v1.1.37 (2026-07-30)
- ✨ feat(tools): 添加工具管理模块，支持 AI 编程助手与 GitHub CLI 的安装升级

## v1.1.36 (2026-07-30)
- ♻️ refactor(nginx): 优化安全扫描站点列表输出格式

## v1.1.35 (2026-07-30)
- ♻️ refactor(nginx): 优化安全扫描站点列表输出格式

## v1.1.34 (2026-07-30)
- 🐛 fix(nginx): 稳定发布日期缓存写入

## v1.1.33 (2026-07-30)
- 🐛 fix: 清理网络测试文件并修复 CI lint

## v1.1.32 (2026-07-30)
- ✨ feat(install): 优化安装升级提示，显示版本过渡信息

## v1.1.31 (2026-07-30)
- ✨ feat(nginx): 新增站点启用/禁用、安全扫描、配置快照与日志分析功能

## v1.1.30 (2026-07-30)
- ⚡️ perf(nginx): 状态总览改用本地缓存的发布日期，零联网零延迟

## v1.1.29 (2026-07-30)
- ♻️ refactor(modules): 重构模块错误处理，统一命令执行模式并新增公共函数

## v1.1.28 (2026-07-30)
- ⚡️ perf(modules): 优化安装、网络测试、端口进程、服务、SSL 及系统信息模块的性能

## v1.1.27 (2026-07-29)
- ✨ feat(modules): 新增 Nginx 版本发布日期、安全更新扫描进度及 SSL 本机证书自动发现功能

## v1.1.26 (2026-07-29)
- 🐛 fix(install): 更新下载链接以使用原始内容 URL，修复文件获取逻辑

## v1.1.25 (2026-07-29)
- 💄 ui: 优化用户确认提示格式，增强可读性

## v1.1.24 (2026-07-29)
- 💄 ui(security-update): 添加完整升级预演功能，优化用户操作体验

## v1.1.23 (2026-07-29)
- Refactor and enhance modules for improved user experience and functionality

## v1.1.22 (2026-07-29)
- 🐛 fix(update): 移除更新过程中的加载指示器

## v1.1.21 (2026-07-29)
- 💄 ui(nginx): 优化菜单显示格式，增强可读性

## v1.1.20 (2026-07-29)
- 💄 ui(nginx): 收敛 Nginx 管理菜单

## v1.1.19 (2026-07-29)
- 💄 ui(banner): 移除版本行中的标签图标

## v1.1.18 (2026-07-29)
- 🐛 fix(sys-info): 仅显示 CPU 主型号

## v1.1.17 (2026-07-29)
- 💄 ui(menus): 明确操作完成后的返回流程

## v1.1.16 (2026-07-29)
- 🔒 security(ssh): 确认密码登录切换操作

## v1.1.15 (2026-07-29)
- 🐛 fix(modules): 修复 Nginx 站点选择与网卡状态

## v1.1.14 (2026-07-29)
- 💄 ui(firewall): 明确防火墙操作流程

## v1.1.13 (2026-07-29)
- fix: 修复防火墙与软件更新行为

## v1.1.12 (2026-07-29)
- ui: 标签图标移回版本号前，收紧空格

## v1.1.11 (2026-07-29)
- ui: 标签图标移到版本号后

## v1.1.10 (2026-07-29)
- ui: 版本号前加标签图标

## v1.1.9 (2026-07-29)
- ui: 安装/卸载文案工具名统一为 Kairo

## v1.1.8 (2026-07-29)
- ui: 横幅工具名改为 Kairo

## v1.1.7 (2026-07-29)
- ui: 统一菜单与卸载文案工具名为 Kairo

## v1.1.6 (2026-07-29)
- chore: ignore local AI project rules

## v1.1.5 (2026-07-29)
- refactor: simplify uninstall flow

## v1.1.4 (2026-07-29)
- fix: make uninstall verifiable and complete

## v1.1.3 (2026-07-29)
- docs: simplify install commands

## v1.1.2 (2026-07-29)
- fix: harden modular runtime and deployment

## v1.1.1 (2026-07-29)
- refactor module foundation

## v1.1.0 (2026-07-29)
- 🎉 rename(kairo): 项目更名为 Kairo，快捷命令改为 `ka`，并迁移运行时目录与 GitHub 仓库。

## v1.0.41 (2026-07-29)
- fix(nginx): keep status summary on one line

## v1.0.40 (2026-07-29)
- ✨ feat(kairo): 为所有慢操作添加旋转指示器避免误判卡死

## v1.0.39 (2026-07-29)
- ✨ feat(nginx): 增强反代配置，支持 WebSocket 并优化 SSL 安全

## v1.0.38 (2026-07-29)
- 💄 ui(kairo): 分割线改为虚线样式，菜单分组间增加空行

## v1.0.37 (2026-07-29)
- 💄 ui(kairo): 精简 banner 布局，将标题融入顶部边框线

## v1.0.36 (2026-07-29)
- ✨ feat(nginx): 增强 Nginx 安装/升级流程，自动保留现有配置并使用非交互模式

## v1.0.35 (2026-07-29)
- ✨ feat(nginx): 改变确认提示默认值，提升安装/升级便捷性

## v1.0.34 (2026-07-29)
- ♻️ refactor(kairo): 将文件下载从 raw CDN 迁移至 GitHub Contents API

## v1.0.33 (2026-07-29)
- ♻️ refactor(kairo): 动态计算分割线宽度以自适应终端尺寸

## v1.0.32 (2026-07-29)
- 🔧 chore(nginx): 增强安装过程的信息输出

## v1.0.31 (2026-07-29)
- ♻️ refactor(kairo): 重构启动横幅显示

## v1.0.30 (2026-07-29)
- ♻️ refactor(nginx): 重构版本检测与安装逻辑

## v1.0.29 (2026-07-29)
- ♻️ refactor(modules): 重构变量声明与数组处理方式

## v1.0.28 (2026-07-29)
- ✨ feat(nginx): 新增 Nginx 反向代理管理模块（[12] Nginx 管理）— 安装走官方源、添加/删除反代站点、一键申请 Let's Encrypt 证书、状态/日志/启停/重载
- 📝 docs(readme): 功能列表加 Nginx 反向代理段
- 🔖 chore: 版本号 1.0.27 → 1.0.28

## v1.0.27 (2026-05-14)
- 🔥 refactor: 清理死代码（废弃 alias 机制残留、未使用变量）

## v1.0.26 (2026-05-14)
- ✨ feat(ssh-keys): 实现SSH公钥批量删除功能

## v1.0.25 (2026-05-14)
- 🌈 style(install): 优化安装完成提示信息，添加颜色输出

## v1.0.24 (2026-05-14)
- ✨ feat(install): 优化安装过程，添加进度显示

## v1.0.23 (2026-05-14)
- 📝 docs(readme): 更新版本号至 1.0.22

## v1.0.22 (2026-05-14)
- ♻️ refactor(kairo.sh): 移除终端超链接支持，简化横幅显示

## v1.0.21 (2026-05-14)
- ✨ feat(ui): 优化主菜单布局并添加可点击链接

## v1.0.20 (2026-05-14)
- ♻️ refactor(ssh-keys): 调整行号计算逻辑，去除重复的行号递增

## v1.0.19 (2026-05-03)
- 📝 docs(README): 更新 README 中的 badges 信息

## v1.0.18 (2026-05-03)
- chore: 更新仓库所有者信息为zeno528

## v1.0.17 (2026-04-08)
- ✨ refactor(network-test): 重构网络测试脚本，优化测速和 Ping 测试功能。

## v1.0.16 (2026-04-08)
- ✨ refactor(network-test): 替换回程路由测试为 backtrace 工具。

## v1.0.15 (2026-04-08)
- 📝 docs(README): 更新支持系统说明。

## v1.0.14 (2026-04-08)
- 📝 docs(README): 更新系统支持说明和模块添加指南。

## v1.0.13 (2026-04-08)
- ✨ refactor(kairo): 重构模块加载逻辑并优化菜单结构。

## v1.0.12 (2026-04-08)
- 🌈 style(kairo): 优化脚本颜色和显示格式。

## v1.0.11 (2026-04-08)
- 🌈 style(kairo): 统一输出格式并引入颜色辅助函数。

## v1.0.10 (2026-04-08)
- ✨ feat(ssh-keys): 添加修改公钥备注功能。

## v1.0.9 (2026-04-08)
- ♻️ refactor(ssh-passwd): 重构 SSH 配置设置逻辑并新增 Root 登录检查功能。

## v1.0.8 (2026-04-08)
- 🔧 chore(kairo): 调整菜单选项顺序并新增SSH公钥管理功能。

## v1.0.7 (2026-04-07)
- 📝 docs(changelog): 添加更新日志文件并记录历史版本

## v1.0.4 (2026-04-07)
- ✨ feat(kairo): 添加新功能模块及优化菜单显示

## v1.0.3 (2026-04-07)
- ✨ fix(install): 优化模块下载逻辑并增加缓存失效机制。

## v1.0.2 (2026-04-07)
- 🌈 style(kairo): 优化启动横幅显示格式。

## v1.0.1 (2026-04-07)
- fix: replace logo with OPS text
