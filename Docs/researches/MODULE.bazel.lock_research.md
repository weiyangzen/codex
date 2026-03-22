# MODULE.bazel.lock 研究文档

## 概述

`MODULE.bazel.lock` 是 Bazel 构建系统的依赖锁定文件，用于记录项目的精确依赖状态。该文件是 Bazel 的 bzlmod 依赖管理系统的核心组成部分，确保构建的可重现性和一致性。

---

## 场景与职责

### 1.1 核心场景

| 场景 | 说明 |
|------|------|
| **依赖锁定** | 记录所有外部依赖的精确版本和校验和，防止依赖漂移 |
| **构建可重现性** | 确保不同环境、不同时间的构建使用完全相同的依赖 |
| **CI/CD 集成** | 在持续集成中验证依赖一致性，检测未提交的依赖变更 |
| **安全审计** | 通过校验和验证依赖完整性，防止供应链攻击 |

### 1.2 文件职责

- **版本锁定**：精确记录每个依赖模块的版本号
- **完整性验证**：存储每个依赖文件的 SHA256 校验和
- **传递依赖管理**：记录传递依赖的解析结果
- **模块扩展状态**：保存模块扩展（module extensions）的执行结果
- **工具链配置**：记录 Rust 工具链等开发环境的精确配置

---

## 功能点目的

### 2.1 主要功能模块

#### 2.1.1 Registry File Hashes（注册表文件哈希）

```json
"registryFileHashes": {
  "https://bcr.bazel.build/bazel_registry.json": "8a28e4aff06ee60aed2a8c281907fb8bcbf3b753c91fb5a5c57da3215d5b3497",
  "https://bcr.bazel.build/modules/abseil-cpp/20210324.2/MODULE.bazel": "7cd0312e064fde87c8d1cd79ba06c876bd23630c83466e9500321be55c96ace2",
  ...
}
```

**目的**：
- 缓存 Bazel Central Registry (BCR) 中模块的元数据哈希
- 加速依赖解析，避免重复下载
- 验证注册表数据完整性

#### 2.1.2 Selected Yanked Versions（已废弃版本）

```json
"selectedYankedVersions": {}
```

**目的**：
- 记录被标记为废弃（yanked）但仍被项目使用的依赖版本
- 提供安全警告，提醒开发者迁移到稳定版本

#### 2.1.3 Module Extensions（模块扩展）

模块扩展是 Bazel 的动态依赖解析机制，当前文件包含以下扩展：

| 扩展名称 | 用途 |
|---------|------|
| `@@aspect_tools_telemetry+//:extension.bzl%telemetry` | Aspect 工具遥测数据收集 |
| `@@pybind11_bazel+//:internal_configure.bzl%internal_configure_extension` | Pybind11 配置 |
| `@@rules_kotlin+//src/main/starlark/core/repositories:bzlmod_setup.bzl%rules_kotlin_extensions` | Kotlin 规则配置 |
| `@@rules_python+//python/extensions:config.bzl%config` | Python 工具链配置 |
| `@@rules_python+//python/uv:uv.bzl%uv` | Python UV 工具链 |
| `@@rules_rs+//rs:extensions.bzl%crate` | Rust crate 依赖管理 |
| `@@rules_rs+//rs/experimental/toolchains:module_extension.bzl%toolchains` | Rust 工具链管理 |

#### 2.1.4 Facts（依赖事实）

Facts 部分记录了 Rust crate 的详细依赖信息，包括：
- 依赖名称和版本（如 `actix-web_4.12.1`）
- 依赖的传递依赖列表
- 特性（features）配置
- 平台特定的条件依赖

---

## 具体技术实现

### 3.1 数据结构

#### 3.1.1 顶层结构

```json
{
  "lockFileVersion": 26,           // 锁定文件格式版本
  "registryFileHashes": {...},      // 注册表文件哈希映射
  "selectedYankedVersions": {...},  // 废弃版本记录
  "moduleExtensions": {...},        // 模块扩展执行结果
  "facts": {...}                    // 依赖事实（主要是 Rust crates）
}
```

#### 3.1.2 模块扩展结构

```json
"@@rules_rs+//rs:extensions.bzl%crate": {
  "general": {
    "bzlTransitiveDigest": "...",    // Starlark 代码的传递哈希
    "usagesDigest": "...",           // 使用点哈希
    "recordedInputs": [...],         // 记录的输入参数
    "generatedRepoSpecs": {...}      // 生成的仓库规范
  }
}
```

#### 3.1.3 Crate 依赖结构

```json
"crate_name_version": {
  "dependencies": [
    {
      "name": "dependency_name",
      "req": "^1.0",           // 版本要求
      "optional": true/false,   // 是否可选
      "kind": "dev/build",      // 依赖类型
      "features": [...]         // 启用的特性
    }
  ],
  "features": {...}             // 特性定义
}
```

### 3.2 关键流程

#### 3.2.1 依赖解析流程

```
MODULE.bazel (声明依赖)
    ↓
bazel mod deps (解析依赖)
    ↓
查询 Bazel Central Registry
    ↓
下载模块元数据
    ↓
计算传递依赖
    ↓
生成 MODULE.bazel.lock
```

#### 3.2.2 锁定文件更新流程

```bash
# 手动更新
just bazel-lock-update
# 或
bazel mod deps --lockfile_mode=update

# CI 验证
./scripts/check-module-bazel-lock.sh
# 或
bazel mod deps --lockfile_mode=error
```

### 3.3 协议与规范

#### 3.3.1 锁定文件版本

- 当前版本：`26`
- 版本号由 Bazel 定义，表示文件格式兼容性
- 不同版本的 Bazel 可能支持不同的锁定文件版本

#### 3.3.2 哈希算法

- 使用 SHA256 计算文件和依赖的校验和
- 格式：64 位十六进制字符串

#### 3.3.3 仓库标识符规范

- `@@` 前缀表示主模块的依赖
- `+` 后缀表示模块版本分隔符
- 例如：`@@rules_rs+//rs:extensions.bzl%crate`

---

## 关键代码路径与文件引用

### 4.1 相关文件

| 文件 | 用途 |
|------|------|
| `MODULE.bazel` | 声明项目依赖和模块配置 |
| `MODULE.bazel.lock` | 锁定依赖版本（本文件） |
| `.bazelrc` | Bazel 构建配置 |
| `justfile` | 包含锁定文件更新命令 |
| `scripts/check-module-bazel-lock.sh` | CI 验证脚本 |

### 4.2 关键代码引用

#### 4.2.1 MODULE.bazel 中的相关配置

```starlark
# 声明模块名称
module(name = "codex")

# 声明依赖
bazel_dep(name = "platforms", version = "1.0.0")
bazel_dep(name = "llvm", version = "0.6.7")
bazel_dep(name = "rules_rs", version = "0.0.43")

# 使用模块扩展
crate = use_extension("@rules_rs//rs:extensions.bzl", "crate")
crate.from_cargo(
    cargo_lock = "//codex-rs:Cargo.lock",
    cargo_toml = "//codex-rs:Cargo.toml",
    platform_triples = [...],
)
```

#### 4.2.2 justfile 中的相关命令

```makefile
[no-cd]
bazel-lock-update:
    bazel mod deps --lockfile_mode=update

[no-cd]
bazel-lock-check:
    ./scripts/check-module-bazel-lock.sh
```

#### 4.2.3 CI 验证脚本

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! bazel mod deps --lockfile_mode=error; then
  echo "MODULE.bazel.lock is out of date."
  echo "Run 'just bazel-lock-update' and commit the updated lockfile."
  exit 1
fi
```

### 4.3 AGENTS.md 中的相关规范

根据项目 `AGENTS.md` 文件：

> - If you change Rust dependencies (`Cargo.toml` or `Cargo.lock`), run `just bazel-lock-update` from the repo root to refresh `MODULE.bazel.lock`, and include that lockfile update in the same change.
> - After dependency changes, run `just bazel-lock-check` from the repo root so lockfile drift is caught locally before CI.

---

## 依赖与外部交互

### 5.1 外部系统

| 系统 | 交互方式 | 用途 |
|------|---------|------|
| **Bazel Central Registry** | HTTPS API | 获取模块元数据 |
| **crates.io** | 通过 rules_rs | 获取 Rust crate 信息 |
| **GitHub Releases** | HTTP 下载 | Rust 工具链下载 |

### 5.2 内部模块依赖

```
MODULE.bazel.lock
    ← MODULE.bazel (依赖声明)
    ← codex-rs/Cargo.lock (Rust 依赖)
    ← codex-rs/Cargo.toml (Rust 配置)
    ← .bazelrc (构建配置)
```

### 5.3 工具链依赖

锁定文件记录了以下工具链的精确版本：

- **Rust 版本**：1.93.0
- **Rust Edition**：2024
- **支持的平台**：
  - aarch64-unknown-linux-gnu/musl
  - aarch64-apple-darwin
  - aarch64-pc-windows-gnullvm
  - x86_64-unknown-linux-gnu/musl
  - x86_64-apple-darwin
  - x86_64-pc-windows-gnullvm

---

## 风险、边界与改进建议

### 6.1 潜在风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| **锁定文件过期** | 依赖更新后未同步更新锁定文件 | CI 强制检查 `--lockfile_mode=error` |
| **合并冲突** | 多人同时修改依赖导致锁定文件冲突 | 使用 `just bazel-lock-update` 重新生成 |
| **供应链攻击** | 依赖被篡改但哈希未变 | 定期审计依赖来源，使用可信镜像 |
| **版本漂移** | 不同 Bazel 版本生成不同格式的锁定文件 | 统一团队 Bazel 版本（.bazelversion） |

### 6.2 边界情况

1. **Yanked 版本处理**：
   - 当前 `selectedYankedVersions` 为空，表示未使用废弃版本
   - 如果使用了废弃版本，Bazel 会发出警告

2. **平台特定依赖**：
   - 锁定文件包含多平台工具链配置
   - 不同平台可能下载不同的依赖文件

3. **模块扩展失败**：
   - 如果模块扩展执行失败，锁定文件不会更新
   - 需要检查扩展的输入参数是否正确

### 6.3 改进建议

#### 6.3.1 短期改进

1. **自动化更新**：
   ```bash
   # 建议在 pre-commit hook 中添加
   just bazel-lock-check
   ```

2. **依赖变更审查**：
   - 在 PR 模板中添加锁定文件变更检查清单
   - 要求依赖变更必须包含锁定文件更新

3. **文档完善**：
   - 在 `MODULE.bazel` 中添加注释说明依赖用途
   - 记录每个 `bazel_dep` 的具体用途

#### 6.3.2 长期改进

1. **依赖可视化**：
   - 使用 `bazel mod graph` 生成依赖图
   - 集成到文档中帮助理解依赖关系

2. **安全扫描**：
   - 集成 `osv-scanner` 扫描已知漏洞
   - 定期更新依赖以修复安全问题

3. **缓存优化**：
   - 配置 `.bazelrc` 中的远程缓存
   - 减少 CI 中重复下载依赖的时间

4. **版本策略**：
   - 制定依赖更新策略（如每月更新）
   - 评估使用 Dependabot 或 Renovate 自动更新

---

## 附录

### A. 文件统计

- **总行数**：约 1648 行
- **文件大小**：约 1.2 MB
- **锁定格式版本**：26
- **主要模块数量**：40+ 个 Bazel 模块
- **Rust crate 数量**：400+ 个 crates

### B. 常用命令速查

| 命令 | 用途 |
|------|------|
| `just bazel-lock-update` | 更新锁定文件 |
| `just bazel-lock-check` | 验证锁定文件 |
| `bazel mod deps` | 查看依赖树 |
| `bazel mod graph` | 生成依赖图 |
| `bazel fetch //...` | 预取所有依赖 |

### C. 相关文档

- [Bazel bzlmod 文档](https://bazel.build/external/overview)
- [Bazel Central Registry](https://registry.bazel.build/)
- [rules_rs 文档](https://github.com/bazelbuild/rules_rust)
