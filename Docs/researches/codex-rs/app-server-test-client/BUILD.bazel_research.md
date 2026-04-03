# BUILD.bazel 研究文档

## 场景与职责

`codex-rs/app-server-test-client/BUILD.bazel` 是 Bazel 构建系统的配置文件，用于定义 `codex-app-server-test-client` crate 的构建规则。该 crate 是一个测试客户端工具，用于与 Codex app-server 进行交互测试。

## 功能点目的

该 BUILD 文件非常简单，仅使用了一个自定义宏 `codex_rust_crate` 来定义 Rust crate 的构建配置：

1. **crate 命名**: 定义了 crate 的名称为 `app-server-test-client`，对应的 Rust crate 名称为 `codex_app_server_test_client`
2. **标准化构建**: 通过 `codex_rust_crate` 宏统一处理依赖管理、编译选项和测试配置

## 具体技术实现

### 关键代码路径

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "app-server-test-client",
    crate_name = "codex_app_server_test_client",
)
```

### 依赖的宏定义

`codex_rust_crate` 宏定义在 `/home/sansha/Github/codex/defs.bzl` 中（第 89 行起）：

```python
def codex_rust_crate(
        name,
        crate_name,
        crate_features = [],
        crate_srcs = None,
        crate_edition = None,
        proc_macro = False,
        build_script_enabled = True,
        build_script_data = [],
        compile_data = [],
        lib_data_extra = [],
        rustc_flags_extra = [],
        ...
```

该宏封装了 Rust crate 的构建逻辑，包括：
- 自动从 Cargo.toml 解析依赖
- 配置编译选项
- 设置测试规则
- 处理平台特定配置

## 依赖与外部交互

### 内部依赖

根据 `Cargo.toml`，该 crate 依赖以下内部 crate：
- `codex-app-server-protocol`: App Server 协议定义
- `codex-core`: 核心功能
- `codex-otel`: OpenTelemetry 追踪
- `codex-protocol`: 协议类型
- `codex-utils-cli`: CLI 工具函数

### 外部依赖

- `anyhow`: 错误处理
- `clap`: 命令行参数解析
- `serde`/`serde_json`: 序列化
- `tokio`: 异步运行时
- `tracing`/`tracing-subscriber`: 日志追踪
- `tungstenite`: WebSocket 客户端
- `url`: URL 解析
- `uuid`: UUID 生成

## 风险、边界与改进建议

### 风险

1. **构建配置简单但依赖复杂**: 虽然 BUILD 文件简单，但实际的构建逻辑隐藏在 `codex_rust_crate` 宏中，需要理解宏的实现才能调试构建问题

2. **依赖版本一致性**: 依赖版本在 workspace 的 `Cargo.toml` 中定义，需要确保与 Bazel 的 lock 文件同步

### 边界

1. **平台限制**: 某些功能（如 `live-elicitation-timeout-pause`）明确不支持 Windows 平台
2. **测试环境依赖**: 需要预先启动 app-server 或指定 `--codex-bin` 参数

### 改进建议

1. **添加编译数据依赖**: 如果脚本文件（如 `live_elicitation_hold.sh`）需要在编译时嵌入，应添加 `compile_data` 参数

2. **文档化宏行为**: 考虑在 BUILD 文件中添加注释说明 `codex_rust_crate` 宏的主要行为

3. **平台特定配置**: 可以考虑为不同平台添加特定的编译选项或依赖

---

**相关文件引用**:
- 宏定义: `/home/sansha/Github/codex/defs.bzl`
- Cargo 配置: `/home/sansha/Github/codex/codex-rs/app-server-test-client/Cargo.toml`
- Workspace 配置: `/home/sansha/Github/codex/codex-rs/Cargo.toml`
