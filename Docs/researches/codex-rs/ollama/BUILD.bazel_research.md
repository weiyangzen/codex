# BUILD.bazel 研究文档

## 场景与职责

该文件是 codex-rs/ollama crate 的 Bazel 构建配置，定义了如何将 Rust 源代码编译为可复用的库 crate。作为 OpenAI Codex CLI 的 Ollama 集成模块，它负责与本地 Ollama 服务进行通信，支持模型拉取、版本检查等功能。

## 功能点目的

1. **定义 Rust Library Target**: 使用项目统一的 `codex_rust_crate` 宏创建名为 `ollama` 的库目标
2. **Crate 命名**: 将 Rust crate 名称设置为 `codex_ollama`（遵循 AGENTS.md 中定义的 crate 命名规范：前缀为 `codex-`）
3. **与 Cargo 互操作**: 该 Bazel 配置与同级目录的 `Cargo.toml` 保持同步，确保开发者可以使用 Cargo 或 Bazel 任一工具链构建

## 具体技术实现

### 构建规则

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "ollama",
    crate_name = "codex_ollama",
)
```

### 关键实现细节

- **宏调用**: 使用 `//:defs.bzl` 中定义的 `codex_rust_crate` 宏，该宏封装了复杂的 Bazel Rust 构建逻辑
- **自动依赖解析**: 宏内部通过 `all_crate_deps()` 从 `@crates` 外部仓库解析 Cargo.lock 中定义的依赖
- **源码发现**: 宏自动通过 `native.glob(["src/**/*.rs"])` 发现所有 Rust 源文件
- **测试目标**: 宏自动生成单元测试和集成测试目标（`ollama-unit-tests` 和 `tests/*.rs` 对应的测试）

### defs.bzl 宏的关键行为

根据 `//:defs.bzl` 中的 `codex_rust_crate` 实现（第89-265行）：

1. **库规则创建**: 使用 `rust_library` 创建库目标
2. **单元测试**: 创建 `ollama-unit-tests` 目标，使用 `workspace_root_test` 包装器确保 Insta 快照测试正确运行
3. **特性支持**: 通过 `crate_features` 参数支持条件编译（本 crate 未使用自定义特性）
4. **构建脚本**: 自动检测并处理 `build.rs`（本 crate 无构建脚本）

## 关键代码路径与文件引用

### 源文件结构
```
codex-rs/ollama/
├── BUILD.bazel          # 本文件
├── Cargo.toml           # Cargo 配置
└── src/
    ├── lib.rs           # 库入口，导出公共 API
    ├── client.rs        # OllamaClient 实现（411行）
    ├── parser.rs        # 拉取事件解析器（75行）
    ├── pull.rs          # 进度报告 trait 和实现（147行）
    └── url.rs           # URL 处理工具（39行）
```

### 依赖关系
- **被依赖方**: 
  - `codex-rs/utils/oss` - 调用 `codex_ollama::ensure_oss_ready()` 和 `codex_ollama::ensure_responses_supported()`
  - `codex-rs/core` - 提供 `ModelProviderInfo`, `Config`, `OLLAMA_OSS_PROVIDER_ID`

- **外部依赖**（通过 Cargo.toml / Bazel 解析）:
  - `reqwest` - HTTP 客户端
  - `serde_json` - JSON 序列化
  - `semver` - 版本解析
  - `tokio` - 异步运行时
  - `async-stream` - 异步流生成
  - `bytes` - 字节缓冲区
  - `futures` - 异步 trait
  - `tracing` - 日志追踪
  - `wiremock` - 测试 mock

## 依赖与外部交互

### Bazel 工作空间集成

```
@crates//:defs.bzl          # 提供 all_crate_deps()
@crates//:data.bzl          # 提供 DEP_DATA
@rules_rust//rust:defs.bzl  # 提供 rust_library, rust_test
```

### 运行时依赖
- **Ollama 服务**: 需要本地运行的 Ollama 服务器（默认端口 11434）
- **网络访问**: 用于拉取模型和查询模型列表

## 风险、边界与改进建议

### 风险点

1. **网络依赖测试**: 测试使用 `wiremock` 进行 HTTP mock，但部分测试会检查 `CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR` 环境变量来决定是否跳过，这在沙箱环境中可能导致测试被静默跳过

2. **版本兼容性**: `ensure_responses_supported()` 函数硬编码了最低版本要求（0.13.4），如果 Ollama 版本号格式变化可能导致解析失败

3. **错误处理边界**: `probe_server()` 方法对 OpenAI 兼容端点 (`/v1/models`) 和原生端点 (`/api/tags`) 的探测逻辑不同，如果用户配置了非标准路径可能探测失败

### 边界条件

1. **空模型列表**: `fetch_models()` 在 HTTP 非成功时返回空 Vec，调用方需要处理无模型的情况
2. **版本解析失败**: `fetch_version()` 在版本解析失败时返回 `None` 而非错误，允许调用方继续执行
3. **流式拉取中断**: `pull_model_stream()` 在连接错误时静默结束流，调用方需要通过 `PullEvent::Error` 检测实际错误

### 改进建议

1. **增加健康检查端点配置**: 当前硬编码 `/api/tags` 和 `/v1/models` 作为健康检查端点，可考虑支持自定义健康检查路径

2. **改进错误信息**: `OLLAMA_CONNECTION_ERROR` 是静态字符串，可考虑包含实际尝试连接的 URL 和端口信息

3. **测试覆盖率**: 当前测试主要覆盖 happy path，建议增加以下测试：
   - 网络超时场景
   - 无效 JSON 响应处理
   - 部分完成的模型拉取恢复

4. **Bazel 构建优化**: 考虑添加 `compile_data` 或 `lib_data_extra` 如果未来需要包含模型配置文件

5. **文档生成**: 可通过 Bazel 规则生成 rustdoc 文档并集成到项目文档站点
