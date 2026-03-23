# Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 `codex-execpolicy-legacy` crate 的 Cargo 包管理配置文件。它定义了 crate 的元数据、构建目标（二进制 + 库）、依赖项和 lint 规则。该 crate 是一个**遗留的执行策略引擎**，用于验证提议的 `execv(3)` 调用是否安全。

## 功能点目的

### 1. 包元数据定义
- 使用 workspace 继承机制统一管理版本、edition、license
- 描述为 "Legacy exec policy engine for validating proposed exec calls"

### 2. 双目标构建配置
- **二进制目标** (`bin`): `codex-execpolicy-legacy` - 提供 CLI 工具
- **库目标** (`lib`): `codex_execpolicy_legacy` - 提供可复用的策略检查库

### 3. 依赖管理
- 生产依赖：策略解析、Starlark 执行、正则匹配、序列化等
- 开发依赖：仅 `tempfile` 用于测试

### 4. Lint 规则继承
- 继承 workspace 级别的 clippy 和 rustc lint 配置

## 具体技术实现

### 包元数据

```toml
[package]
name = "codex-execpolicy-legacy"
version.workspace = true      # 从 workspace 继承版本
edition.workspace = true      # 从 workspace 继承 edition (2024)
license.workspace = true      # 从 workspace 继承 license (Apache-2.0)
description = "Legacy exec policy engine for validating proposed exec calls."
```

### 双目标配置

```toml
[[bin]]
name = "codex-execpolicy-legacy"
path = "src/main.rs"          # CLI 入口

[lib]
name = "codex_execpolicy_legacy"
path = "src/lib.rs"           # 库入口
```

这种设计允许：
- 作为独立 CLI 工具运行：`cargo run -p codex-execpolicy-legacy -- check ls -l`
- 作为依赖库被其他 crate 使用：`use codex_execpolicy_legacy::ExecvChecker;`

### 依赖项分析

| 依赖 | 用途 |
|------|------|
| `allocative` | 内存分配分析 |
| `anyhow` | 错误处理 |
| `clap` | CLI 参数解析 (derive feature) |
| `derive_more` | 派生宏增强 |
| `env_logger` / `log` | 日志记录 |
| `multimap` | 多值映射数据结构 |
| `path-absolutize` | 路径绝对化 |
| `regex-lite` | 轻量级正则表达式 |
| `serde` / `serde_json` / `serde_with` | 序列化/反序列化 |
| `starlark` | Starlark 语言解析执行（策略文件格式） |
| `tempfile` (dev) | 测试临时文件 |

## 关键代码路径与文件引用

- **库入口**: `src/lib.rs` - 导出所有公共 API
- **CLI 入口**: `src/main.rs` - 实现命令行界面
- **策略文件**: `src/default.policy` - 默认策略规则
- **构建脚本**: `build.rs` - 监控策略文件变更

## 依赖与外部交互

### Workspace 继承
从 `codex-rs/Cargo.toml` 继承：
- `version = "0.0.0"`
- `edition = "2024"`
- `license = "Apache-2.0"`
- 所有依赖的版本号

### 内部 crate 依赖关系
```
codex-execpolicy-legacy
├── 被 codex-exec 依赖（执行模块）
├── 被 codex-core 依赖（核心模块）
└── 与 codex-execpolicy 并存（新版策略引擎）
```

### Starlark 集成
- 使用 `starlark = "0.13.0"` 解析 `.policy` 文件
- 策略文件使用 Python-like 语法定义程序执行规则

## 风险、边界与改进建议

### 风险
1. **Starlark 版本锁定**: 固定使用 0.13.0 版本，升级可能需要策略文件语法调整
2. **双目标维护**: 同时维护 bin 和 lib 目标，API 变更需要同时考虑两者
3. **Legacy 定位**: 明确标记为 "legacy"，意味着未来可能被 `codex-execpolicy` 取代

### 边界
- 仅支持类 Unix 系统的可执行文件检查（`execv_checker.rs` 中的 `is_executable_file` 有 Windows 占位实现）
- 策略文件语法是自定义的 Starlark 方言，学习成本较高

### 改进建议
1. **迁移路径**: 制定从 legacy 到新版的迁移计划，逐步减少对 legacy 的依赖
2. **依赖精简**: `multimap` 可以用标准库的 `HashMap<Vec>` 模式替代，减少依赖
3. **测试增强**: 增加更多集成测试，特别是边界情况（如超长参数、特殊字符等）
4. **文档完善**: 为策略文件的 Starlark DSL 编写更完整的语法文档
