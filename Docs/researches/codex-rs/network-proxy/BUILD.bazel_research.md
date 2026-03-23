# codex-rs/network-proxy/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中用于定义 `codex-network-proxy` crate 构建规则的构建配置文件。该文件位于 `codex-rs/network-proxy/` 目录下，负责声明 Rust 库 crate 的构建目标、依赖关系以及编译选项。

## 功能点目的

该 Bazel 构建文件的核心目的是：

1. **定义 Rust Crate 构建目标**：将 `codex-network-proxy` 声明为一个可重用的 Rust 库 crate
2. **统一构建规则**：通过 `codex_rust_crate` 宏（定义在 `//:defs.bzl`）应用项目统一的 Rust 构建配置
3. **指定 Crate 名称**：将内部 crate 名称 `network-proxy` 映射到外部 crate 名称 `codex_network_proxy`

## 具体技术实现

### 构建规则结构

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "network-proxy",
    crate_name = "codex_network_proxy",
)
```

### 关键配置项

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `"network-proxy"` | Bazel 目标名称，用于内部引用 |
| `crate_name` | `"codex_network_proxy"` | 生成的 Rust crate 名称，遵循 `codex_*` 前缀约定 |

### 构建规则宏

`codex_rust_crate` 宏定义在根目录的 `defs.bzl` 文件中，它封装了：
- Rust 编译器配置
- 标准依赖注入
- 测试规则生成
- 文档生成规则

## 关键代码路径与文件引用

### 直接依赖

| 文件路径 | 关系 | 说明 |
|----------|------|------|
| `//:defs.bzl` | 加载 | 项目级 Rust 构建规则宏 |

### 隐式依赖（通过宏展开）

该 BUILD 文件本身简洁，实际构建逻辑通过 `codex_rust_crate` 宏展开，隐式依赖包括：
- `Cargo.toml` - 用于提取 crate 元数据和依赖
- `src/lib.rs` - crate 入口文件
- 所有 `src/**/*.rs` 源文件

### 源文件结构

```
codex-rs/network-proxy/src/
├── lib.rs           # Crate 入口，模块导出
├── proxy.rs         # 核心代理逻辑（NetworkProxy, NetworkProxyBuilder）
├── http_proxy.rs    # HTTP/HTTPS 代理实现
├── socks5.rs        # SOCKS5 代理实现
├── config.rs        # 配置结构体和解析
├── policy.rs        # 域名策略匹配（allowlist/denylist）
├── network_policy.rs # 网络策略决策 trait 和审计
├── state.rs         # 代理状态管理
├── runtime.rs       # 运行时状态和配置重载
├── mitm.rs          # MITM（中间人）HTTPS 拦截
├── certs.rs         # CA 证书管理
├── upstream.rs      # 上游连接客户端
├── responses.rs     # HTTP 响应构造
├── reasons.rs       # 阻断原因常量
└── mitm_tests.rs    # MITM 模块测试
```

## 依赖与外部交互

### Cargo.toml 依赖

`Cargo.toml` 中定义的依赖会被 Bazel 构建系统处理：

**核心依赖：**
- `rama-*` 系列 (0.3.0-alpha.4) - 代理服务器框架
- `tokio` - 异步运行时
- `anyhow` - 错误处理
- `serde`/`serde_json` - 序列化
- `globset` - 域名模式匹配

**平台特定依赖：**
- `rama-unix` (仅 Unix) - Unix socket 支持

### 内部 Workspace 依赖

- `codex-utils-absolute-path` - 绝对路径处理
- `codex-utils-home-dir` - 家目录解析
- `codex-utils-rustls-provider` - TLS 加密提供器

### 与其他 Bazel 目标的交互

该 crate 被其他 Bazel 目标依赖：
- `codex-rs/core` - 核心库使用网络代理
- `codex-rs/tui` - TUI 应用集成
- 其他需要网络沙箱的组件

## 风险、边界与改进建议

### 当前风险

1. **Alpha 版本依赖**：`rama` 系列依赖使用 `0.3.0-alpha.4` 预发布版本，存在 API 不稳定风险
   - 位置：`Cargo.toml` 第 30-36 行
   - 建议：跟踪 rama 正式版发布，及时升级

2. **平台限制**：Unix socket 功能仅限 macOS，代码中存在大量条件编译
   - 影响：跨平台行为不一致
   - 建议：考虑统一抽象或文档明确说明

### 边界情况

1. **构建模式**：Bazel 构建与 Cargo 构建需要保持同步
   - `MODULE.bazel.lock` 需要定期更新
   - 遵循 AGENTS.md 指引：`just bazel-lock-update`

2. **测试覆盖**：该 crate 包含大量集成测试，Bazel 构建需确保测试资源正确声明

### 改进建议

1. **构建优化**：
   - 考虑添加 `compile_data` 声明（如果添加 `include_str!` 等编译时文件读取）
   - 文档化 `codex_rust_crate` 宏的具体行为

2. **版本管理**：
   - 为 rama 依赖创建 workspace 级别变量，便于统一升级
   - 考虑锁定具体版本避免意外更新

3. **跨平台**：
   - 评估是否可以将 Unix socket 支持扩展到 Linux
   - 或者将平台特定代码分离到独立模块

---

**文档生成时间**：2026-03-23  
**对应代码版本**：基于仓库当前 HEAD 分析
