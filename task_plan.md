# 任务计划：Python 声明式构建工具

## 目标
将 ~2500 行 Shell 脚本 + 40 个手动管理的 patch 文件，重构为 Python 声明式构建工具。
用户只需编辑 `build.yaml` 即可完成所有新增、修改、删除操作。

## 当前阶段
Phase 1

## 各阶段

### Phase 1：基础设施（Python 骨架 + 配置 + 管线）
- [x] Task 1: 创建目录结构和 requirements.txt
- [x] Task 2: 日志系统 logger.py
- [x] Task 3: 配置模型 config.py
- [x] Task 4: 创建完整的 build.yaml
- [x] Task 5: 所有模块 stub 文件 + main.py CLI 入口
- [x] Task 6: 更新 build.sh 为兼容层
- [ ] Task 7: 验证 Python 工具可运行
- **状态：** in_progress

### Phase 2：核心模块（替换 packages.sh / feeds.sh / patcher 手动调用）
- [ ] Task 8: 实现 patcher.py（patch 自动应用 + dry-run + upgrade-check）
- [ ] Task 9: 实现 packages.py（包移除 + tweak + APK 修复）
- [ ] Task 10: 实现 feeds.py（自定义 feed 稀疏克隆 + 外部仓库）
- **状态：** pending

### Phase 3：复杂模块（替换 docker.sh / system.sh）
- [ ] Task 11: 实现 docker.py（nftables 兼容 + 1009 行 docker.sh 替换）
- [ ] Task 12: 实现 system.py（UCI defaults + PBR + ttyd 等）
- [ ] Task 13: 实现 image.py（make + 产物打包）
- **状态：** pending

### Phase 4：收尾
- [ ] Task 14: 更新 GitHub Actions workflow
- [ ] Task 15: 删除旧 Shell 模块
- [ ] Task 16: 更新 CLAUDE.md
- **状态：** pending

## 关键问题
1. GitHub Actions 中 Python 3.10+ 是否可用？→ ubuntu-24.04 默认 Python 3.12
2. pyyaml 在 CI 中安装是否顺利？→ pip install pyyaml 1 秒

## 已做决策
| 决策 | 理由 |
|------|------|
| Python 3.10+ | ubuntu-24.04 默认版本 |
| PyYAML（非 Pydantic）| 减少依赖，配置简单 |
| 渐进式迁移 | 每个 Phase 独立可发布 |
| 保留 .patch 格式 | OpenWrt 生态标准，无需改变 |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
|      | 1       |         |

## 备注
- 始终保留旧的 Shell 脚本直到对应模块被完全替换
- Phase 1 完成后即可使用 `python wrt_core/builder/main.py --debug` 验证
