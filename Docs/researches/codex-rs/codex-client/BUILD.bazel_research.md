# codex-rs/codex-client/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统对 `codex-client` crate 的构建配置。该文件定义了如何将 Rust 源代码编译成可发布的 crate 库，并管理测试所需的资源文件。

## 功能点目的

### 1. 加载共享构建规则
```starlark
load("//:defs.bzl", "codex_rust_crate")
```
从项目根目录加载 `defs.bzl` 中定义的 `codex_rust_crate` 宏。这是整个 codex-rs 项目统一的 Rust crate 构建规则，确保所有 crate 遵循一致的编译配置、依赖管理和输出规范。

### 2. 定义 crate 构建目标
```starlark
codex_rust_crate(
    name = "codex-client",
    crate_name = "codex_client",
    compile_data = glob(["tests/fixtures/**"]),
)
```

| 属性 | 值 | 说明 |
|------|-----|------|
| `name` | `codex-client` | Bazel 目标名称，用于依赖引用 |
| `crate_name` | `codex_client` | 实际生成的 Rust crate 名称（下划线格式） |
| `compile_data` | `glob(["tests/fixtures/**"])` | 编译时数据文件，包含测试用的证书 fixtures |

## 具体技术实现

### 构建规则继承
`codex_rust_crate` 宏（定义于 `//:defs.bzl`）通常封装了以下行为：
- 自动从 `Cargo.toml` 解析依赖
- 配置 Rust 编译器选项（edition、lints 等）
- 处理 `src/lib.rs` 作为库入口
- 管理 feature flags
- 生成文档和测试目标

### 测试资源管理
`compile_data` 使用 glob 模式包含 `tests/fixtures/` 目录下的所有文件：
- `test-ca.pem` - 测试用 CA 证书
- `test-ca-trusted.pem` - OpenSSL TRUSTED CERTIFICATE 格式测试证书
- `test-intermediate.pem` - 中间证书测试文件

这些 fixtures 被用于：
1. 单元测试中的证书解析验证
2. 子进程集成测试的 CA 配置验证
3. PEM 格式兼容性测试（包括 CRL、TRUSTED CERTIFICATE 等变体）

## 关键代码路径与文件引用

```
codex-rs/codex-client/
├── BUILD.bazel          # 本文件：Bazel 构建配置
├── Cargo.toml           # Rust 依赖和元数据
├── src/
│   └── lib.rs           # 库入口，暴露所有公共 API
├── tests/
│   ├── ca_env.rs        # 子进程 CA 测试
│   └── fixtures/        # 测试证书文件
└── src/bin/
    └── custom_ca_probe.rs  # 测试辅助二进制文件
```

## 依赖与外部交互

### 内部依赖（通过 Workspace）
- `codex-utils-rustls-provider` - Rustls 加密提供者初始化工具
- `codex-utils-cargo-bin` - 测试二进制定位工具

### 外部依赖（通过 Cargo.toml）
- `reqwest` - HTTP 客户端
- `rustls` / `rustls-native-certs` - TLS 配置
- `tokio` - 异步运行时
- `zstd` - 请求压缩

### Bazel 依赖关系
```
//codex-rs/codex-client:codex-client
    ↓ 被依赖
//codex-rs/codex-api
//codex-rs/core
//codex-rs/tui
//codex-rs/backend-client
//codex-rs/login
//codex-rs/cloud-tasks
//codex-rs/rmcp-client
//codex-rs/tui_app_server
```

## 风险、边界与改进建议

### 风险点
1. **测试资源路径依赖**：`glob(["tests/fixtures/**"])` 依赖固定的目录结构，重命名 fixtures 目录会导致测试失败
2. **宏封装黑盒**：`codex_rust_crate` 的具体行为隐藏在 `defs.bzl` 中，需要查看该文件才能理解完整的构建逻辑

### 边界情况
- 空 fixtures 目录：glob 会返回空列表，不会导致构建失败
- 新增测试文件：无需修改 BUILD.bazel，glob 会自动包含

### 改进建议
1. **显式列出 fixtures**：考虑用显式文件列表替代 glob，提高可预测性：
   ```starlark
   compile_data = [
       "tests/fixtures/test-ca.pem",
       "tests/fixtures/test-ca-trusted.pem",
       "tests/fixtures/test-intermediate.pem",
   ]
   ```

2. **添加二进制目标声明**：`custom_ca_probe.rs` 作为 bin target，应在 BUILD.bazel 中显式声明（如果 `codex_rust_crate` 宏未自动处理）

3. **文档注释**：考虑在文件头部添加模块用途注释，说明这是通用 HTTP 传输层的构建配置
