# codex-rs/app-server/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中定义 `codex-app-server` crate 构建规则的构建配置文件。该文件位于 `codex-rs/app-server/` 目录下，负责声明 Rust 二进制 crate 的构建目标、测试配置和依赖关系。

### 定位
- **所属模块**: `codex-rs/app-server` - Codex 应用服务器核心模块
- **构建系统**: Bazel (通过 rules_rust)
- **Crate 类型**: 二进制可执行文件 + 库

## 功能点目的

### 1. 构建目标定义

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "app-server",
    crate_name = "codex_app_server",
    test_tags = ["no-sandbox"],
)
```

| 属性 | 值 | 说明 |
|------|-----|------|
| `name` | `"app-server"` | Bazel 目标名称 |
| `crate_name` | `"codex_app_server`" | Rust crate 名称（snake_case） |
| `test_tags` | `["no-sandbox"]` | 测试标签，禁用沙箱执行 |

### 2. 关键配置说明

#### `test_tags = ["no-sandbox"]`
- **目的**: 禁用 Bazel 沙箱隔离执行测试
- **原因**: `codex-app-server` 需要访问文件系统、网络、PTY 等系统资源，沙箱环境会限制这些能力
- **影响**: 测试在主机环境中直接运行，需要确保测试的幂等性和隔离性

## 具体技术实现

### 构建规则加载

```bazel
load("//:defs.bzl", "codex_rust_crate")
```

- 从项目根目录的 `defs.bzl` 加载自定义的 `codex_rust_crate` 宏
- 该宏封装了 `rules_rust` 的 `rust_binary` 和 `rust_library` 规则
- 提供统一的 crate 命名、版本管理和依赖处理

### Crate 结构

根据 `Cargo.toml` 中的定义，该 crate 包含：

```toml
[[bin]]
name = "codex-app-server"
path = "src/main.rs"

[[bin]]
name = "codex-app-server-test-notify-capture"
path = "src/bin/notify_capture.rs"

[lib]
name = "codex_app_server"
path = "src/lib.rs"
```

| 组件 | 路径 | 用途 |
|------|------|------|
| 主二进制 | `src/main.rs` | `codex app-server` CLI 入口 |
| 辅助二进制 | `src/bin/notify_capture.rs` | 测试通知捕获工具 |
| 库 | `src/lib.rs` | 供其他 crate 使用的公共 API |

## 关键代码路径与文件引用

### 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `//:defs.bzl` | 依赖 | 项目级 Bazel 宏定义 |
| `Cargo.toml` | 配套 | Rust 包配置和依赖声明 |
| `src/main.rs` | 源文件 | 主程序入口 |
| `src/lib.rs` | 源文件 | 库公共接口 |
| `MODULE.bazel` | 依赖 | Bazel 模块依赖声明 |

### 构建输出

```
bazel-bin/codex-rs/app-server/
├── codex-app-server                    # 主可执行文件
├── codex-app-server-test-notify-capture # 测试工具
└── libcodex_app_server.rlib            # 库文件
```

## 依赖与外部交互

### 构建时依赖

通过 `codex_rust_crate` 宏隐式处理：
- `rules_rust` 提供的 Rust 工具链
- `Cargo.toml` 中声明的 crates.io 依赖
- 工作区内其他 `codex-*` crate

### 运行时依赖

从 `Cargo.toml` 分析的主要依赖类别：

| 类别 | 关键依赖 | 用途 |
|------|----------|------|
| Web 框架 | `axum` | WebSocket 服务器 |
| 异步运行时 | `tokio` | 异步 I/O 和任务调度 |
| 序列化 | `serde`, `serde_json` | JSON-RPC 消息处理 |
| 协议 | `codex-app-server-protocol` | API 类型定义 |
| 核心逻辑 | `codex-core` | 业务逻辑实现 |
| 认证 | `codex-login` | OAuth/API Key 认证 |

## 风险、边界与改进建议

### 当前风险

1. **测试沙箱禁用 (`no-sandbox`)**
   - **风险**: 测试可能相互干扰或影响主机环境
   - **缓解**: 使用临时目录、隔离的数据库文件、独立的端口

2. **构建规则集中化**
   - **风险**: `defs.bzl` 的变更会影响所有 crate
   - **缓解**: 充分的集成测试和渐进式部署

### 边界条件

- 该 BUILD 文件仅定义构建目标，不包含依赖版本信息
- 依赖版本由 `Cargo.toml` 和 `MODULE.bazel.lock` 共同管理
- 测试标签仅影响 Bazel 测试执行，不影响 Cargo 测试

### 改进建议

1. **细化测试标签**
   ```bazel
   test_tags = [
       "no-sandbox",
       "requires-network",
       "requires-pty",
   ],
   ```

2. **添加构建优化配置**
   ```bazel
   rustc_flags = select({
       "//conditions:release": ["-C", "opt-level=3"],
       "//conditions:default": [],
   })
   ```

3. **文档化宏契约**
   - 在 `defs.bzl` 中添加 `codex_rust_crate` 的详细文档
   - 说明预期的目录结构和文件命名约定

### 相关文档

- [AGENTS.md](../../../../AGENTS.md) - 项目级开发规范
- [Cargo.toml](Cargo.toml) - Rust 包配置
- [README.md](README.md) - 应用服务器 API 文档
