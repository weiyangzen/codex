# Cargo.toml 研究文档

## 场景与职责

此文件定义了 `codex-responses-api-proxy` crate 的元数据和依赖配置。该 crate 是一个安全敏感的 HTTP 代理服务器，专门用于在特权用户和非特权用户之间安全地传递 OpenAI API 密钥。

## 功能点目的

- **包元数据**: 定义 crate 名称、版本、许可证等基本信息
- **工作区继承**: 使用 workspace 级别的统一配置（版本、edition、许可证）
- **双目标构建**: 同时定义库 (`lib.rs`) 和二进制 (`main.rs`) 构建目标
- **依赖管理**: 声明运行时依赖，包括安全相关的 `zeroize` 和进程加固库

## 具体技术实现

### 包配置

```toml
[package]
name = "codex-responses-api-proxy"
version.workspace = true      # 继承工作区版本
edition.workspace = true      # 继承 Rust edition (2021)
license.workspace = true      # 继承许可证 (Apache-2.0)
```

### 构建目标

#### 库目标
```toml
[lib]
name = "codex_responses_api_proxy"  # 库 crate 名称（下划线命名）
path = "src/lib.rs"                  # 库入口文件
```

#### 二进制目标
```toml
[[bin]]
name = "codex-responses-api-proxy"   # 二进制名称（连字符命名）
path = "src/main.rs"                 # 二进制入口文件
```

**命名差异说明**:
- 库使用 `codex_responses_api_proxy` (Rust 惯例，下划线)
- 二进制使用 `codex-responses-api-proxy` (CLI 惯例，连字符)

### 依赖分析

| 依赖 | 用途 | 特性 |
|------|------|------|
| `anyhow` | 错误处理 | workspace |
| `clap` | CLI 参数解析 | `derive` - 使用派生宏 |
| `codex-process-hardening` | 进程加固 | workspace - 同仓库库 |
| `ctor` | 构造函数属性 | workspace - 用于 `pre_main` |
| `libc` | 系统调用 | workspace - 用于 `mlock` |
| `reqwest` | HTTP 客户端 | `blocking`, `json`, `rustls-tls` |
| `serde` | 序列化框架 | `derive` |
| `serde_json` | JSON 处理 | workspace |
| `tiny_http` | HTTP 服务器 | workspace |
| `zeroize` | 安全内存清零 | workspace - 防止密钥残留 |

### 关键安全依赖

1. **`zeroize`**: 确保 API 密钥在内存中被安全清零，防止通过内存转储泄露
2. **`codex-process-hardening`**: 提供进程级安全加固（禁用 core dump、ptrace 等）
3. **`libc`**: 用于调用 `mlock(2)` 系统调用，将密钥内存锁定在 RAM 中

## 关键代码路径与文件引用

- **当前文件**: `codex-rs/responses-api-proxy/Cargo.toml`
- **工作区配置**: 根目录 `Cargo.toml` (定义 workspace 级别的版本、edition、依赖)
- **库实现**: `codex-rs/responses-api-proxy/src/lib.rs`
- **二进制实现**: `codex-rs/responses-api-proxy/src/main.rs`
- **API 密钥读取**: `codex-rs/responses-api-proxy/src/read_api_key.rs`
- **进程加固库**: `codex-rs/process-hardening/`

## 依赖与外部交互

### 同仓库依赖

```
codex-responses-api-proxy
└── codex-process-hardening (本地路径依赖)
```

### 外部 crates.io 依赖

- `tiny_http` - 轻量级 HTTP 服务器
- `reqwest` - 功能丰富的 HTTP 客户端
- `clap` - 命令行解析标准库
- `zeroize` - 安全内存处理

## 风险、边界与改进建议

### 风险

1. **依赖版本漂移**: 使用 `workspace = true` 意味着依赖版本由工作区统一管理，可能引入意外更新
2. **`ctor` 依赖**: `#[ctor]` 属性宏在进程启动时运行，可能引入不可预测的行为

### 边界

1. **无开发依赖**: 未声明 `[dev-dependencies]`，测试完全依赖工作区配置
2. **无特性标志**: 未定义 `[features]`，所有功能始终启用
3. **固定 reqwest 特性**: `blocking` 特性强制使用同步 API，限制了异步扩展的可能性

### 改进建议

1. **添加描述字段**: 添加 `description` 字段提高 crates.io 发布质量
```toml
description = "Secure HTTP proxy for OpenAI Responses API with API key isolation"
```

2. **考虑添加关键字**: 便于 crates.io 发现
```toml
keywords = ["openai", "proxy", "security", "api-key"]
categories = ["command-line-utilities", "network-programming"]
```

3. **版本约束**: 考虑对安全关键依赖（如 `zeroize`）使用更严格的版本约束

4. **特性分离**: 如果未来需要，可以将 `http-shutdown` 功能设为可选特性
