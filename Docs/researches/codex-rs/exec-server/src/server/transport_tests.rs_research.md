# 传输层测试研究文档

## 场景与职责

`transport_tests.rs` 是 codex-exec-server 传输层的单元测试模块，负责验证地址解析逻辑的正确性。该模块确保 `parse_listen_url` 函数能够正确处理各种输入格式，并返回预期的成功或失败结果。

该模块位于 `codex-rs/exec-server/src/server/transport_tests.rs`，通过 `#[path = "transport_tests.rs"]` 属性在 `transport.rs` 中条件编译引入。

## 功能点目的

### 1. 验证默认 URL 解析
- **目的**: 确保默认监听 URL `ws://127.0.0.1:0` 能正确解析
- **测试**: `parse_listen_url_accepts_default_websocket_url`

### 2. 验证标准 WebSocket URL 解析
- **目的**: 确保标准格式的 WebSocket URL 能正确解析为 SocketAddr
- **测试**: `parse_listen_url_accepts_websocket_url`

### 3. 验证无效输入拒绝
- **目的**: 确保非 IP 地址格式（如主机名）被拒绝
- **测试**: `parse_listen_url_rejects_invalid_websocket_url`

### 4. 验证不支持协议拒绝
- **目的**: 确保非 WebSocket 协议（如 HTTP）被拒绝
- **测试**: `parse_listen_url_rejects_unsupported_url`

## 具体技术实现

### 测试组织结构

```rust
#[cfg(test)]
#[path = "transport_tests.rs"]
mod transport_tests;
```

- 使用 `#[cfg(test)]` 条件编译，仅在测试时包含
- 使用 `#[path]` 属性指定测试文件路径
- 保持生产代码与测试代码分离

### 测试用例详解

#### 1. 默认 URL 解析测试
```rust
#[test]
fn parse_listen_url_accepts_default_websocket_url() {
    let bind_address =
        parse_listen_url(DEFAULT_LISTEN_URL).expect("default listen URL should parse");
    assert_eq!(
        bind_address,
        "127.0.0.1:0".parse().expect("valid socket address")
    );
}
```

**测试要点**:
- 验证 `DEFAULT_LISTEN_URL`（`ws://127.0.0.1:0`）能成功解析
- 验证解析结果为 `127.0.0.1:0`
- 使用 `expect` 提供清晰的失败信息

**边界情况**:
- 端口 `0` 表示由操作系统分配
- 解析结果为具体的 SocketAddr，而非字符串

#### 2. 标准 URL 解析测试
```rust
#[test]
fn parse_listen_url_accepts_websocket_url() {
    let bind_address =
        parse_listen_url("ws://127.0.0.1:1234").expect("websocket listen URL should parse");
    assert_eq!(
        bind_address,
        "127.0.0.1:1234".parse().expect("valid socket address")
    );
}
```

**测试要点**:
- 验证指定端口的 URL 能正确解析
- 验证解析结果与输入的 IP 和端口一致

#### 3. 主机名拒绝测试
```rust
#[test]
fn parse_listen_url_rejects_invalid_websocket_url() {
    let err = parse_listen_url("ws://localhost:1234")
        .expect_err("hostname bind address should be rejected");
    assert_eq!(
        err.to_string(),
        "invalid websocket --listen URL `ws://localhost:1234`; expected `ws://IP:PORT`"
    );
}
```

**测试要点**:
- 验证主机名（`localhost`）被拒绝
- 验证错误类型为 `InvalidWebSocketListenUrl`
- 验证错误消息包含原始 URL 和预期格式提示

**设计原因**:
- 避免运行时 DNS 解析
- 确保绑定地址的确定性
- 简化错误处理

#### 4. 不支持协议拒绝测试
```rust
#[test]
fn parse_listen_url_rejects_unsupported_url() {
    let err =
        parse_listen_url("http://127.0.0.1:1234").expect_err("unsupported scheme should fail");
    assert_eq!(
        err.to_string(),
        "unsupported --listen URL `http://127.0.0.1:1234`; expected `ws://IP:PORT`"
    );
}
```

**测试要点**:
- 验证 HTTP 协议被拒绝
- 验证错误类型为 `UnsupportedListenUrl`
- 验证错误消息格式正确

### 测试覆盖矩阵

| 输入 | 预期结果 | 测试函数 |
|------|----------|----------|
| `ws://127.0.0.1:0` | Ok(127.0.0.1:0) | `parse_listen_url_accepts_default_websocket_url` |
| `ws://127.0.0.1:1234` | Ok(127.0.0.1:1234) | `parse_listen_url_accepts_websocket_url` |
| `ws://localhost:1234` | Err(InvalidWebSocketListenUrl) | `parse_listen_url_rejects_invalid_websocket_url` |
| `http://127.0.0.1:1234` | Err(UnsupportedListenUrl) | `parse_listen_url_rejects_unsupported_url` |

### 未覆盖场景

以下场景当前未在测试中覆盖：

1. **IPv6 地址**
   - 输入: `ws://[::1]:8080`
   - 预期: 应成功解析

2. **无效端口**
   - 输入: `ws://127.0.0.1:99999`
   - 预期: 应返回错误

3. **缺少端口**
   - 输入: `ws://127.0.0.1`
   - 预期: 应返回错误

4. **空字符串**
   - 输入: `""`
   - 预期: 应返回错误

5. **特殊字符**
   - 输入: `ws://127.0.0.1:8080/path`
   - 预期: 应返回错误（当前实现会失败，但行为未定义）

## 依赖与外部交互

### 测试依赖

| 依赖项 | 用途 |
|--------|------|
| `pretty_assertions::assert_eq` | 提供更清晰的断言失败输出 |
| `super::DEFAULT_LISTEN_URL` | 测试默认常量 |
| `super::parse_listen_url` | 被测函数 |

### 被测代码

```rust
// transport.rs
pub const DEFAULT_LISTEN_URL: &str = "ws://127.0.0.1:0";

pub(crate) fn parse_listen_url(
    listen_url: &str,
) -> Result<SocketAddr, ExecServerListenUrlParseError> {
    if let Some(socket_addr) = listen_url.strip_prefix("ws://") {
        return socket_addr.parse::<SocketAddr>().map_err(|_| {
            ExecServerListenUrlParseError::InvalidWebSocketListenUrl(listen_url.to_string())
        });
    }

    Err(ExecServerListenUrlParseError::UnsupportedListenUrl(
        listen_url.to_string(),
    ))
}
```

### 运行方式

```bash
# 运行所有测试
cargo test -p codex-exec-server

# 仅运行传输层测试
cargo test -p codex-exec-server transport_tests

# 显示测试输出
cargo test -p codex-exec-server -- --nocapture
```

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖不足**
   - 风险：未覆盖 IPv6、无效端口等边界情况
   - 影响：潜在的生产环境问题
   - 建议：扩展测试用例覆盖更多场景

2. **硬编码错误消息验证**
   - 现状：测试验证完整的错误消息字符串
   - 风险：修改错误消息会破坏测试
   - 建议：仅验证错误类型，或部分匹配消息

3. **无集成测试**
   - 现状：仅单元测试地址解析
   - 风险：无法验证实际的 TCP 绑定和 WebSocket 升级
   - 建议：添加集成测试验证完整流程

### 改进建议

1. **添加 IPv6 测试**
```rust
#[test]
fn parse_listen_url_accepts_ipv6() {
    let bind_address =
        parse_listen_url("ws://[::1]:8080").expect("IPv6 URL should parse");
    assert_eq!(
        bind_address,
        "[::1]:8080".parse().expect("valid IPv6 socket address")
    );
}
```

2. **添加无效端口测试**
```rust
#[test]
fn parse_listen_url_rejects_invalid_port() {
    let err = parse_listen_url("ws://127.0.0.1:99999")
        .expect_err("invalid port should be rejected");
    assert!(matches!(
        err,
        ExecServerListenUrlParseError::InvalidWebSocketListenUrl(_)
    ));
}
```

3. **添加空输入测试**
```rust
#[test]
fn parse_listen_url_rejects_empty() {
    let err = parse_listen_url("").expect_err("empty URL should be rejected");
    assert!(matches!(
        err,
        ExecServerListenUrlParseError::UnsupportedListenUrl(_)
    ));
}
```

4. **使用参数化测试减少重复**
```rust
use test_case::test_case;

#[test_case("ws://127.0.0.1:0" => Ok("127.0.0.1:0".parse().unwrap()); "default")]
#[test_case("ws://127.0.0.1:1234" => Ok("127.0.0.1:1234".parse().unwrap()); "specific port")]
#[test_case("ws://localhost:1234" => Err(...); "hostname rejected")]
#[test_case("http://127.0.0.1:1234" => Err(...); "http rejected")]
fn test_parse_listen_url(input: &str) -> Result<SocketAddr, ExecServerListenUrlParseError> {
    parse_listen_url(input)
}
```

5. **添加集成测试**
```rust
#[tokio::test]
async fn test_websocket_server_accepts_connection() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    
    // 启动服务器
    tokio::spawn(async move {
        run_websocket_listener(addr).await.unwrap();
    });
    
    // 连接客户端
    let (ws_stream, _) = connect_async(format!("ws://{addr}")).await.unwrap();
    
    // 验证连接成功
    assert!(ws_stream.is_active());
}
```

### 相关文件引用

- 本文件：`codex-rs/exec-server/src/server/transport_tests.rs`
- 主模块：`codex-rs/exec-server/src/server/transport.rs`
- 服务器模块：`codex-rs/exec-server/src/server.rs`
- Cargo 配置：`codex-rs/exec-server/Cargo.toml`

### 测试最佳实践

1. **命名规范**: 测试函数使用 `snake_case`，以被测函数名开头
2. **断言消息**: 使用 `expect` 和 `expect_err` 提供清晰的失败描述
3. **精确验证**: 不仅验证成功/失败，还验证具体值
4. **错误消息验证**: 验证错误消息内容，确保用户体验一致
