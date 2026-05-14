# CLAUDE.md

## 项目概述

基于 ImmortalWrt 的固件自动编译系统。通过模块化 Shell 脚本对上游 ImmortalWrt 源码进行配置、修补和编译，产出定制路由器/软路由固件。

## 分支架构

项目有两个主要分支，**每次修改前必须先确认当前分支和要修改的分支**：

### ipq60xx 分支（当前分支）
- **目标设备**: JD Cloud IPQ60xx（Qualcomm IPQ6018，ARM64）
- **上游源码**: `https://github.com/VIKINGYFY/immortalwrt.git` (main 分支)
- **编译目录**: `imm-nss`
- **配置入口**: `wrt_core/compilecfg/jdcloud_ipq60xx_immwrt.ini`
- **主配置文件**: `wrt_core/deconfig/jdcloud_ipq60xx_immwrt.config`
- **补充配置片段**: `compile_base.config`, `docker_deps.config`, `nss.config`, `proxy.config`
- **关键特性**: 包含 NSS (Network SubSystem) 硬件加速补丁、ath11k WiFi 固件
- **产出物**: `.bin` 固件文件 + `.manifest`

### x86_64 分支
- **目标平台**: x86_64 PC / 虚拟机（软路由）
- **上游源码**: `https://github.com/immortalwrt/immortalwrt.git` (v24.10.6 分支)
- **编译目录**: `immortalwrt`
- **配置入口**: `wrt_core/compilecfg/x64_immwrt.ini`
- **主配置文件**: `wrt_core/deconfig/x64_immwrt.config`
- **补充配置片段**: `compile_base.config`, `docker_deps.config`, `proxy.config`
- **关键特性**: 无 NSS 加速（不适用 x86），大量 luci-app 软件包
- **产出物**: `*efi.img.gz`, `*combined.img.gz`, `*rootfs.tar.gz`, `*.vmdk`, `*.qcow2` + `.manifest`

## 核心目录结构

```
wrt_core/
├── build.sh              # 主构建脚本（两分支各自硬编码不同 CONFIG_FILE/INI_FILE）
├── update.sh             # 克隆上游源码 + 运行所有模块函数进行修补
├── pre_clone_action.sh   # 预克隆：解析 INI，克隆上游仓库，移除国内镜像源
├── compilecfg/           # INI 配置（REPO_URL, REPO_BRANCH, BUILD_DIR）
├── deconfig/             # .config 配置文件（kernel/驱动/包选型）
├── modules/              # 修补脚本模块（被 update.sh source 后调用）
│   ├── system.sh         # 系统级修补（LAN 地址、菜单顺序、默认设置等）
│   ├── feeds.sh          # feeds 源管理、golang 更新、dnsmasq 切换
│   ├── packages.sh       # 软件包调整、卸载/替换/添加包
│   ├── docker.sh         # Docker 相关修补（dockerd, dockerman, nftables 兼容）
│   ├── cups.sh           # CUPS 打印服务修补
│   └── general.sh        # 其他通用修补
└── patches/              # 补丁文件和二进制固件
    ├── ath11k_fw.mk      # ath11k-firmware Makefile（IPQ60xx WiFi 固件）
    ├── *.patch           # 各类源码补丁
    ├── cpuusage / hnatusage / tempinfo / smp_affinity / nss_diag.sh  # 调试脚本
    ├── lucky_*.tar.gz    # Lucky 二进制文件（分 arm64/x86_64）
    ├── pbr.user.*        # PBR 策略路由配置（移动/电信/联通）
    └── openssl/          # OpenSSL 相关
```

## 关键开发命令

### 本地编译
```bash
# 完整编译
./build.sh

# Debug 模式（只做配置不编译）
./build.sh debug
```

### 本地测试单个模块函数
```bash
# 模块函数在 update.sh 中被 source 后调用
# 可以 source 后手动调用某个函数测试
source wrt_core/modules/system.sh
# 然后调用某个函数
```

## 构建流程

1. `build.sh` 解析 INI → 确定 REPO_URL、REPO_BRANCH、BUILD_DIR
2. 调用 `update.sh` → 克隆上游仓库到 `imm-nss/` 或 `immortalwrt/`
3. `update.sh` 执行 `main()` → 按顺序调用 modules/ 中所有函数进行修补
4. 回到 `build.sh` → 应用 config 片段，执行 `make defconfig`
5. `make download -jN && make -jN V=s`
6. 产物复制到 `firmware/` 目录

## CI/CD

GitHub Actions 工作流（仅 ipq60xx 分支配置了 CI）：
- `release_wrt.yml`: 手动触发 (`workflow_dispatch`)，完整编译并发布到 Release
- `schedule_daily.yml`: 定时触发（每周一 20:00 UTC），调用 release_wrt.yml
- 构建环境: ubuntu-24.04，超时 480 分钟
- Debug 产物上传到 `Andylive5518/make_tmp` 仓库

## 编码注意事项

- 所有脚本使用 Bash，`set -e` 确保错误即退出
- 模块脚本中的函数在 `update.sh` 的 `main()` 中按顺序调用，**顺序很重要**
- `build.sh` 中硬编码了 `CONFIG_FILE` 和 `INI_FILE` 路径，跨分支合并时注意冲突
- 配置文件片段通过 `cat` 追加到 `.config`，非覆盖
- 固件产出物的文件类型清理逻辑在 `build.sh` 中，两分支不同（ipq60xx 删 `.bin/.manifest`，x86_64 删各种镜像格式）

## 常见操作

### 添加新软件包
1. 修改对应分支的 `wrt_core/deconfig/*.config`，添加 `CONFIG_PACKAGE_xxx=y`
2. 如需修补 Makefile/源码，在 `wrt_core/modules/packages.sh` 中添加函数
3. 在 `wrt_core/update.sh` 的 `main()` 中调用该函数

### 跨分支同步修改
- 两分支有大量共同代码（modules/ 完全相同，update.sh 主逻辑相同）
- 在 A 分支修复的 bug 通常也适用于 B 分支
- 使用 `git cherry-pick` 跨分支移植提交
- `build.sh` 由于硬编码路径不同，合并时需手动处理
