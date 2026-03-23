# codex-rs/feedback/BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-feedback` crate 的 Bazel 构建配置文件，位于 `codex-rs/feedback/` 目录下。它定义了如何将 Rust 源代码编译成库 crate，并集成到整个项目的 Bazel 构建系统中。

`codex-feedback` crate 是 Codex CLI 的**用户反馈收集与上传模块**，负责：
1. 在运行时捕获日志和诊断信息
2. 收集用户反馈（bug 报告、使用体验等）
3. 将反馈数据上传到 Sentry 服务

## 功能点目的

### 1. Bazel 构建配置

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "feedback",
    crate_name = "codex_feedback",
)
```

- 使用项目自定义的 `codex_rust_crate` 宏（定义在 `//:defs.bzl`）
- 目标名称：`feedback`（Bazel 目标名）
- Crate 名称：`codex_feedback`（Rust crate 名，用于 `extern crate` 和依赖引用）

### 2. 与 Cargo 的互操作性

该 Bazel 配置与同一目录下的 `Cargo.toml` 保持同步：
- `crate_name = "codex_feedback"` 对应 `Cargo.toml` 中的 `name = "codex-feedback"`
- Bazel 使用下划线命名规范（`codex_feedback`），Cargo 使用连字符（`codex-feedback`）
- 这是 Rust 生态的标准做法：crate 名使用连字符，但库名使用下划线

## 具体技术实现

### 关键流程

1. **构建触发**：当运行 `bazel build //codex-rs/feedback` 时，Bazel 会：
   - 读取 `BUILD.bazel` 确定构建规则
   - 通过 `codex_rust_crate` 宏展开为 `rust_library` 规则
   - 自动发现 `src/**/*.rs` 源文件（由宏实现）
   - 解析 `Cargo.toml` 中的依赖信息（通过 `@crates` 外部仓库）

2. **依赖解析**：
   - 正常依赖（`[dependencies]`）→ `all_crate_deps()` 
   - 开发依赖（`[dev-dependencies]`）→ `all_crate_deps(normal_dev = True)`
   - 内部 workspace 依赖通过 `codex-protocol = { workspace = true }` 解析

3. **测试目标**：
   - 单元测试：`feedback-unit-tests`（通过 `workspace_root_test` 规则包装）
   - 集成测试：如果存在 `tests/*.rs` 文件，会生成对应测试目标

### 数据结构

该 Bazel 文件本身不包含复杂数据结构，但引用的宏 `codex_rust_crate` 支持以下参数（来自 `defs.bzl`）：

| 参数 | 类型 | 说明 |
|------|------|------|
| `name` | string | Bazel 目标名称 |
| `crate_name` | string | Rust crate 名称 |
| `crate_features` | list | 启用的 Cargo features |
| `deps_extra` | list | 额外依赖 |
| `test_tags` | list | 测试标签（如禁用沙箱） |

### 实际生成的目标

根据 `defs.bzl` 中的 `codex_rust_crate` 实现，该配置会生成：

1. `//codex-rs/feedback:feedback` - 主库目标（`rust_library`）
2. `//codex-rs/feedback:feedback-unit-tests-bin` - 单元测试二进制（`rust_test`）
3. `//codex-rs/feedback:feedback-unit-tests` - 可运行的测试目标（`workspace_root_test`）

## 关键代码路径与文件引用

### 本 crate 相关文件

| 文件 | 说明 |
|------|------|
| `codex-rs/feedback/BUILD.bazel` | 本文件，Bazel 构建配置 |
| `codex-rs/feedback/Cargo.toml` | Cargo 构建配置，依赖声明 |
| `codex-rs/feedback/src/lib.rs` | 主库源码，包含反馈收集核心逻辑 |
| `codex-rs/feedback/src/feedback_diagnostics.rs` | 诊断信息收集模块 |

### 依赖的外部定义

| 文件 | 说明 |
|------|------|
| `//:defs.bzl` | 项目级 Bazel 宏定义，包含 `codex_rust_crate` |
| `@crates//:defs.bzl` | 外部仓库，由 `crate_universe` 生成，包含所有 Cargo 依赖 |
| `@crates//:data.bzl` | 包含 `DEP_DATA`，用于获取 crate 的二进制文件信息 |

### 使用方（调用方）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/Cargo.toml` | 依赖 `codex-feedback` |
| `codex-rs/app-server/src/lib.rs` | 导入 `codex_feedback::CodexFeedback` |
| `codex-rs/app-server/src/in_process.rs` | 使用 `CodexFeedback` 进行反馈收集 |
| `codex-rs/tui/Cargo.toml` | 依赖 `codex-feedback` |
| `codex-rs/tui/src/bottom_pane/feedback_view.rs` | 使用 `FeedbackSnapshot` 上传反馈 |
| `codex-rs/tui_app_server/Cargo.toml` | 依赖 `codex-feedback` |
| `codex-rs/exec/Cargo.toml` | 依赖 `codex-feedback` |

## 依赖与外部交互

### 直接依赖（来自 Cargo.toml）

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `codex-protocol` | 内部协议定义（`ThreadId`, `SessionSource`） |
| `sentry` | 反馈上传到 Sentry 服务 |
| `tracing` | 日志追踪框架集成 |
| `tracing-subscriber` | 日志订阅者实现 |

### Bazel 工作空间依赖

```bazel
# 在 WORKSPACE 或 MODULE.bazel 中定义
crate_universe = use_extension("@rules_rust//crate_universe:extension.bzl", "crate_universe")
crate_universe.from_cargo(name = "crates", manifests = ["//codex-rs/Cargo.toml"])
```

所有 Cargo 依赖通过 `crate_universe` 规则生成 Bazel 外部仓库 `@crates`。

## 风险、边界与改进建议

### 风险

1. **DSN 硬编码风险**：`lib.rs` 中硬编码了 Sentry DSN
   ```rust
   const SENTRY_DSN: &str = "https://ae32ed50620d7a7792c1ce5df38b3e3e@o33249.ingest.us.sentry.io/4510195390611458";
   ```
   - 如果 DSN 泄露或需要轮换，需要重新编译
   - 建议：考虑通过环境变量或配置文件注入

2. **网络依赖**：上传反馈依赖外部 Sentry 服务
   - 超时设置：`UPLOAD_TIMEOUT_SECS = 10`
   - 离线环境下反馈会丢失（没有本地队列机制）

3. **隐私风险**：日志可能包含敏感信息
   - 代码中有 `include_logs` 参数控制是否包含日志
   - 但用户可能不小心上传敏感数据

### 边界

1. **环形缓冲区大小**：默认 4 MiB（`DEFAULT_MAX_BYTES = 4 * 1024 * 1024`）
   - 超过后旧日志会被丢弃
   - 长时间运行的会话可能丢失早期日志

2. **标签数量限制**：最多 64 个（`MAX_FEEDBACK_TAGS = 64`）
   - 防止内存无限增长

3. **Bazel/Cargo 同步**：
   - 修改 `Cargo.toml` 后需要运行 `just bazel-lock-update` 更新 Bazel 锁文件
   - 否则 Bazel 构建可能使用旧依赖版本

### 改进建议

1. **构建优化**：
   - 考虑添加 `crate_features` 参数支持条件编译（如禁用 Sentry 上传用于内部部署）

2. **测试覆盖**：
   - 当前测试主要覆盖环形缓冲区和元数据层
   - 建议添加 Sentry 上传的 mock 测试

3. **文档**：
   - 添加 README.md 说明反馈模块的工作原理
   - 说明如何配置 Sentry DSN（如果支持覆盖）

4. **可观测性**：
   - 添加上传成功/失败的指标统计
   - 支持本地日志导出（不依赖 Sentry）
