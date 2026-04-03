# ci.bazelrc 研究文档

## 场景与职责

本文件是 Bazel 在 CI 环境下的专用配置文件，扩展了根目录 `.bazelrc` 的配置，针对持续集成环境优化构建行为。它平衡了构建速度和可靠性，并针对不同操作系统配置了特定的执行策略。

## 功能点目的

1. **CI 环境优化**：配置适合 CI 的缓存、下载和失败处理策略
2. **远程执行支持**：启用 BuildBuddy 远程执行和缓存
3. **跨平台构建**：为 Linux、macOS 和 Windows 配置不同的执行策略
4. **构建可靠性**：配置 `--keep_going` 确保尽可能多地发现问题

## 具体技术实现

### 通用配置
```bash
common --remote_download_minimal
common --keep_going
common --verbose_failures
```

| 配置项 | 说明 |
|--------|------|
| `--remote_download_minimal` | 仅下载必需的输出文件，减少网络传输 |
| `--keep_going` | 遇到错误继续构建，尽可能发现所有问题 |
| `--verbose_failures` | 失败时输出详细错误信息 |

### 磁盘缓存配置
```bash
# Disable disk cache since we have remote one and aren't using persistent workers.
common --disk_cache=
```
- 禁用本地磁盘缓存，因为使用远程缓存且没有持久化 worker
- 避免 CI 环境中磁盘缓存的额外开销

### Windows 缓存路径配置
```bash
common:windows --repo_contents_cache=D:/a/.cache/bazel-repo-contents-cache
common:windows --repository_cache=D:/a/.cache/bazel-repo-cache
```
- 将缓存目录重定位到 D 盘，与 checkout 在同一卷
- 避免跨卷复制，提高性能

### Linux 远程执行配置
```bash
common:linux --config=remote
common:linux --strategy=remote
common:linux --platforms=//:rbe
```
- 完全远程执行：构建和测试都在远程执行
- 使用 `//:rbe` 平台配置（定义在 `rbe.bzl`）
- 注释提到 Linux 交叉构建尚有问题（libc 约束混乱）

### macOS 混合执行配置
```bash
common:macos --config=remote
common:macos --strategy=remote
common:macos --strategy=TestRunner=darwin-sandbox,local
```
- 构建动作远程执行
- 测试动作在本地 darwin-sandbox 中运行
- 原因：平台特定测试需要在 macOS 上执行

### Windows 配置（未完成）
```bash
# On windows we cannot cross-build the tests but run them locally due to what appears to be a Bazel bug
# (windows vs unix path confusion)
```
- Windows 配置未完成
- 存在 Bazel bug：Windows 与 Unix 路径混淆问题

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.bazelrc` | 根目录 Bazel 主配置 |
| `.github/workflows/ci.bazelrc` | 本 CI 专用配置 |
| `.github/workflows/bazel.yml` | 使用该配置的 CI 工作流 |
| `rbe.bzl` | 远程执行平台定义 |
| `BUILD.bazel` | 平台目标定义 |

### 配置继承关系
```
.bazelrc (通用配置)
    └── --config=remote (远程执行配置)

.github/workflows/ci.bazelrc (CI 专用)
    ├── common:* (通用 CI 配置)
    ├── common:linux (Linux 远程执行)
    ├── common:macos (macOS 混合执行)
    └── common:windows (Windows 配置 - 待完成)
```

### 根目录 .bazelrc 相关配置
```bash
common:remote --extra_execution_platforms=//:rbe
common:remote --remote_executor=grpcs://remote.buildbuddy.io
common:remote --jobs=800
```
- `ci.bazelrc` 引用的 `--config=remote` 在 `.bazelrc` 中定义
- 远程执行使用 BuildBuddy (remote.buildbuddy.io)
- 并行度设置为 800（利用远程执行的高并发能力）

## 依赖与外部交互

### 外部服务
1. **BuildBuddy** (remote.buildbuddy.io)：远程执行和缓存服务
2. **GitHub Actions 运行器**：提供构建环境

### 平台特定依赖
- Linux：完全远程执行，需要 RBE 平台配置
- macOS：本地测试执行，需要 darwin-sandbox
- Windows：配置未完成

## 风险、边界与改进建议

### 风险
1. **Windows 支持缺失**：Windows 配置未完成，阻碍 Windows CI 构建
2. **Linux 交叉构建问题**：注释提到 libc 约束问题需要解决
3. **远程执行依赖**：完全依赖 BuildBuddy，服务不可用时会失败
4. **缓存一致性**：`--remote_download_minimal` 可能导致调试困难

### 边界条件
- 需要 `BUILDBUDDY_API_KEY` 才能使用远程执行
- macOS 测试必须在本地运行（平台特定测试）
- Windows 路径问题需要 Bazel 修复

### 改进建议
1. **完成 Windows 配置**：解决路径问题，启用 Windows 远程执行
2. **Linux 交叉构建**：解决 libc 约束问题，启用 ARM64 Linux 构建
3. **本地回退**：配置远程执行失败时的本地回退策略
4. **调试配置**：添加调试配置便于问题排查
5. **缓存优化**：评估 `--remote_download_minimal` 与调试需求的平衡
6. **文档完善**：添加每个配置项的详细注释说明

### 建议添加的配置
```bash
# 调试配置
common:debug --remote_download_all  # 下载所有输出便于调试
common:debug --explain=explain.log  # 输出构建解释
common:debug --verbose_explanations

# 本地回退配置
common:local-fallback --remote_local_fallback  # 远程失败时本地重试

# 性能分析配置
common:profile --profile=profile.gz  # 生成性能分析数据
```
